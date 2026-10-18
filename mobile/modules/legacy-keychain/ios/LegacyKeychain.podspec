Pod::Spec.new do |s|
  s.name = 'LegacyKeychain'
  s.version = '1.0.0'
  s.summary = 'Reads the installed Swift app session from Keychain.'
  s.description = s.summary
  s.license = { :type => 'MIT' }
  s.author = 'Rithwik Shetty'
  s.homepage = 'https://github.com/rithwikshetty/tab-it'
  s.source = { :git => 'https://github.com/rithwikshetty/tab-it.git' }
  s.platforms = { :ios => '16.4' }
  s.swift_version = '5.9'
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.frameworks = 'Security'
  s.source_files = '**/*.swift'
end
