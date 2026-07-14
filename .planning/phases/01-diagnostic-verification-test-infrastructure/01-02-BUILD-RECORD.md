# Phase 01 Plan 02 — Build Record

**Plan:** 01-02 (diagnostic on-device verification)
**Task:** 1 — Build diagnostic release APK + document log-pull procedure
**Built:** 2026-07-14T12:26:06Z
**Git HEAD at build:** `893c9be` (includes 01-01 commit `d1ea567` with the 5 `[DIAG]` checkpoints)
**Build host:** macOS 26.5.1 darwin-arm64, Flutter 3.44.1 (stable), Android SDK 36.1.0, JDK 21 (Android Studio JBR), Gradle 8.11.1, AGP 8.9.1

## Build Command

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
flutter build apk --release --split-per-abi
```

No `--no-verify`, no source/config modifications. Build used the existing `key.properties` release signing config (`android/app/build.gradle` `signingConfigs.release`), `minifyEnabled true` + `shrinkResources true` + ProGuard.

## Result

`assembleRelease` Gradle task: 35.6s. Build succeeded, no errors. Three deprecation warnings only (Gradle 8.11.1, AGP 8.9.1, Kotlin 2.1.10 — all "will soon be dropped", non-blocking for this build).

### Output APKs

| ABI | Path | Size | Timestamp |
|-----|------|------|-----------|
| armeabi-v7a (32-bit ARM) | `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` | 22.2 MB | 2026-07-14 15:25 |
| **arm64-v8a (64-bit ARM — modern devices)** | `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` | 24.3 MB | 2026-07-14 15:25 |
| x86_64 (emulator) | `build/app/outputs/flutter-apk/app-x86_64-release.apk` | 25.9 MB | 2026-07-14 15:25 |

**Install on a real phone:** use `app-arm64-v8a-release.apk` (virtually all modern Android devices are arm64). Use `app-armeabi-v7a-release.apk` only for older 32-bit devices. Use `app-x86_64-release.apk` for an emulator.

### [DIAG] inclusion proof

- `git log --oneline -1` at build time → `893c9be` (descendant of `d1ea567 feat(01-01): add [DIAG] diagnostic checkpoints to initSongs`)
- `rg -c '\[DIAG\]' lib/resources/services/my_audio_handler.dart` → **5** (matches 01-01 deliverable: checkpoints 1, 2-try, 2-catch, 4, 5)
- The 5 `[DIAG]` `AppLogger.debug` calls in `MyAudioHandler.initSongs` write to the file log unconditionally on release builds (`app_logger.dart:95` — `_writeToFile` runs regardless of `kDebugMode`).

## Log-File Location (CORRECTED — see Deviation below)

`AppLogger.initialize()` (`lib/utils/app_logger.dart:11-32`) resolves the path via `getExternalStorageDirectory()`, then writes to:

```
<externalStorageDir>/log/applogs.txt
```

On Android, `getExternalStorageDirectory()` returns the **app-specific external storage** directory:

```
/storage/emulated/0/Android/data/com.everancii.audiobookflow/files/log/applogs.txt
```

Rotation: file is truncated to the last 1000 lines once it exceeds 1 MB (`app_logger.dart:46-69`). Pull logs promptly after each test book to avoid losing `[DIAG]` lines to rotation.

## Log-Pull Commands

> **Deviation from plan:** the plan's suggested command `adb shell run-as com.everancii.audiobookflow cat files/log/applogs.txt` does **not** work on this release build for two reasons:
> 1. `run-as` only works on **debuggable** apps. Release builds are not debuggable (`android:debuggable` defaults to false in release), so `run-as` returns `Package 'com.everancii.audiobookflow' is not debuggable`.
> 2. Even on a debuggable build, `run-as` CWD is the app's **internal** data dir (`/data/data/<pkg>/files`), but `AppLogger` writes to **external** storage (`/storage/emulated/0/Android/data/<pkg>/files`). The relative path `files/log/applogs.txt` would resolve to internal storage, where the log does not exist.
>
> Constraint: "Do NOT modify any source file" — so the app cannot be made debuggable for this build. The commands below are the working alternatives. Pick the one that matches your device.

### Option A — `adb pull` (Android 9 or below, OR rooted device, OR emulator)

```bash
adb pull /storage/emulated/0/Android/data/com.everancii.audiobookflow/files/log/applogs.txt ~/Desktop/soundbooks-diag.txt
```

On Android 10+ non-rooted devices this returns `Permission denied` — use Option B or C.

### Option B — Rooted device (su)

```bash
adb shell su -c "cat /storage/emulated/0/Android/data/com.everancii.audiobookflow/files/log/applogs.txt" > ~/Desktop/soundbooks-diag.txt
```

### Option C — On-device file manager (Android 10+ non-rooted, RECOMMENDED)

Open a file manager that supports `Android/data/` access via SAF (e.g. the built-in **Files** app on Android 11+, Solid Explorer, CX File Manager, Material Files). Navigate to:

```
Android/data/com.everancii.audiobookflow/files/log/applogs.txt
```

Copy/share the file to yourself (e.g. upload to Drive, email, or `adb pull` after copying to a shared location like `/sdcard/Download/`).

On Android 11+ the system **Files** app can browse `Android/data/` for the app's own data; third-party managers need the "All files access" permission.

### Clearing the log before a test run

```bash
# Rooted:
adb shell su -c "truncate -s 0 /storage/emulated/0/Android/data/com.everancii.audiobookflow/files/log/applogs.txt"
# Non-rooted: use the on-device file manager to delete the file (the app recreates it on next log write).
```

## What the Developer Does Next (Task 2 — Human Checkpoint)

See `01-02-PLAN.md` Task 2 `<how-to-verify>` for the full 9-step procedure. Summary:

1. Install `app-arm64-v8a-release.apk` on a real Android device: `adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
2. Clear the log file (Option A/B/C above).
3. Open FlowBook → Sound-Books source → tap a book. Wait ~15s. Do NOT press play manually.
4. Pull the log file (Option A/B/C above). Grep for `[DIAG]`.
5. Record per book: checkpoint 1 (processingState before setAudioSources), checkpoint 2 (OK/THREW + processingState after), checkpoint 4 (processingState + playing after play()), checkpoint 5 (processingState + playing 500ms later), probe duration.
6. Repeat for 3+ Sound-Books books total.
7. Record the hypothesis verdict + timeout recommendation in `01-02-SUMMARY.md` and type `approved` with the data.

