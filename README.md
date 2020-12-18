# WebSocket.swift

![🐧 linux: ready](https://img.shields.io/badge/%F0%9F%90%A7%20linux-ready-red.svg)
[![GitHub license](https://img.shields.io/badge/license-Apache%202.0-lightgrey.svg)](https://raw.githubusercontent.com/tesseract-one/WebSocket.swift/main/LICENSE)
[![Build Status](https://github.com/tesseract-one/WebSocket.swift/workflows/Build%20%26%20Tests/badge.svg?branch=main)](https://github.com/tesseract-one/WebSocket.swift/actions?query=workflow%3ABuild%20%26%20Tests+branch%3Amain)
[![GitHub release](https://img.shields.io/github/release/tesseract-one/WebSocket.swift.svg)](https://github.com/tesseract-one/WebSocket.swift/releases)
[![SPM compatible](https://img.shields.io/badge/SwiftPM-Compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![CocoaPods version](https://img.shields.io/cocoapods/v/TesseractWebSocket.svg)](https://cocoapods.org/pods/TesseractWebSocket)
![Platform OS X | iOS | tvOS | watchOS | Linux](https://img.shields.io/badge/platform-Linux%20%7C%20OS%20X%20%7C%20iOS%20%7C%20tvOS%20%7C%20watchOS-orange.svg)

## Cross-platform WebSocket client implementation based on Swift NIO

## Goals

We have good WebSocket libraries for Apple platforms, but we need it on Linux too.
This library based on Apple Swift NIO framework, which allows it to be cross-platform.

## Getting started

### Installation

#### [Package Manager](https://swift.org/package-manager/)

Add the following dependency to your [Package.swift](https://github.com/apple/swift-package-manager/blob/master/Documentation/Usage.md#define-dependencies):

```swift
.package(url: "https://github.com/tesseract-one/WebSocket.swift.git", from: "0.0.3")
```

Run `swift build` and build your app.

#### [CocoaPods](http://cocoapods.org/)

Add the following to your [Podfile](http://guides.cocoapods.org/using/the-podfile.html):

```rb
pod 'TesseractWebSocket.swift'
```

Then run `pod install`

### Examples

#### Echo Connection

```swift
import Foundation
import WebSocket

let socket = WebSocket()

socket.onConnected = { ws in
  ws.send("hello")
}

socket.onText = { text, ws in
  print("Received", text)
  assert(text == "hello")
  ws.disconnect()
}

socket.connect(url: URL(string: "wss://echo.websocket.org")!)
```

### WARNING! You should always disconnect WebSocket. It will leak otherwise! And will leak thread too!

## Author

 - [Tesseract Systems, Inc.](mailto:info@tesseract.one)
   ([@tesseract_one](https://twitter.com/tesseract_one))

## License

WebSocket.swift is available under the Apache 2.0 license. See [the LICENSE file](./LICENSE) for more information.
