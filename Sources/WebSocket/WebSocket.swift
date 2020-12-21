//
//  WebSocket.swift
//  
//
//  Created by Yehor Popovych on 12/16/20.
//

import Foundation
import NIO
import NIOHTTP1
import NIOConcurrencyHelpers
import NIOWebSocket
import NIOSSL

public class WebSocket {
    private let group: EventLoopGroup
    private let isGroupOwned: Bool
    private let maxFrameSize: Int
    private let tlsConfiguration: TLSConfiguration
    
    private var channel: Channel? = nil
    private var state: WebSocketState = .disconnected
    private var waitingForPong: Bool = false
    private var frameBuffer: WebSocketFrameBuffer? = nil
    private var scheduledTimeoutTask: Scheduled<Void>? = nil
    
    public var isConnected: Bool {
        channel?.isActive ?? false
    }
    
    // Set this interval in onConnected handler.
    public var pingInterval: TimeAmount? {
        didSet {
            if pingInterval != nil && isConnected {
                if scheduledTimeoutTask == nil {
                    waitingForPong = false
                    self._pingAndScheduleNextTimeoutTask()
                }
            } else {
                scheduledTimeoutTask?.cancel()
                scheduledTimeoutTask = nil
            }
        }
    }
    
    public var callbackQueue: DispatchQueue
    public var onData: Optional<(WebSocketData, WebSocket) -> Void> = nil
    public var onPing: Optional<(WebSocket) -> Void> = nil
    public var onPong: Optional<(WebSocket) -> Void> = nil
    public var onConnected: Optional<(WebSocket) -> Void> = nil
    public var onDisconnected: Optional<(WebSocketErrorCode, WebSocket) -> Void> = nil
    public var onError: Optional<(WebSocketError, WebSocket) -> Void> = nil
    
    public init(
        callbackQueue: DispatchQueue = .main,
        eventLoopGroup: WebSocketEventLoopGroupProvider = .createNew(threads: 1),
        tlsConfiguration: TLSConfiguration = .forClient(),
        maxFrameSize: Int = 1 << 14
    ) {
        self.callbackQueue = callbackQueue
        self.onError = {err, _ in print("[WebSocket Error]: \(err)")}
        self.maxFrameSize = maxFrameSize
        self.tlsConfiguration = tlsConfiguration
        self.group = eventLoopGroup.group
        self.isGroupOwned = !eventLoopGroup.isShared
    }
    
    public func connect(to url: String, headers: HTTPHeaders = [:], timeout: TimeAmount = .seconds(10)) throws {
        guard let url = URL(string: url) else {
            throw WebSocketError.invalidURL
        }
        connect(url: url, headers: headers, timeout: timeout)
    }
    
    public func connect(url: URL, headers: HTTPHeaders = [:], timeout: TimeAmount = .seconds(10)) {
        group.next().execute {
            self._connect(url: url, headers: headers, timeout: timeout)
        }
    }
    
    public func disconnect() {
        group.next().execute {
            self._disconnect(code: .normalClosure)
        }
    }
    
    public func send<S>(_ text: S, sent: Optional<(WebSocketError?) -> Void> = nil)
        where S: Collection, S.Element == Character
    {
        _withChannel(error: sent) { channel in
            let string = String(text)
            var buffer = channel.allocator.buffer(capacity: text.count)
            buffer.writeString(string)
            self.send(raw: buffer, opcode: .text, fin: true, sent: sent)
        }
    }
    
    public func send<Data: DataProtocol>(_ data: Data, sent: Optional<(WebSocketError?) -> Void> = nil) {
        _withChannel(error: sent) { channel in
            var buffer = channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            self.send(raw: buffer, opcode: .binary, fin: true, sent: sent)
        }
    }
    
    public func ping(sent: Optional<(WebSocketError?) -> Void> = nil) {
        _withChannel(error: sent) { channel in
            let buffer = channel.allocator.buffer(capacity: 0)
            self.send(raw: buffer, opcode: .ping, fin: true, sent: sent)
        }
    }
    
    public func send(
        raw buffer: ByteBuffer, opcode: WebSocketOpcode, fin: Bool = true,
        sent: Optional<(WebSocketError?) -> Void> = nil
    ) {
        self._handleError(self._send(buffer: buffer, opcode: opcode, fin: fin)) { err in
            sent?(err.map{ err as? WebSocketError ?? .fromNio(error: $0)})
        }
    }
    
    private func _send(
        buffer: ByteBuffer, opcode: WebSocketOpcode, fin: Bool = true
    ) -> EventLoopFuture<Void> {
        guard let channel = channel, isConnected else {
            return group.next().makeFailedFuture(WebSocketError.disconnected)
        }
        let promise = group.next().makePromise(of: Void.self)
        let frame = WebSocketFrame(
            fin: fin,
            opcode: opcode,
            maskKey: _makeMaskKey(),
            data: buffer
        )
        channel.writeAndFlush(frame, promise: promise)
        return promise.futureResult
    }
    
