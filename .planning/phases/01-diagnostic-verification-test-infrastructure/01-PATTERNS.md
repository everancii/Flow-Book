# Phase 1: Diagnostic Verification + Test Infrastructure - Pattern Map

**Mapped:** 2026-07-14
**Files analyzed:** 2 (both modifications — no new files)
**Analogs found:** 2 / 2

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|------------------|------|-----------|----------------|---------------|
| `test/playback_trust_test.dart` | test | request-response (assert on fake state) | same file — existing `MyAudioHandler with fake playback engine` group (lines 210-292) | exact (in-file) |
| `lib/resources/services/my_audio_handler.dart` | service | event-driven (initSongs orchestration + stream listen) | same file — existing `AppLogger.debug` calls in `initSongs` (lines 563-613) | exact (in-file) |

**Note:** Phase 1 modifies two existing files. No new production files. No new test files — new test cases are added to the existing `playback_trust_test.dart` group. Both analogs live in the very files being modified, so pattern extraction is direct.

## Pattern Assignments

### `test/playback_trust_test.dart` (test, request-response)

**Analog:** same file — `'MyAudioHandler with fake playback engine'` group, lines 210-292

**Imports pattern** (lines 1-15) — already present, no new imports needed:
```dart
import 'dart:async';
import 'dart:io';

import 'package:audiobookflow/resources/models/audiobook.dart';
import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:audiobookflow/resources/models/history_of_audiobook.dart';
import 'package:audiobookflow/resources/services/bookmark_service.dart';
import 'package:audiobookflow/resources/services/my_audio_handler.dart';
import 'package:audiobookflow/screens/audiobook_player/widgets/track_section_dialog.dart'
    show effectiveTrackLength, formatTrackDuration;
import 'package:audiobookflow/utils/optimized_timer.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
```
`ProcessingState` comes from `package:just_audio/just_audio.dart` (line 15) — already imported. No rxdart import needed unless Phase 3 upgrades fake to BehaviorSubject (out of Phase 1 scope).

**Hive setup pattern** (lines 20-45) — shared by all tests, do not duplicate:
```dart
setUpAll(() async {
  hiveDir = await Directory.systemTemp.createTemp('flow_book_playback_test_');
  Hive.init(hiveDir.path);
  for (final boxName in [
    'playing_audiobook_details_box',
    'history_of_audiobook_box',
    'bookmarks_box',
    'listening_stats_box',
  ]) {
    await Hive.openBox(boxName);
  }
});

setUp(() async {
  await Hive.box('playing_audiobook_details_box').clear();
  await Hive.box('history_of_audiobook_box').clear();
  await Hive.box('bookmarks_box').clear();
  await Hive.box('listening_stats_box').clear();
});
```
New tests inherit this — boxes are cleared per-test. No new boxes needed.

**Handler+fake construction pattern** (lines 212-216, repeated 246-250, 269-273) — copy verbatim:
```dart
final fake = FakePlaybackEngine();
final handler = MyAudioHandler(
  player: fake,
  configureAudioSession: false,
);
```
`configureAudioSession: false` is mandatory — avoids real audio-session activation in tests.

**initSongs call pattern** (lines 252-258) — the shape new tests follow:
```dart
await handler.initSongs(
  _sampleFiles(),
  _sampleAudiobook(),
  0,
  0,
  playImmediately: false,
);
```
New "fails today" test calls with `playImmediately: true` and does NOT await immediately (captures `initFuture`).

**Assertion pattern** (lines 229-235, 262-264) — `expect` on fake counters + recorded calls:
```dart
expect(fake.setAudioSourcesCalls, hasLength(1));
expect(fake.setAudioSourcesCalls.single.initialIndex, 1);
expect(fake.playCount, 0);
```
New test asserts `fake.playCount == 0` before `ready` emitted (fails today), `== 1` after.

**Sample-data helpers** (lines 295-348) — `_sampleAudiobook()` + `_sampleFiles()` + `_bookmark(...)` already defined at file bottom. New tests reuse these — do not redefine.

**FakePlaybackEngine fields new tests configure** (lines 350-499):
- `processingState` — public mutable field, default `ProcessingState.ready` (line 384). New test sets `fake.processingState = ProcessingState.loading` before `initSongs`.
- `processingStates` — broadcast `StreamController<ProcessingState>` (line 357). New test calls `fake.processingStates.add(ProcessingState.ready)` to emit transition.
- `processingStateStream` getter (line 411) returns `processingStates.stream` — the surface the fix listens on.
- `playCount` — int counter incremented in `play()` (line 422). Assertion target.
- `playing` — public mutable bool (line 366), set true by `play()` (line 423).

