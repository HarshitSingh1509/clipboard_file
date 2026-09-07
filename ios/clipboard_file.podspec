#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint clipboard_file.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'clipboard_file'
  s.version          = '0.1.1'
  s.summary          = 'Read and copy files from the system clipboard on iOS and Android.'
  s.description      = <<-DESC
Read images, PDFs, Office documents, CSV, and other files from the clipboard on iOS and Android.
                       DESC
  s.homepage         = 'https://github.com/HarshitSingh1509/clipboard_file'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Harshit Singh' => 'harshitsingh15sept@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {'clipboard_file_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
