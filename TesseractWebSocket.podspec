Pod::Spec.new do |s|
  s.name             = 'TesseractWebSocket'
  s.version          = '0.0.2'
  s.summary          = 'Cross-platform WebSocket client implementation based on Swift NIO'

  s.description      = <<-DESC
This library uses Swift NIO asynchronous networking framework for WebSocket client implementation.
Library tested on all Apple platforms and Linix
                       DESC

  s.homepage         = 'https://github.com/tesseract-one/WebSocket.swift'

  s.license          = { :type => 'Apache 2.0', :file => 'LICENSE' }
  s.author           = { 'Tesseract Systems, Inc.' => 'info@tesseract.one' }
  s.source           = { :git => 'https://github.com/tesseract-one/WebSocket.swift.git', :tag => s.version.to_s }

  s.ios.deployment_target = '10.0'
  s.osx.deployment_target = '10.12'
  s.tvos.deployment_target = '10.0'
  s.watchos.deployment_target = '6.0'
  
  s.swift_versions = ['5', '5.1', '5.2']

  s.module_name = 'WebSocket'
  
  s.source_files = 'Sources/WebSocket/**/*.swift'

  s.dependency 'SwiftNIO', '~> 2.11'
  s.dependency 'SwiftNIOHTTP1', '~> 2.11'
  s.dependency 'SwiftNIOWebSocket', '~> 2.11'
  s.dependency 'SwiftNIOConcurrencyHelpers', '~> 2.11'
  s.dependency 'SwiftNIOFoundationCompat', '~> 2.11'
  s.dependency 'SwiftNIOSSL', '~> 2.0'
  
  s.test_spec 'WebSocketTests' do |test_spec|
    test_spec.platforms = {:ios => '10.0', :osx => '10.12', :tvos => '10.0'}
    test_spec.source_files = 'Tests/WebSocketTests/**/*.swift'
  end
end
