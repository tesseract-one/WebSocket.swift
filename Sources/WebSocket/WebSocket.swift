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
    private let maxFrameSize: Int
    private let tlsConfiguration: TLSConfiguration
    
    private var channel: Channel? = nil
    private var connecting: Bool = false
    private var waitingForClose: WebSocketErrorCode? = nil
    private var waitingForPong: Bool = false
    private var frameBuffer: WebSocketFrameBuffer? = nil
    private var scheduledTimeoutTask: Scheduled<Void>? = nil
    
    public var isConnected: Bool {
        channel?.isActive ?? false
    }
    
    // Set this interval in onConnected handler.
    public var pingInterval: TimeAmount? {
        didSet {
            if pingInterval != nil {
                if scheduledTimeoutTask == nil {
                    waitingForPong = false
                    self.pingAndScheduleNextTimeoutTask()
                }
            } else {
                scheduledTimeoutTask?.cancel()
                scheduledTimeoutTask = nil
            }
        }
    }
    
    public var callbackQueue: DispatchQueue
    public var onText: Optional<(String, WebSocket) -> Void> = nil
    public var onData: Optional<(Data, WebSocket) -> Void> = nil
    public var onPing: Optional<(WebSocket) -> Void> = nil
    public var onPong: Optional<(WebSocket) -> Void> = nil
    public var onConnected: Optional<(WebSocket) -> Void> = nil
    public var onDisconnected: Optional<(WebSocketErrorCode, WebSocket) -> Void> = nil
    public var onError: Optional<(WebSocketError, WebSocket) -> Void> = nil
    
    public init(
        callbackQueue: DispatchQueue = .main,
        tlsConfiguration: TLSConfiguration = .forClient(),
        maxFrameSize: Int = 1 << 14
    ) {
        self.callbackQueue = callbackQueue
        self.onError = {err, _ in print("[WebSocket Error]: \(err)")}
        self.maxFrameSize = maxFrameSize
        self.tlsConfiguration = tlsConfiguration
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }
    
    public func connect(to url: String, headers: HTTPHeaders = [:]) throws {
        guard let url = URL(string: url) else {
            throw WebSocketError.invalidURL
        }
        connect(url: url, headers: headers)
    }
    
    public func connect(url: URL, headers: HTTPHeaders = [:]) {
        guard channel == nil, !connecting else {
            callbackQueue.async { self.onError?(.alreadyConnected, self) }
            return
        }
        
        connecting = true
        
        let scheme = url.scheme ?? "ws"
        let host = url.host ?? "localhost"
        let port = url.port ?? (scheme == "wss" ? 443 : 80)
        let path = url.path
        
        let reqKey = Data((0..<16).map{_ in UInt8.random(in: .min ..< .max)}).base64EncodedString()
        
        let upgradePromise = group.next().makePromise(of: Void.self)
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
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
            self.connecting = false
            self.callbackQueue.async { self.onError?(.transport(error: err), self) }
        }
    }
    
    public func disconnect() {
        self._handleError(close(code: .normalClosure))
    }
    
    public func send<S>(_ text: S) where S: Collection, S.Element == Character {
        _withChannel { channel in
            let string = String(text)
            var buffer = channel.allocator.buffer(capacity: text.count)
            buffer.writeString(string)
            self._handleError(self.send(raw: buffer, opcode: .text, fin: true))
        }
    }
    
    public func send<Data: DataProtocol>(_ data: Data) {
        _withChannel { channel in
            var buffer = channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            self._handleError(self.send(raw: buffer, opcode: .binary, fin: true))
        }
    }
    
    public func ping() {
        _withChannel { channel in
            let buffer = channel.allocator.buffer(capacity: 0)
            self._handleError(self.send(raw: buffer, opcode: .ping, fin: true))
        }
    }
    
    public func send(raw buffer: ByteBuffer, opcode: WebSocketOpcode, fin: Bool = true) -> EventLoopFuture<Void> {
        guard let channel = channel else {
            return group.next().makeFailedFuture(WebSocketError.disconnected)
        }
        let promise = group.next().makePromise(of: Void.self)
        let frame = WebSocketFrame(
            fin: fin,
            opcode: opcode,
            maskKey: makeMaskKey(),
            data: buffer
        )
        channel.writeAndFlush(frame, promise: promise)
        return promise.futureResult
    }
    
    private func makeMaskKey() -> WebSocketMaskingKey {
        return WebSocketMaskingKey((0..<4).map{_ in UInt8.random(in: .min ..< .max)})!
    }
    
    private func _connected(channel: Channel) -> EventLoopFuture<Void> {
        self.channel = channel
        return channel.pipeline.addHandler(WebSocketHandler(webSocket: self)).map { [weak self] in
            guard let sself = self else { return }
            sself.connecting = false
            sself.callbackQueue.async { sself.onConnected?(sself) }
        }
    }
    
    private func _disconnected(code: WebSocketErrorCode) {
        channel!.close(mode: .all, promise: nil)
        channel = nil
        waitingForClose = nil
        scheduledTimeoutTask?.cancel()
        scheduledTimeoutTask = nil
        callbackQueue.async { self.onDisconnected?(code, self) }
    }
    
    private func pingAndScheduleNextTimeoutTask() {
        guard let channel = channel, channel.isActive, let pingInterval = pingInterval else {
            return
        }
        if waitingForPong {
            // We never received a pong from our last ping, so the connection has timed out
            self.close(code: .unknown(1006)).whenComplete { _ in
                self._disconnected(code: .unknown(1006))
            }
        } else {
            ping()
            waitingForPong = true
            scheduledTimeoutTask = group.next().scheduleTask(
                deadline: .now() + pingInterval,
                pingAndScheduleNextTimeoutTask
            )
        }
    }
    
    private func _withChannel(_ f: @escaping (Channel) -> Void) {
        guard let channel = channel else {
            self.callbackQueue.async {
                self.onError?(WebSocketError.disconnected, self)
            }
            return
        }
        f(channel)
    }
    
    private func _handleError<R>(_ future: EventLoopFuture<R>) {
        future.whenFailure { error in
            let fixed = error as? WebSocketError ?? .transport(error: error)
            self.callbackQueue.async { self.onError?(fixed, self) }
        }
    }
    
    deinit {
        assert (channel == nil, "WebSocket isn't disconnected")
        try! self.group.syncShutdownGracefully()
    }
}