    private func _makeMaskKey() -> WebSocketMaskingKey {
        return WebSocketMaskingKey((0..<4).map{_ in UInt8.random(in: .min ..< .max)})!
    }
    
    // isn't thread safe
    private func _connected(channel: Channel) -> EventLoopFuture<Void> {
        self.channel = channel
        return channel.pipeline.addHandler(WebSocketHandler(webSocket: self)).map { [weak self] in
            guard let sself = self else { return }
            if let code = sself.state.disconnecting {
                sself.state = .connected
                sself._disconnect(code: code)
                sself.callbackQueue.async { sself.onConnected?(sself) }
            } else {
                sself.state = .connected
                if sself.pingInterval != nil {
                    sself._pingAndScheduleNextTimeoutTask()
                }
                sself.callbackQueue.async { sself.onConnected?(sself) }
            }
        }
    }
    
    // isn't thread safe
    private func _disconnected(code: WebSocketErrorCode) {
        state = .disconnected
        channel!.close(mode: .all, promise: nil)
        channel = nil
        scheduledTimeoutTask?.cancel()
        scheduledTimeoutTask = nil
        waitingForPong = false
        callbackQueue.async { self.onDisconnected?(code, self) }
    }
    
    // isn't thread safe
    private func _pingAndScheduleNextTimeoutTask() {
        guard isConnected, let pingInterval = pingInterval else {
            return
        }
        if waitingForPong {
            // We never received a pong from our last ping, so the connection has timed out
            _disconnect(code: .unknown(1006))
        } else {
            ping()
            waitingForPong = true
            scheduledTimeoutTask = group.next().scheduleTask(deadline: .now() + pingInterval) { [weak self] in
                self?._pingAndScheduleNextTimeoutTask()
            }
        }
    }
    
    // isn't thread safe
    private func _connect(url: URL, headers: HTTPHeaders, timeout: TimeAmount) {
        guard channel == nil, state.isDisconnected else {
            self._error(WebSocketError.alreadyConnected)
            return
        }
        state = .connecting
        
        let scheme = url.scheme ?? "ws"
        let host = url.host ?? "localhost"
        let port = url.port ?? (scheme == "wss" ? 443 : 80)
        let path = url.path
        
        let reqKey = Data((0..<16).map{_ in UInt8.random(in: .min ..< .max)}).base64EncodedString()
        
        let upgradePromise = group.next().makePromise(of: Void.self)
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .connectTimeout(timeout)
            .channelInitializer { channel in
                let httpHandler = HTTPInitialRequestHandler(
                    host: host,
                    path: path,
                    headers: headers,
                    upgradePromise: upgradePromise
                )
                
                let websocketUpgrader = NIOWebSocketClientUpgrader(
                    requestKey: reqKey,
                    maxFrameSize: self.maxFrameSize,
                    automaticErrorHandling: true,
                    upgradePipelineHandler: { channel, req in
                        return self._connected(channel: channel)
                    }
                )
                
                let config: NIOHTTPClientUpgradeConfiguration = (
                    upgraders: [websocketUpgrader],
                    completionHandler: { context in
                        upgradePromise.succeed(())
                        channel.pipeline.removeHandler(httpHandler, promise: nil)
                    }
                )
                
                let future: EventLoopFuture<Void>
                
                if scheme == "wss" {
                    do {
                        let context = try NIOSSLContext(configuration: self.tlsConfiguration)
                        let tlsHandler = try NIOSSLClientHandler(context: context, serverHostname: host)
                        future = channel.pipeline.addHandler(tlsHandler)
                    } catch {
                        return channel.pipeline.close(mode: .all)
                    }
                } else {
                    future = self.group.next().makeSucceededFuture(())
                }
                
                return future.flatMap {
                    channel.pipeline.addHTTPClientHandlers(
                        leftOverBytesStrategy: .forwardBytes,
                        withClientUpgrade: config
                    )
                }.flatMap {
                    channel.pipeline.addHandler(httpHandler)
                }
            }
        
        let connect = bootstrap.connect(host: host, port: port)
        connect.cascadeFailure(to: upgradePromise)
        let connected = connect.flatMap { _ in upgradePromise.futureResult }
        connected.whenFailure { err in
            self.state = .disconnected
            self._error(err)
        }
    }
    
    // isn't thread safe
    private func _disconnect(code: WebSocketErrorCode) {
        _handleError(close(code: code))
    }
    