## Acceptance Criteria — Task 1

- [x] `ls build/app/outputs/flutter-apk/*.apk` shows APK files built after 01-01 completed (Jul 14 15:25 > Jul 14 12:19).
- [x] `flutter build apk --release --split-per-abi` completed without errors (✓ Built lines, 0 errors, deprecation warnings only).

## Deviations from Plan

**1. [Rule 3 - Blocking issue] Plan's log-pull `run-as` command does not work on release build**
- **Found during:** Task 1 (preparing log-pull instructions)
- **Issue:** `adb shell run-as com.everancii.audiobookflow cat files/log/applogs.txt` (plan-suggested) fails on this release APK: (a) release builds are not debuggable so `run-as` refuses, (b) the relative path resolves to internal storage while the log lives in external storage.
- **Fix:** Documented the correct external-storage path (`/storage/emulated/0/Android/data/com.everancii.audiobookflow/files/log/applogs.txt`) and three working pull methods (adb pull on Android ≤9 / emulator / rooted, su on rooted, on-device file manager on Android 10+ non-rooted). No source change (constraint: "Do NOT modify any source file"). The developer picks the method matching their device.
- **Files modified:** `.planning/phases/01-diagnostic-verification-test-infrastructure/01-02-BUILD-RECORD.md` (this file)
- **Verification:** `app_logger.dart:13` confirms `getExternalStorageDirectory()`; Android docs confirm `run-as` requires `android:debuggable=true`; `android/app/build.gradle:51-58` release buildType does not set debuggable.
