$stderr.sync = true
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
stage = ->(name) { $stderr.puts("apple-control #{name} elapsed_ms=#{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(3)}") }
stage.call('ruby-start')
require 'xcodeproj'
require 'fileutils'
stage.call('libraries-loaded')

# Xcode requires a host for its UI-test target relationship. The tests
# address Otzaria by bundle ID without changing the real app project.
root, sources = ARGV
raise 'root and sources are required' unless root && sources
FileUtils.mkdir_p(root)
File.write(File.join(root, 'Host.swift'), <<~SWIFT)
  import UIKit
  @main final class Host: UIResponder, UIApplicationDelegate {
      var window: UIWindow?
      func application(_ application: UIApplication,
          didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
          window = UIWindow(frame: UIScreen.main.bounds)
          window?.rootViewController = UIViewController()
          window?.makeKeyAndVisible()
          return true
      }
  }
SWIFT
FileUtils.cp(File.join(sources, 'AppleQuietControl.swift'), root)
stage.call('sources-written')
project = Xcodeproj::Project.new(File.join(root, 'Control.xcodeproj'))
host = project.new_target(:application, 'QuietHost', :ios, '15.0')
tests = project.new_target(:ui_test_bundle, 'AppleQuietControl', :ios, '15.0')
tests.add_dependency(host)
host.add_file_references([project.main_group.new_file('Host.swift')])
tests.add_file_references(%w[AppleQuietControl.swift ControlConfig.swift].map { |f| project.main_group.new_file(f) })
[host, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => "org.otzaria.quiet.#{target.name}",
      'SWIFT_VERSION' => '5.0',
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'TARGETED_DEVICE_FAMILY' => '1,2',
      'CODE_SIGNING_ALLOWED' => 'NO'
    })
  end
end
tests.build_configurations.each do |config|
  config.build_settings['TEST_TARGET_NAME'] = 'QuietHost'
  config.build_settings['ENABLE_TESTING_SEARCH_PATHS'] = 'YES'
end
project.root_object.attributes['TargetAttributes'] = {
  tests.uuid => { 'TestTargetID' => host.uuid }
}
project.save
stage.call('project-saved')
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(host)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.save_as(project.path, 'AppleQuietControl', true)
stage.call('scheme-saved')
