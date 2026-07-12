# Listening Reliability Design

Date: 2026-07-12
Branch: codex/improve-android-update-flow
Status: Draft for review

## Goal

Flow Book should get a listener back to their audiobook quickly and recover gracefully when a source fails.

The release should make the app feel dependable in two moments:

- App open: the listener sees the right book, chapter, position, and a clear play action.
- Source failure: the listener understands what happened and has a useful next action.

## Non-Goals

- No new audiobook providers.
- No redesign of the whole app shell.
- No account system or cloud sync.
- No automatic source scraping beyond existing provider capabilities.
- No Play Store release work in this spec.

## Product Shape

This is a focused release called Listening Reliability. It combines a stronger resume experience with a shared recovery system for provider failures.

The user-facing promise:

> Open Flow Book, keep listening. If a source breaks, the app tells you why and helps you recover.

## User Flows

### Continue Listening

When the user opens Home and there is saved playback state, the first section is a Continue Listening card.

The card shows:

- Cover image.
- Audiobook title.
- Current chapter or track title.
- Progress position and total duration when known.
- Source label.
- Primary play/resume button.

Tapping play resumes the saved audiobook at the saved chapter and position.

If the saved item cannot be restored, the card shows a recovery state instead of silently disappearing.

### Recent Listening

Below Continue Listening, Home shows recent listening items from history.

Each item shows:

- Cover.
- Title.
- Last played position or chapter.
- Source label.

Tapping an item opens details or resumes playback, matching the app's existing navigation pattern.

### Source Failure Recovery

When 4read, knigavuhe, YouTube, or Librivox fails during search, details loading, stream selection, or playback, the app shows a recovery panel.

The panel has this priority order:

1. Explain the failure in plain language.
2. Offer Retry when the operation can be retried.
3. Offer downloaded or cached content when available.
4. Offer Search other sources for the same title.
5. Offer source-specific help, such as Login, Open web page, or Update app.

The app should not show raw exceptions, empty screens, or generic "Something went wrong" messages when it can classify the failure.

## Source Error Model

Add one shared source error model used by provider services and screens.

Core fields:

- `source`: librivox, fourRead, knigavuhe, youtube, local, unknown.
- `stage`: search, list, details, stream, playback, login, update, download.
- `type`: network, notFound, blocked, loginRequired, streamUnavailable, parseFailure, unsupported, timeout, storage, unknown.
- `title`: short user-facing title.
- `message`: plain user-facing explanation.
- `canRetry`: whether Retry should be shown.
- `canSearchAlternatives`: whether cross-source search should be shown.
- `sourceUrl`: optional URL for opening provider page or login.
- `debugMessage`: developer-facing detail for logs only.

Provider-specific errors should be converted into this model near the provider boundary, not scattered across UI widgets.

## Recovery Actions

The recovery panel supports actions through a small shared action model:

- Retry: reruns the failed operation.
- Resume cached/downloaded: starts available local content for the same audiobook.
- Search alternatives: opens Search with the current title and all eligible sources.
- Login: opens the provider login screen when authentication is required.
- Open source page: launches the source URL when available.
- Dismiss: returns to the previous stable screen.

Each screen can choose which actions to render, but action creation should be shared so behavior stays consistent.

## App Areas

### Home

Home becomes resume-first:

- Continue Listening at top when state exists.
- Recent Listening below it.
- Existing browse/discovery sections remain available below resume content.

Empty state:

- If there is no listening history, show existing discovery content without a fake resume card.

Failure state:

- If now-playing state exists but restore fails, show a compact recovery card with Retry and Search alternatives.

### Player

Player should preserve and expose recovery:

- If playback engine restore fails, show a source recovery panel.
- If stream URL fails, classify it as streamUnavailable, blocked, loginRequired, timeout, or unknown.
- Keep current sleep timer, bookmarks, equalizer, and chapter controls unchanged.

### Details

Details loading should classify source failures:

- Invalid or missing provider URL: notFound or unsupported.
- Provider page blocked: blocked.
- Login/session issue: loginRequired.
- Parser cannot extract tracks: parseFailure.
- Stream missing: streamUnavailable.

### Search

Search should support alternative lookup:

- A recovery action can open Search prefilled with the audiobook title.
- The user can choose a different source or use the current search defaults.

## Data Flow

```text
Provider service / playback engine
        |
        v
SourceError mapper
        |
        v
Bloc/service state
        |
        v
Recovery panel + actions
```

Resume flow:

```text
Hive now-playing + history
        |
        v
Resume state loader
        |
        v
Home Continue Listening card
        |
        v
Audio handler restore/resume
```

## Component Boundaries

### `SourceError`

Purpose: standard data model for provider and playback failures.

Depends on: no UI packages.

Used by: provider services, blocs, player, details, search, and recovery widgets.

### `SourceRecoveryAction`

Purpose: describes user actions available after a failure.

Depends on: source error model and app navigation callbacks.

Used by: recovery UI builders.

### `SourceRecoveryPanel`

Purpose: reusable UI for error explanation and recovery actions.

Depends on: design system widgets and action callbacks.

Used by: Home, Details, Player, Search.

### `ResumeListeningService`

Purpose: reads now-playing and history data, validates whether an item can be resumed, and returns a display-ready resume state.

Depends on: existing Hive boxes and audiobook models.

Used by: Home and playback restore tests.

## Error Handling

Every source failure should have one of three outcomes:

- Recovered automatically: cached/downloaded content or valid restored state is available.
- Recoverable by user action: retry, login, search alternatives, or open source page.
- Not recoverable: explain that this source cannot provide the audiobook right now.

Unknown errors are allowed, but they should be logged with `debugMessage` and shown with a useful fallback message:

> This source did not return playable audio. Try again or search another source.

## Testing

Add focused tests before implementation is considered complete:

- `SourceError` mapping tests for 4read invalid URL, knigavuhe blocked response, YouTube stream unavailable, network timeout, and parser failure.
- `ResumeListeningService` tests for valid saved state, missing audiobook, missing track, and stale history.
- Home widget test for Continue Listening card and empty history state.
- Recovery panel widget test for Retry, cached content, search alternatives, and login action visibility.
- Playback restore regression test for app restart/update preserving book, chapter, and position.

Existing `playback_trust_test.dart`, `four_read_open_guard_test.dart`, and `settings_update_button_test.dart` are useful models for test style.

## Rollout Plan

1. Build the shared source error and recovery action models.
2. Add source error mapping for the riskiest providers first: 4read and knigavuhe.
3. Add recovery panel UI and wire it into Details.
4. Add ResumeListeningService and Home Continue Listening card.
5. Wire recovery into Player stream failures.
6. Add Search alternatives action.
7. Extend tests and run the full Flutter test suite.

## Success Criteria

- A returning listener can resume the last audiobook from Home with one tap.
- App restart or update preserves current book, chapter, and position.
- 4read and knigavuhe failures no longer collapse into generic UI states.
- Every classified source failure has at least one clear user-facing next action.
- Full Flutter test suite passes.

## Open Decisions

- Search alternatives should start with all sources enabled unless the user later asks for source-specific filtering.
- Cached/downloaded recovery should be offered only when the app can prove local playable content exists.
- The first implementation should prioritize Android behavior because current release and update flow are Android-centered.
