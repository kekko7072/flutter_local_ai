#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint sign_in_with_apple.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_local_ai'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for handling Flutter Local AI'
  s.description      = <<-DESC
Flutter plugin for handling Flutter Local AI.
                       DESC
  s.homepage         = 'https://github.com/kekko7072/flutter_local_ai'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Francesco Vezzani' => 'pub.dev@vezz.io' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_local_ai/Classes/**/*'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '26.0'
  s.osx.deployment_target = '26.0'

  # Flutter.framework does not contain a i386 slice. Only x86_64 simulators are supported.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
  s.swift_version = '5.0'
end