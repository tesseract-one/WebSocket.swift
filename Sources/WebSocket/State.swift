//
//  State.swift
//  
//
//  Created by Yehor Popovych on 12/21/20.
//

import Foundation
import NIOWebSocket

enum WebSocketState: Equatable {
    case connecting
    case connected
    case disconnecting(code: WebSocketErrorCode)
    case disconnected
    
    var isConnected: Bool {
        switch self {
        case .connected: return true
        default: return false
        }
    }
    
    var isConnecting: Bool {
        switch self {
        case .connecting: return true
        default: return false
        }
    }
    
    var isDisconnected: Bool {
        switch self {
        case .disconnected: return true
        default: return false
        }
    }
    
    var disconnecting: WebSocketErrorCode? {
        switch self {
        case .disconnecting(code: let code): return code
        default: return nil
        }
    }
}
