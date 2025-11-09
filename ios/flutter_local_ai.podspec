#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_local_ai.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_local_ai'
  s.version          = '0.1.0'
  s.summary          = 'A Flutter plugin for local AI inference on Android and iOS'
  s.description      = <<-DESC
A Flutter package that wraps Android ML Kit GenAI and iOS GenAI APIs for local AI inference.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '18.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
