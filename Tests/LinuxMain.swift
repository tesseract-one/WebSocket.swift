import XCTest

import WebSocketTests

var tests = [XCTestCaseEntry]()
tests += WebSocketTests.__allTests()

XCTMain(tests)
