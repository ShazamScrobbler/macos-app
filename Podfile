platform :osx, "11.0"

target "ShazamScrobbler" do
pod 'LastFm'
pod 'FMDB'
end

target "ShazamScrobblerTests" do

end

# Keep pod libraries universal so an Apple silicon build is not linked
# against Intel-only static libraries.
post_install do |installer|
  installer.pods_project.build_configurations.each do |config|
    config.build_settings["ARCHS"] = "arm64 x86_64"
    config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "11.0"
    config.build_settings["ONLY_ACTIVE_ARCH"] = config.name == "Debug" ? "YES" : "NO"
  end
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "11.0"
    end
  end
end

