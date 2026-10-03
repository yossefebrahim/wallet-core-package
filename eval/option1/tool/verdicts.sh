# Sourced by eval/option1/run_eval.sh: the shell side of the verdicts that
# decide whether a row may say `pass`. Kept apart so that
# packages/wallet_core_flutter_native/test/eval_option1/verdicts_test.dart can
# drive them with stubbed `row` and `harness` functions.
#
# Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library.
# Not affiliated with or endorsed by Trust Wallet.
#
# Needs, from the caller: row (writes one result row), harness (runs one
# tools/packaging_eval measurement), and the note texts ORCH and NOART.

# pristine_check DIR WHEN: exits 1 unless the consumer at DIR is as
# `flutter create` wrote it plus the README's edits. What it looks for is
# what a flutter command run inside DIR leaves behind (T1.8a delta 5):
# `flutter pub get`'s plugin injection copies Flutter's Podfile template into
# ios/ (keeping the template's mtime) and adds `#include? "Pods/…"` to the
# xcconfigs whenever the app has an iOS plugin and Swift Package Manager is
# off; `pod install` and Xcode add Podfile.lock, Pods/, .symlinks, the
# project's Pods references and SwiftPM state; `flutter pub get` also writes
# macos/Flutter/GeneratedPluginRegistrant.swift, which the template does not
# ignore. run_eval.sh calls it before and after the run.
pristine_check() {
  for f in ios/Podfile ios/Podfile.lock ios/Pods ios/.symlinks \
    macos/Podfile macos/Podfile.lock macos/Pods \
    macos/Flutter/GeneratedPluginRegistrant.swift \
    ios/Runner.xcworkspace/xcshareddata/swiftpm \
    ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm \
    macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm; do
    if [ -e "$1/$f" ]; then
      echo "run_eval: $1/$f exists: the consumer is not as flutter create wrote it ($2). Something ran a flutter command inside it; restore the platform folders from tool/create_consumer.sh's output." >&2
      exit 1
    fi
  done
  for f in ios/Runner.xcodeproj/project.pbxproj macos/Runner.xcodeproj/project.pbxproj \
    ios/Flutter/Debug.xcconfig ios/Flutter/Release.xcconfig \
    macos/Flutter/Flutter-Debug.xcconfig macos/Flutter/Flutter-Release.xcconfig; do
    if [ ! -f "$1/$f" ]; then
      echo "run_eval: $1/$f is missing ($2)" >&2
      exit 1
    fi
    if grep -q 'Pods' "$1/$f"; then
      echo "run_eval: $1/$f references CocoaPods: the consumer is not as flutter create wrote it ($2)" >&2
      exit 1
    fi
  done
}

# not_built CHECK TARGET RC COMMAND: the row for a measurement of a build that
# did not succeed in this run. Nothing is read from disk: a file at the
# measured path could only be an earlier run's (review finding 4, T1.8a-d4).
not_built() {
  case $3 in
    10) summary='refused here'; notes="$ORCH" ;;
    20) summary='no artifact'; notes="$NOART" ;;
    *) summary='not built in this run'
       notes="the build this measures did not succeed here (exit $3); nothing left over from an earlier run is measured" ;;
  esac
  row --check "$1" --target "$2" --status unmeasured --summary "$summary" --command "$4" --notes "$notes"
}

# packaged RC LIB TARGET FORMAT: symbols and size of the binary inside a built
# app, in that app's column — measured only when RC says the build succeeded
# in this run.
packaged() {
  if [ "$1" -eq 0 ]; then
    harness symbols --artifact "$2" --format "$4" --target "$3"
    harness size --artifact "$2" --target "$3"
  else
    not_built symbols "$3" "$1" "dart run tools/packaging_eval/bin/symbols.dart --artifact $2 --format $4 --target $3"
    not_built size "$3" "$1" "dart run tools/packaging_eval/bin/size.dart --artifact $2 --target $3"
  fi
}

# offline_verdict RC PRE POST: sets OFF_STATUS, OFF_SUMMARY and OFF_NOTES for
# a target's offline row from its build's exit code and the hook's evidence
# (`eval_tool.dart offline-evidence`, KIND<TAB>EVIDENCE) right before and right
# after the build. `pass` only when the build started with no cached copy of
# the artifact and the hook then copied it from vendored_dir with offline set
# — the clean offline install PRD §12.2 step 7 asks for. A warm cache never
# passes (review finding 11, T1.8a-d4).
offline_verdict() {
  pre_kind=$(printf %s "$2" | cut -f1)
  post_kind=$(printf %s "$3" | cut -f1)
  post_evidence=$(printf %s "$3" | cut -f2-)
  OFF_NOTES="hook log before: ${2:-none}; after: ${3:-none}. Clean state: a fresh staged copy (no .dart_tool, so the hook's default cache_dir is empty) with offline: true and vendored_dir set. That no socket was opened follows from offline (the fetch tool makes no request); it is not observed at the socket level"
  if [ "$1" -eq 10 ]; then
    OFF_STATUS=unmeasured; OFF_SUMMARY='offline: refused here'; OFF_NOTES="$ORCH"
  elif [ "$1" -ne 0 ]; then
    OFF_STATUS=unmeasured; OFF_SUMMARY='offline: not built'; OFF_NOTES='the offline build did not succeed in this run (see its consumer-build row)'
  elif [ "$pre_kind" != none ]; then
    OFF_STATUS=unmeasured; OFF_SUMMARY="offline: cache not empty before the build ($pre_kind)"
  else
    case $post_kind in
      vendored) OFF_STATUS=pass; OFF_SUMMARY='offline: built from vendored_dir, empty cache'
        OFF_NOTES="$post_evidence. $OFF_NOTES" ;;
      downloaded) OFF_STATUS=fail; OFF_SUMMARY='offline: the hook downloaded' ;;
      *) OFF_STATUS=unmeasured; OFF_SUMMARY="offline: no vendored copy in the hook log ($post_kind)" ;;
    esac
  fi
}
