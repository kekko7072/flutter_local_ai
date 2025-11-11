#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_local_ai.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_local_ai'
  s.version          = '0.0.1-dev.6'
  s.summary          = 'A Flutter package that wraps Android ML Kit GenAI and Apple Foundation Models APIs for local AI inference.'
  s.description      = <<-DESC
A Flutter package that provides a unified API for local AI inference on Android with ML Kit GenAI and on Apple Platforms (iOS and macOS) using Foundation Models.
                       DESC
  s.homepage         = 'https://github.com/kekko7072/flutter_local_ai'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Francesco Vezzani' => 'pub.dev@vezz.io' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.swift'
  s.dependency 'Flutter'
  s.platforms = { :ios => '26.0', :osx => '26.0' }
  s.swift_version = '5.9'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'SWIFT_OBJC_INTERFACE_HEADER_NAME' => 'flutter_local_ai-Swift.h'
  }
  s.swift_versions = ['5.9']
end
