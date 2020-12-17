//
//  FrameBuffer.swift
//  
//
//  Created by Yehor Popovych on 12/17/20.
//

import Foundation
import NIO
import NIOWebSocket
import NIOFoundationCompat

struct WebSocketFrameBuffer {
    var buffer: ByteBuffer
    var type: WebSocketOpcode

    init(type: WebSocketOpcode) {
        self.buffer = ByteBufferAllocator().buffer(capacity: 0)
        self.type = type
    }

    mutating func append(_ frame: WebSocketFrame) throws {
        guard frame.opcode == type else {
            throw WebSocketError.opcodeMismatch(buffer: type, frame: frame.opcode)
        }
        var data = frame.unmaskedData
        buffer.writeBuffer(&data)
    }
    
    mutating func string() -> String? {
        if case .text = type {
            return buffer.readString(length: buffer.readableBytes)
        }
        return nil
    }
    
    mutating func data() -> Data? {
        if case .binary = type {
            return buffer.readData(length: buffer.readableBytes)
        }
        return nil
    }
}