**Critical stream caveat** (from RESEARCH.md Pitfall 1): broadcast StreamController does NOT replay last state. `firstWhere(ready)` hangs if subscribed when already `ready` and no new emission. New tests must use field-check-first pattern (set `processingState = loading`, emit `ready` on stream after a 10ms pump) — NOT `firstWhere`. If Phase 3 picks `firstWhere`, upgrade fake to BehaviorSubject then (out of Phase 1 scope).

**New test insertion point:** inside existing `group('MyAudioHandler with fake playback engine', ...)` block (line 210), after the last existing test (line 291, before closing `}` at 292). Keep group cohesion.

---

### `lib/resources/services/my_audio_handler.dart` (service, event-driven)

**Analog:** same file — existing `AppLogger.debug` calls in `initSongs`, lines 563-613

**Imports pattern** (line 12) — already present:
```dart
import 'package:audiobookflow/utils/app_logger.dart';
```
No new imports. `AppLogger.debug(message, [tag])` signature (app_logger.dart:90).

**Existing logging pattern to mirror** (lines 563-613) — the `[DIAG]` logs copy this shape:
```dart
if (playImmediately) {
  AppLogger.debug(
      'initSongs: calling _player.play(), state=${_player.processingState}');
  _player.play();

  // Listen for processing state changes to re-trigger play if we enter buffering
  DateTime? bufferingStarted;
  final sub = _player.processingStateStream.listen((state) {
    AppLogger.debug('initSongs: processingState=$state');

    if (state == ProcessingState.ready) {
      AppLogger.debug('initSongs: player ready, ensuring play');
      bufferingStarted = null;
      _player.play();
    } else if (state == ProcessingState.buffering) {
      bufferingStarted ??= DateTime.now();
    } else if (state == ProcessingState.idle && _player.playing) {
      AppLogger.debug('initSongs: player went idle, attempting recovery');
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_player.processingState == ProcessingState.idle) {
          _player.play();
        }
      });
    }
    // ... 30s buffering-skip block ...
  });

  Future.delayed(const Duration(seconds: 60), () => sub.cancel());
}
```
Key conventions to copy:
- `AppLogger.debug('initSongs: <desc>, state=${_player.processingState}')` — state interpolation pattern
- `Future.delayed(Duration, () { ... })` for delayed side-effects (line 582, 597, 608) — matches checkpoint 5's 500ms delayed log
- Gen-staleness guard `if (myGen != _initGen) return;` already used at lines 526, 549, 622 — checkpoint 5 delayed log must replicate this guard

**Generation-tracking pattern** (lines 423-424) — `myGen` is the local to interpolate in `[DIAG]` logs:
```dart
_isReinitializing = true;
final myGen = ++_initGen;
```
`[DIAG]` log format: `'[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: ...'`. The `active=...` flag marks stale-init logs (Pitfall 3).

**setAudioSources call site — checkpoint 2 insertion point** (lines 540-547):
```dart
await _player.setAudioSources(
  _audioSources!,
  initialIndex: sources.isEmpty ? 0 : safeIndex,
  initialPosition: currentIsYT
      ? Duration.zero
      : Duration(milliseconds: positionInMilliseconds),
  preload: playImmediately,
);
```
Currently NO try/catch wraps this (RESEARCH.md Pitfall 2). Phase 1 wraps it in try/catch that logs then **rethrows** (preserves existing propagation to `_autoPlay` catch at audiobook_details.dart:133). Do NOT swallow.

**play() call site — checkpoint 3/4 insertion point** (lines 563-565):
```dart
AppLogger.debug(
    'initSongs: calling _player.play(), state=${_player.processingState}');
_player.play();
```
Existing log at 563 IS checkpoint 3 (no new log needed there). Checkpoint 4 = new `AppLogger.debug('[DIAG] ... after play(), state=..., playing=${_player.playing}')` immediately after `_player.play()`. Checkpoint 5 = `Future.delayed(500ms, () { if (myGen != _initGen) return; AppLogger.debug('[DIAG] ... 500ms after play() ...'); })`.

