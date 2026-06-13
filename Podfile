platform :osx, '13.0'

project 'HostsEditor.xcodeproj'

install! 'cocoapods', :warn_for_unused_master_specs_repo => false

inhibit_all_warnings!

def install_lookin_server_pods
  lookin_pods = %w[
    LookinServerBase
    LookinCore
    LookinShared
    LookinServer
  ]
  debug_only_options = { :configurations => ['Debug'] }

  use_local_lookin = %w[1 true yes].include?(ENV['kUse_Local_Lookin'].to_s.downcase)
  lookin_source = if use_local_lookin
    { :path => '../LookInside' }
  else
    { :git => 'https://gitea.ddns.vanjay.cn:4433/iOS/LookInside.git', :branch => 'feature/vanjay/kg_main' }
  end

  lookin_pods.each do |pod_name|
    pod pod_name, lookin_source.merge(debug_only_options)
  end
end

target 'HostsEditor' do
  use_frameworks! :linkage => :static

  # pod 'ViewScopeServer', :path => '/Users/VanJay/Documents/Work/Private/ViewScope'
  pod 'ViewScopeServer', :git => 'https://github.com/wangwanjie/ViewScope.git', :branch => 'main', :configurations => ['Debug']

  install_lookin_server_pods

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
