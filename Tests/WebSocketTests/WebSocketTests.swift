//
//  WebSocketTests.swift
//  
//
//  Created by Yehor Popovych on 12/16/20.
//

import XCTest
import WebSocket
import NIO

final class WebSocketTests: XCTestCase {
    func testWebSocketEcho() {
        let closed = expectation(description: "Socket closed")
        
        let socket = WebSocket()
        socket.connect(url: URL(string: "ws://echo.websocket.org")!)
        
        socket.onConnected = { ws in
            ws.send("hello")
        }
        
        socket.onText = { text, ws in
            XCTAssertEqual(text, "hello")
            ws.disconnect()
        }
        
        socket.onDisconnected = { code, _ in
            XCTAssertEqual(code, .normalClosure)
            closed.fulfill()
        }
        
        wait(for: [closed], timeout: 5)
    }
    
    func testWebSocketTLSEcho() {
        let closed = expectation(description: "Socket closed")
        
        let socket = WebSocket()
        socket.connect(url: URL(string: "wss://echo.websocket.org")!)
        
        socket.onConnected = { ws in
            ws.send("hello")
        }
        
        socket.onText = { text, ws in
            XCTAssertEqual(text, "hello")
            ws.disconnect()
        }
        
        socket.onDisconnected = { code, _ in
            XCTAssertEqual(code, .normalClosure)
            closed.fulfill()
        }
        
        wait(for: [closed], timeout: 5)
    }
}
