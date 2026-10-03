#
# wallet_core_flutter_native — iOS packaging, DECISION-2 Option 2
# (evaluation branch, T1.9).
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# What this pod does: it vendors Frameworks/TrustWalletCore.xcframework, a
# dynamic framework the app links and embeds, so the library is loaded with the
# app and `DynamicLibrary.process()` resolves it (the loader's first iOS
# default). The xcframework is never committed. It is produced *while CocoaPods
# evaluates this file* during `pod install`, by tool/option2/prepare_xcframework.dart,
# from manifest artifacts obtained through the package's own fetch tool
# (tool/fetch_artifacts.dart: sha256 and size verified, no flag accepts a
# mismatch):
#
#   - a manifest with an `ios/TrustWalletCore.xcframework.zip` row: the zip is
#     verified, expanded, and vendored as shipped;
#   - a manifest with `ios/<abi>/` and `ios-simulator/<abi>/libTrustWalletCore.dylib`
#     rows: each verified dylib is wrapped in a framework bundle and the
#     xcframework is assembled around them.
#
# Why at evaluation time and not in `prepare_command`: Flutter adds every
# plugin pod with `:path => '.symlinks/plugins/<name>/ios'`, and CocoaPods does
# not run `prepare_command` for a path pod. Evaluation is the one hook that
# runs before CocoaPods reads the xcframework's Info.plist to generate its
# copy phase. A failed verification raises, and `pod install` fails with the
# fetch tool's report.
#
# The build-time script phase below re-checks the result on every Xcode build:
# a manifest edited after `pod install`, or a framework binary changed since —
# including by another app's `pod install` against a different manifest, since
# the pod directory is shared — fails the build. It cannot see a replacement
# that lands after it has run and before the app links and embeds the
# framework.
#
# Build-time inputs, environment variables only. None of them is read at run
# time (threat model TM-13):
#
#   WCF_MANIFEST       absolute path of the manifest to verify against.
#                      Default: this package's assets/compat_manifest.json.
#   WCF_VENDORED_DIR   a directory laid out by logical name (--vendored).
#   WCF_OFFLINE=1      never open a socket (--offline).
#   WCF_ARTIFACT_DIR   the shared cache, read by the fetch tool itself.

require 'open3'

# Flutter's podhelper makes `<app>/ios/.symlinks/plugins/<name>` a symlink to
# the package root (the pub-cache copy for a hosted package) and declares the
# pod `:path => '.symlinks/plugins/<name>/ios'`. CocoaPods neither copies nor
# re-links a :path pod: it evaluates this file and builds from that directory
# in place. So __dir__ is `.symlinks/plugins/<name>/ios`, and the lexical `..`
# below is `.symlinks/plugins/<name>`, the symlink to the package root: tool/
# and assets/ resolve from there. Had CocoaPods resolved the symlink first,
# __dir__ would be `<package root>/ios` and `..` the same root: the link
# points at the package root, not at ios/, so both readings agree. (The
# script phase's `${PODS_TARGET_SRCROOT}/..` is resolved by the kernel,
# through the same link, to the same root, because ios/ is a real directory
# in it.)
wcf_pod_dir = File.expand_path(__dir__)
wcf_package_dir = File.expand_path('..', wcf_pod_dir)

# The pod's deployment target, fixed rather than derived. It is not the
# library's own minimum: the device dylib is measured at iOS 13.0 (vtool:
# LC_BUILD_VERSION minos 13.0; manifest min_os "13.0", kept in the framework's
# Info.plist), but Xcode 27's iphoneos SDK accepts 15.0–27.0 only, and
# Flutter 3.47's own Flutter.framework declares MinimumOSVersion 15.0, so no
# app this pod can be part of targets less. Deriving it at `pod install` (from
# the host SDK's SDKSettings.plist, or from the manifest) would make the spec,
# and Podfile.lock's checksum of it, differ by machine, and on an older Xcode
# could declare less than Flutter itself supports. prepare_xcframework.dart
# refuses a manifest whose device slice needs a newer iOS than this.
wcf_deployment_target = '15.0'

wcf_manifest =
  if ENV['WCF_MANIFEST'].to_s.empty?
    File.join(wcf_package_dir, 'assets', 'compat_manifest.json')
  else
    File.expand_path(ENV['WCF_MANIFEST'])
  end

