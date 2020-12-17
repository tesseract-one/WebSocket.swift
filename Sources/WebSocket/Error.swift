//
//  Error.swift
//  
//
//  Created by Yehor Popovych on 12/16/20.
//

import Foundation
import NIOHTTP1

public enum WebSocketError: Error, LocalizedError {
    case invalidURL
    case invalidResponseStatus(head: HTTPResponseHead)
    case transport(error: Error)
    case alreadyConnected
    case disconnected
    
    public var errorDescription: String? {
        return "\(self)"
    }
}
