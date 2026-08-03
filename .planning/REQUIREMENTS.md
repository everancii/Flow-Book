# Requirements: Flow Book

**Defined:** 2026-08-03
**Core Value:** Tap a book from any source and it plays — discover to playback in one gesture.

## v1.1 Requirements (Cold-Restore Progress Bar Fix)

Requirements for milestone v1.1. Single-category, single-requirement fix.

### Restore & Position-Stream Bridge

- [ ] **RESTORE-01**: After quitting the app and returning to the last-played book, pressing play resumes at the saved position **and the progress bar (position thumb, total duration, and remaining-time label) reflects the restored position correctly within the first second of playback** — for all sources whose audio already restores correctly today.

## Future Requirements

Deferred — not in the v1.1 roadmap.

### Restore & Position-Stream Bridge (deferred)

- **RESTORE-02**: Total duration renders correctly for streaming sources where the native duration probe has not yet returned at cold-restore time (separate symptom, not reported in v1.1).
- **RESTORE-03**: Mini-player and media-notification position stay in sync with the player position after cold-restore + play (not reported; deferred).

## Out of Scope

Explicitly excluded from v1.1. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Cross-source restore hardening beyond the reported progress-bar symptom | User explicitly scoped to "just this bug" |
| Mini-player / notification position sync | Not reported; defer to future milestone |
| Changes to the `playImmediately: false` "no seek before deferred load" invariant | Protected by `playback_trust_test.dart`; forked just_audio pins this behavior |
| Details-screen redesign / loading-feedback UI | Out of scope per v1.0 carry-over; not relevant to this bug |
| 4 active OpenSpec changes (`fix-4read-book-open-error`, `four-read-top-books`, `knigavuhe-search-integration`, `youtube-playlist-auto-load`) | Tracked separately under openspec/, not part of this milestone |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| RESTORE-01 | Phase 5 | Pending (roadmap approved) |

**Coverage:**
- v1.1 requirements: 1 total
- Mapped to phases: 1
- Unmapped: 0 ✓

---
*Requirements defined: 2026-08-03*
*Last updated: 2026-08-03 after milestone v1.1 definition*
