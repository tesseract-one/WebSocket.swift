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
        socket.connect(url: URL(string: "ws://localhost:8000")!)
        
        socket.onConnected = { ws in
            ws.send("hello")
        }
        
        socket.onData = { data, ws in
            XCTAssertEqual(data.text, "hello")
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
        
        var tlsConf = TLSConfiguration.makeClientConfiguration()
        tlsConf.certificateVerification = .none
        let socket = WebSocket(tlsConfiguration: tlsConf)
        socket.connect(url: URL(string: "wss://localhost:8443")!)
        
        socket.onConnected = { ws in
            ws.send("hello")
        }
        
        socket.onData = { data, ws in
            XCTAssertEqual(data.text, "hello")
            ws.disconnect()
        }
        
        socket.onDisconnected = { code, _ in
            XCTAssertEqual(code, .normalClosure)
            closed.fulfill()
        }
        
        wait(for: [closed], timeout: 5)
    }
    
    func testSharedEventLoopGroup() {
        let closed = expectation(description: "Socket closed")
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        
        var tlsConf = TLSConfiguration.makeClientConfiguration()
        tlsConf.certificateVerification = .none
        let socket = WebSocket(eventLoopGroup: .shared(group), tlsConfiguration: tlsConf)
        
        socket.connect(url: URL(string: "wss://localhost:8443")!)
        
        socket.onConnected = { ws in
            ws.send("hello")
        }
        
        socket.onData = { data, ws in
            XCTAssertEqual(data.text, "hello")
            ws.disconnect()
        }
        
        socket.onDisconnected = { code, _ in
            XCTAssertEqual(code, .normalClosure)
            closed.fulfill()
        }
        
        wait(for: [closed], timeout: 5)
        // Wait for Group to dispatch tasks
        sleep(1)
        // Shutdown group
        XCTAssertNoThrow(try group.syncShutdownGracefully())
    }
}
