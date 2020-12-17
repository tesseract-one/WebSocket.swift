//
//  EventLoopGroup.swift
//  
//
//  Created by Yehor Popovych on 12/17/20.
//

import Foundation
import NIO

public enum WebSocketEventLoopGroup {
    case createNew
    case shared(EventLoopGroup)
    
    public var isShared: Bool {
        switch self {
        case .createNew: return false
        case .shared: return true
        }
    }
    
    public var group: EventLoopGroup {
        switch self {
        case .createNew: return MultiThreadedEventLoopGroup(numberOfThreads: 1)
        case .shared(let group): return group
        }
    }
}
