---
status: testing
phase: 05-cold-restore-position-stream-bridge-fix
source: [05-VERIFICATION.md]
started: 2026-08-03T00:00:00Z
updated: 2026-08-03T00:00:00Z
---

## Current Test

number: 1
name: Cold-restore progress bar position (all sources)
expected: |
  After quitting the app and returning to the last-played book, pressing play
  shows the progress bar at the saved position (not 0:00) within 1 second of
  playback starting — for LibriVox, YouTube, 4read, knigavuhe, Sound-Books,
  and local/download sources.
awaiting: user response

## Tests

### 1. Cold-restore progress bar position (all sources)
expected: After quitting the app and returning to the last-played book, pressing play shows the progress bar at the saved position (not 0:00) within 1 second of playback starting — for every source whose audio already restores correctly today (LibriVox, YouTube, 4read, knigavuhe, Sound-Books, local/download).
result: [pending]

### 2. Duration + remaining-time label render non-zero
expected: The total duration and "Time Remaining" label render correct non-zero values after cold-restore + play.
result: [pending]

### 3. Seek still works after cold-restore + play
expected: Dragging the progress bar to seek still works correctly after a cold-restore + play (no jump-back to 0, no stuck thumb).
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