    private func _withChannel(
        error: Optional<(WebSocketError) -> Void> = nil,
        _ f: @escaping (Channel) -> Void
    ) {
        guard let channel = channel, isConnected else {
            _error(WebSocketError.disconnected)
            callbackQueue.async { error?(.disconnected) }
            return
        }
        f(channel)
    }
    
    private func _error(_ error: Error) {
        let fixed = error as? WebSocketError ?? .fromNio(error: error)
        self.callbackQueue.async { self.onError?(fixed, self) }
    }
    
    private func _handleError(_ future: EventLoopFuture<Void>, cb: Optional<(Error?) -> Void> = nil) {
        future.whenComplete { result in
            switch result {
            case .success(_): self.callbackQueue.async { cb?(nil) }
            case .failure(let err):
                self.callbackQueue.async { cb?(err) }
                self._error(err)
            }
        }
    }
    
    deinit {
        if (isGroupOwned) {
            group.shutdownGracefully { error in
                if let err = error {
                    fatalError("Can't shutdown EventLoopGroup: \(err)")
                }
            }
        }
    }
}

// internal methods
extension WebSocket {
    // isn't thread safe
    func handle(frame: WebSocketFrame) {
        switch frame.opcode {
        case .connectionClose: _handleClose(frame: frame)
        case .ping: _handlePing(frame: frame)
        case .binary, .text, .pong: _handleData(frame: frame)
        case .continuation: _handleContinuation(frame: frame)
        default: break
        }
        
        // if this frame was final and we have a non-nil frame sequence,
        // output it to the websocket and clear storage
        if var frameSequence = frameBuffer, frame.fin {
            switch frameSequence.type {
            case .binary:
                callbackQueue.async { self.onData?(.binary(frameSequence.data()!), self) }
            case .text:
                callbackQueue.async { self.onData?(.text(frameSequence.string()!), self) }
            case .pong:
                waitingForPong = false
                callbackQueue.async { self.onPong?(self) }
            default: break
            }
            frameBuffer = nil
        }
    }
    
    // isn't thread safe
    func close(code: WebSocketErrorCode) -> EventLoopFuture<Void> {
        switch state {
        case .connected:
            state = .disconnecting(code: code)
            
            let codeAsInt = UInt16(webSocketErrorCode: code)
            let codeToSend: WebSocketErrorCode
            if codeAsInt == 1005 || codeAsInt == 1006 {
                /// Code 1005 and 1006 are used to report errors to the application, but must never be sent over
                /// the wire (per https://tools.ietf.org/html/rfc6455#section-7.4)
                codeToSend = .normalClosure
            } else {
                codeToSend = code
            }

            var buffer = channel!.allocator.buffer(capacity: 2)
            buffer.write(webSocketErrorCode: codeToSend)

            return _send(buffer: buffer, opcode: .connectionClose, fin: true)
        case .connecting:
            state = .disconnecting(code: code)
            return group.next().makeSucceededFuture(())
        default: return group.next().makeSucceededFuture(())
        }
    }
    
    // isn't thread safe
    private func _handleClose(frame: WebSocketFrame) {
        if let code = state.disconnecting {
            // peer confirmed close, time to close channel
            _disconnected(code: code)
        } else {
            // peer asking for close, confirm and close output side channel
            var data = frame.data
            let maskingKey = frame.maskKey
            if let maskingKey = maskingKey {
                data.webSocketUnmask(maskingKey)
            }
            let code = data.readWebSocketErrorCode() ?? .unknown(1005)
            close(code: code).whenComplete { _ in
                self._disconnected(code: code)
            }
        }
    }
    
    // isn't thread safe
    private func _handleData(frame: WebSocketFrame) {
        var frameSequence = frameBuffer ?? WebSocketFrameBuffer(type: frame.opcode)
        do {
            // append this frame and update the sequence
            try frameSequence.append(frame)
            frameBuffer = frameSequence
        } catch {
            _disconnect(code: .protocolError)
        }
    }
    
    // isn't thread safe
    private func _handleContinuation(frame: WebSocketFrame) {
        if var frameSequence = frameBuffer {
            do {
                // append this frame and update
                try frameSequence.append(frame)
                frameBuffer = frameSequence
            } catch {
                _disconnect(code: .protocolError)
            }
        } else {
            _disconnect(code: .protocolError)
        }
    }
    
    // isn't thread safe
    private func _handlePing(frame: WebSocketFrame) {
        if frame.fin {
            var frameData = frame.data
            let maskingKey = frame.maskKey
            if let maskingKey = maskingKey {
                frameData.webSocketUnmask(maskingKey)
            }
            send(raw: frameData, opcode: .pong, fin: true)
            callbackQueue.async { self.onPing?(self) }
        } else {
            _disconnect(code: .protocolError)
        }
    }
}