**Diagnostic log format (RESEARCH.md Pattern 2)** — exact strings to insert:
```dart
// CHECKPOINT 1 — before setAudioSources (insert above line 540)
AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: '
    'before setAudioSources, processingState=${_player.processingState}, '
    'playing=${_player.playing}');

// CHECKPOINT 2 — wrap existing setAudioSources (lines 540-547)
try {
  await _player.setAudioSources(
    _audioSources!,
    initialIndex: sources.isEmpty ? 0 : safeIndex,
    initialPosition: currentIsYT
        ? Duration.zero
        : Duration(milliseconds: positionInMilliseconds),
    preload: playImmediately,
  );
  AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: '
      'setAudioSources OK, processingState=${_player.processingState}');
} catch (e) {
  AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: '
      'setAudioSources THREW: $e, processingState=${_player.processingState}');
  rethrow; // preserve existing propagation — DO NOT swallow
}

// CHECKPOINT 4 — after _player.play() (insert below line 565)
AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: '
    'after play(), processingState=${_player.processingState}, '
    'playing=${_player.playing}');

// CHECKPOINT 5 — delayed, inside the `if (playImmediately)` block
Future.delayed(const Duration(milliseconds: 500), () {
  if (myGen != _initGen) return; // stale init — don't log
  AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: '
      '500ms after play(), processingState=${_player.processingState}, '
      'playing=${_player.playing}'
      '${_player.playing ? '' : ' <- audioSession.setActive may have failed'}');
});
```

**AppLogger.debug contract** (app_logger.dart:90-96):
```dart
static void debug(String message, [String? tag]) {
  final logMessage = '[${tag ?? _tag}] DEBUG: $message';
  if (kDebugMode) {
    print(logMessage);
  }
  _writeToFile(logMessage);  // ALWAYS runs — file log on release builds
}
```
File logging is unconditional (line 95) — diagnostic logs WILL appear on release-device log file. `kDebugMode` only gates `print` (line 92-94). Do NOT add `kDebugMode` guard around `[DIAG]` logs (RESEARCH.md Anti-Pattern) — that defeats on-device purpose.

---

## Shared Patterns

### AppLogger.debug usage
**Source:** `lib/utils/app_logger.dart:90-96`, used at `my_audio_handler.dart:563,570,573,581,593,612,714,878`
**Apply to:** All `[DIAG]` checkpoints in `initSongs`
```dart
AppLogger.debug('[DIAG] initSongs[gen=$myGen,active=${myGen == _initGen}]: <desc>, '
    'processingState=${_player.processingState}, playing=${_player.playing}');
```
- No tag arg — uses default `'Flow Book'` tag (consistent with existing initSongs logs)
- File write always on — release-build device logs work
- Multi-line string concat with adjacent string literals (matches line 563-564 style)

### Generation staleness guard
**Source:** `my_audio_handler.dart:526,549,622`
**Apply to:** Checkpoint 5 delayed log callback
```dart
if (myGen != _initGen) return;
```
Prevents stale-init logs from a superseded `initSongs` call firing after 500ms delay. Matches existing guard pattern at three sites in `initSongs`.

### rethrow-not-swallow for diagnostic try/catch
**Source:** RESEARCH.md Pitfall 2 (no existing analog — current code has no try/catch around setAudioSources)
**Apply to:** Checkpoint 2 wrapper around `setAudioSources`
```dart
try {
  await _player.setAudioSources(...);
  AppLogger.debug('[DIAG] ... OK ...');
} catch (e) {
  AppLogger.debug('[DIAG] ... THREW: $e ...');
  rethrow;
}
```
`rethrow` preserves propagation to `_autoPlay` catch (`audiobook_details.dart:133`) and `_playChapter` catch (`:84`). Swallowing would break Sound-Books error UX.

### Test construction + assertion shape
**Source:** `playback_trust_test.dart:212-216,252-264`
**Apply to:** All new test cases in the `MyAudioHandler with fake playback engine` group
```dart
final fake = FakePlaybackEngine();
final handler = MyAudioHandler(
  player: fake,
  configureAudioSession: false,
);
// ... configure fake, call initSongs, assert on fake.playCount / fake.setAudioSourcesCalls ...
```
`configureAudioSession: false` mandatory. Reuse `_sampleFiles()` + `_sampleAudiobook()` helpers (file bottom, lines 295-336) — do not redefine.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| — | — | — | All Phase 1 modifications have exact in-file analogs. No external pattern source needed. |

## Metadata

**Analog search scope:**
- `test/playback_trust_test.dart` (full read, 520 lines — single pass)
- `lib/resources/services/my_audio_handler.dart` (lines 1-80 imports+abstract, 410-669 initSongs+helpers)
- `lib/utils/app_logger.dart` (lines 1-110 — debug signature)
- Grep for `AppLogger.debug` across `lib/` (52 matches — confirmed initSongs is the densest usage site)

**Files scanned:** 3 source files + 1 grep pass
**Pattern extraction date:** 2026-07-14
