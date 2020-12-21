//
//  Data.swift
//  
//
//  Created by Yehor Popovych on 12/21/20.
//

import Foundation

public enum WebSocketData {
    case text(String)
    case binary(Data)
    
    public var text: String? {
        switch self {
        case .text(let s): return s
        default: return nil
        }
    }
    
    public var binary: Data? {
        switch self {
        case .binary(let d): return d
        default: return nil
        }
    }
}
