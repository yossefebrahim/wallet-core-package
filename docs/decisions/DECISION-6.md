# DECISION-6 — Minimum Flutter and Dart SDK Versions

Unofficial Dart/Flutter SDK for the open-source Trust Wallet Core library. Not affiliated with or endorsed by Trust Wallet.

| | |
|---|---|
| **Question** | What are the minimum Flutter and Dart SDK versions required by this package? |
| **Status** | **Decided by the owner 2026-10-05** |
| **Evidence** | [`eval/option1` evidence](evidence/DECISION-2-option1.md) |

## 1. Decision and Bounds

The minimum SDK versions are set as follows:
- `flutter: ">=3.47.5"`
- `sdk: ^3.13.0` (using the project's existing caret style, matching Dart 3.13.4 bundled with Flutter 3.47.5).

*Note: The actual `pubspec.yaml` edits are executed by task T1.R1, not by this brief.*

## 2. Evidence and Justification

- **Measured facts**: Flutter 3.47.5 is the only measured version (from the T1.17 host facts) that builds successfully.
- **Xcode compatibility**: Flutter 3.44.1 fails to build the iOS side on Xcode 27.0.
- **`hooks_runner` behavior**: The behavior of `hooks_runner` changed materially between version 1.1.1 and 1.5.0. 
- **`MinimumOSVersion`**: The native-asset framework's `MinimumOSVersion` requirement shifted from iOS 13 to iOS 15, per the Option 1 evidence document. 

## 3. Re-measure Triggers

The minimum boundaries will be re-measured when:
- Each new Flutter stable version is released. 

*Note: A 3.44.x Android-only measurement would theoretically allow a lower floor for Android, but this is not planned or supported.*

## 4. What Changes if Overturned

If these bounds are overturned to allow older versions, we must configure and maintain parallel CI jobs measuring Xcode 26 against older Flutter stables and support older versions of the hooks protocol.
