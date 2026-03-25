platform :osx, '13.0'

project 'HostsEditor.xcodeproj'

install! 'cocoapods', :warn_for_unused_master_specs_repo => false

inhibit_all_warnings!

target 'HostsEditor' do
  use_frameworks! :linkage => :static

  # pod 'ViewScopeServer', :path => '/Users/VanJay/Documents/Work/Private/ViewScope'
  pod 'ViewScopeServer', :git => 'https://github.com/wangwanjie/ViewScope.git', :branch => 'main', :configurations => ['Debug']

  target 'HostsEditorTests' do
    inherit! :complete
  end

  target 'HostsEditorUITests' do
    inherit! :complete
  end

end

target 'HostsEditorHelper' do
  use_frameworks!

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    end
  end
end
