Pod::Spec.new do |s|

  s.name         = "BoltProtocol"
  s.module_name  = 'Bolt'
  s.version      = "1.1.0b1"
  s.summary      = "Bolt protocol implementation in Swift"

  s.description  = <<-DESC
The Bolt network protocol is a highly efficient, lightweight client-server protocol designed for database applications.

The reference implementation can be found [here][https://github.com/neo4j-contrib/boltkit]. This is the Swift implementation, and is used by Theo, the Swift Neo4j driver.
DESC

  s.homepage     = "https://github.com/Neo4j-Swift/Bolt-swift"

  s.authors            = { "Niklas Saers" => "niklas@saers.com" }
  s.social_media_url   = "http://twitter.com/niklassaers"

  s.license      = { :type => "BSD", :file => "LICENSE" }

  s.ios.deployment_target = "12.2"
  s.osx.deployment_target = "10.14"
  s.tvos.deployment_target = "10.0"

  s.source       = { :git => "https://github.com/Neo4j-Swift/bolt-swift.git", :branch => "develop/swift-nio", :tag => "#{s.version}" }
  s.source_files  = "Sources"

  s.dependency 'PackStream', '~> 1.1.1'
  s.dependency 'SwiftNIO', '~> 2.0'
  s.dependency 'SwiftNIOTransportServices', '~> 1.0'
  # s.dependency 'SwiftNIOExtras', '~> 1.0'
  s.swift_version = '5.0'
end