wcf_prepare = lambda do
  # `pod lib lint`, `ruby -c` and anything else that is not CocoaPods
  # installing into a Flutter app have no app to resolve the Dart tool through;
  # they get the spec without the side effect. A real app always has run
  # `flutter pub get` first, and the script phase fails a build whose
  # xcframework was never prepared.
  next unless defined?(Pod::Config)

  install_root = Pod::Config.instance.installation_root.to_s
  app_dir = File.expand_path('..', install_root)
  package_config = File.join(app_dir, '.dart_tool', 'package_config.json')
  unless File.exist?(package_config)
    Pod::UI.warn("wallet_core_flutter_native: no #{package_config}; " \
                 'TrustWalletCore.xcframework was not prepared')
    next
  end

  # One evaluation per manifest per CocoaPods process: CocoaPods may load a
  # path podspec more than once during a single install.
  memo_key = [wcf_pod_dir, wcf_manifest, File.mtime(wcf_manifest).to_f,
              ENV['WCF_VENDORED_DIR'], ENV['WCF_OFFLINE']].join('|')
  $wcf_native_prepared ||= {}
  next if $wcf_native_prepared[memo_key]

  flutter_root = ENV['FLUTTER_ROOT'].to_s
  generated = File.join(install_root, 'Flutter', 'Generated.xcconfig')
  if flutter_root.empty? && File.exist?(generated)
    File.foreach(generated) do |line|
      match = line.match(/^FLUTTER_ROOT=(.*)$/)
      flutter_root = match[1].strip if match
    end
  end
  dart = flutter_root.empty? ? 'dart' : File.join(flutter_root, 'bin', 'dart')

  # Frameworks/ and .wcf_work/ are in the pod directory, which every app using
  # this copy of the package shares (for a hosted package, the pub-cache copy).
  # prepare_xcframework.dart holds an exclusive lock on .wcf_work/.lock for
  # the whole verify, assemble and stamp step, and fetches into a fresh
  # .wcf_work/run-* directory of its own, so a concurrent `pod install`
  # against another manifest waits instead of swapping files under it.
  args = [
    dart, "--packages=#{package_config}",
    File.join(wcf_package_dir, 'tool', 'option2', 'prepare_xcframework.dart'),
    '--manifest', wcf_manifest,
    '--out', File.join(wcf_pod_dir, 'Frameworks'),
    '--work', File.join(wcf_pod_dir, '.wcf_work'),
    '--privacy-manifest', File.join(wcf_pod_dir, 'Resources', 'PrivacyInfo.xcprivacy'),
    '--deployment-target', wcf_deployment_target
  ]
  unless ENV['WCF_VENDORED_DIR'].to_s.empty?
    args += ['--vendored', File.expand_path(ENV['WCF_VENDORED_DIR'])]
  end
  args << '--offline' if ENV['WCF_OFFLINE'] == '1'

  output, status = Open3.capture2e(*args)
  unless status.success?
    raise Pod::Informative,
          "wallet_core_flutter_native: native artifact verification FAILED " \
          "(exit #{status.exitstatus}); TrustWalletCore.xcframework was not " \
          "produced.\n#{args.join(' ')}\n#{output}"
  end
  Pod::UI.puts(output)
  $wcf_native_prepared[memo_key] = true
end

wcf_prepare.call

Pod::Spec.new do |s|
  s.name             = 'wallet_core_flutter_native'
  s.version          = '0.0.1'
  s.summary          = 'Native distribution layer of wallet_core_flutter: ' \
                       'checksum-verified TrustWalletCore.xcframework.'
  s.description      = <<-DESC
Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not
affiliated with or endorsed by Trust Wallet. Vendors TrustWalletCore.xcframework,
verified at pod install against the compatibility manifest the package ships.
                       DESC
  s.homepage         = 'https://pub.dev/packages/wallet_core_flutter_native'
  s.license          = { :type => 'MIT', :text => 'MIT. See LICENSE and ' \
                         'THIRD_PARTY_NOTICES.md at the repository root.' }
  s.author           = 'wallet_core_flutter contributors'
  s.source           = { :path => '.' }

  s.platform = :ios, wcf_deployment_target
  s.dependency 'Flutter'

  s.source_files = 'Classes/**/*'
  s.vendored_frameworks = 'Frameworks/TrustWalletCore.xcframework'
  s.preserve_paths = ['Frameworks/**/*']

  # PRD §12.2 step 10: the slices import file-timestamp and system-boot-time
  # APIs. The same manifest is also at the root of each framework bundle;
  # this resource bundle is the pod-level copy Xcode's privacy report reads
  # for the plugin.
  s.resource_bundles = {
    'wallet_core_flutter_native_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }

  # No linker flags of its own, and nothing set on the app's target: the app's
  # link sees only CocoaPods' own `-framework "TrustWalletCore"`
  # (test/packaging/static_consistency_test.dart keeps it that way).
  # User-script sandboxing is off for this pod's target only, because the
  # script phase reads the manifest, which lives outside the build products.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO'
  }

  s.script_phase = {
    :name => 'Verify TrustWalletCore.xcframework against the manifest',
    :execution_position => :before_compile,
    :always_out_of_date => '1',
    :shell_path => '/bin/sh',
    :script => <<~'SH'
      set -eu
      fw="${PODS_TARGET_SRCROOT}/Frameworks"
      manifest="${WCF_MANIFEST:-${PODS_TARGET_SRCROOT}/../assets/compat_manifest.json}"
      fail() { echo "error: wallet_core_flutter_native: $*" >&2; exit 1; }
      [ -f "$fw/wcf_manifest.sha256" ] || fail "TrustWalletCore.xcframework was never prepared; run pod install"
      [ -f "$manifest" ] || fail "no manifest at $manifest"
      want=$(cat "$fw/wcf_manifest.sha256")
      have=$(/usr/bin/shasum -a 256 "$manifest" | /usr/bin/cut -d ' ' -f 1)
      [ "$want" = "$have" ] || fail "$manifest (sha256 $have) is not the manifest TrustWalletCore.xcframework was verified against at pod install (sha256 $want); run pod install"
      cd "$fw"
      /usr/bin/shasum -a 256 --status -c wcf_binaries.sha256 || fail "a TrustWalletCore.framework binary changed after pod install verified it; run pod install"
    SH
  }
end