// internal methods
extension WebSocket {
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
                callbackQueue.async { self.onData?(frameSequence.data()!, self) }
            case .text:
                callbackQueue.async { self.onText?(frameSequence.string()!, self) }
            case .pong:
                self.waitingForPong = false
                callbackQueue.async { self.onPong?(self) }
            case .ping:
                callbackQueue.async { self.onPing?(self) }
            default: break
            }
            frameBuffer = nil
        }
    }
    
    func close(code: WebSocketErrorCode) -> EventLoopFuture<Void> {
        if isConnected && waitingForClose == nil {
            waitingForClose = code
            
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

            return send(raw: buffer, opcode: .connectionClose, fin: true)
        } else {
            return group.next().makeSucceededFuture(())
        }
    }
    
    private func _handleClose(frame: WebSocketFrame) {
        if let code = waitingForClose {
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
    
    private func _handleData(frame: WebSocketFrame) {
        var frameSequence = frameBuffer ?? WebSocketFrameBuffer(type: frame.opcode)
        // append this frame and update the sequence
        frameSequence.append(frame)
        frameBuffer = frameSequence
    }
    
    private func _handleContinuation(frame: WebSocketFrame) {
        if var frameSequence = frameBuffer {
            // append this frame and update
            frameSequence.append(frame)
            frameBuffer = frameSequence
        } else {
            _handleError(close(code: .protocolError))
        }
    }
    
    private func _handlePing(frame: WebSocketFrame) {
        if frame.fin {
            var frameData = frame.data
            let maskingKey = frame.maskKey
            if let maskingKey = maskingKey {
                frameData.webSocketUnmask(maskingKey)
            }
            _handleError(send(raw: frameData, opcode: .pong, fin: true))
        } else {
            _handleError(close(code: .protocolError))
        }
    }
}