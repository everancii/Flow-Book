## Why

Users can discover books from the 4read source, but opening a selected book fails with an error. This breaks a core user journey (discover -> open -> read/listen) and reduces trust in the catalog integration.

## What Changes

- Add a reliable open-book flow for 4read search results, including robust payload validation before navigation.
- Introduce source-specific error handling so users see actionable messages when a 4read book cannot be opened.
- Define fallback behavior for missing or malformed metadata instead of crashing or hard-failing.
- Add telemetry/log events to distinguish 4read open failures from generic reader errors.

## Capabilities

### New Capabilities
- `four-read-book-open`: Ensure books discovered via 4read can be opened consistently, with validated data and graceful fallback handling.
- `four-read-open-error-feedback`: Provide user-visible, actionable error feedback for 4read open failures and capture diagnostic logging.

### Modified Capabilities
- None.

## Impact

- Affected code: 4read source integration, book detail/open navigation, and error presentation paths in reader-related screens/services.
- APIs/systems: 4read response parsing and mapping logic.
- Dependencies: No new external packages expected; relies on existing logging and UI error surfaces.