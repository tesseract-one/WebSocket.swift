//
//  EventLoopGroup.swift
//  
//
//  Created by Yehor Popovych on 12/17/20.
//

import Foundation
import NIO

public enum WebSocketEventLoopGroupProvider {
    case createNew(threads: Int)
    case shared(EventLoopGroup)
    
    public var isShared: Bool {
        switch self {
        case .createNew: return false
        case .shared: return true
        }
    }
    
    public var group: EventLoopGroup {
        switch self {
        case .createNew(threads: let t): return MultiThreadedEventLoopGroup(numberOfThreads: t)
        case .shared(let group): return group
        }
    }
}
