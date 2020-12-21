//
//  Error.swift
//  
//
//  Created by Yehor Popovych on 12/16/20.
//

import Foundation
import NIOHTTP1
import NIOWebSocket

public enum WebSocketError: Error, LocalizedError {
    case invalidURL
    case invalidResponseStatus(head: HTTPResponseHead)
    case connectTimeout
    case alreadyConnected
    case disconnected
    case opcodeMismatch(buffer: WebSocketOpcode, frame: WebSocketOpcode)
    case transport(error: Error)
    
    public var errorDescription: String? {
        return "\(self)"
    }
}

extension WebSocketError {
    public static func fromNio(error: Error) -> WebSocketError {
        if let channel = error as? ChannelError {
            switch channel {
            case .connectTimeout: return .connectTimeout
            case .connectPending: return .alreadyConnected
            case .alreadyClosed, .ioOnClosedChannel, .outputClosed, .inputClosed: return .disconnected
            default: return .transport(error: error)
            }
        } else {
            return .transport(error: error)
        }
    }
}
