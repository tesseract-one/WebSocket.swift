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
    case opcodeMismatch(buffer: WebSocketOpcode, frame: WebSocketOpcode)
    case transport(error: Error)
    case alreadyConnected
    case disconnected
    
    public var errorDescription: String? {
        return "\(self)"
    }
}
