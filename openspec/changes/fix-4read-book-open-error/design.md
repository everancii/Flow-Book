## Context

The app can fetch/search books from the 4read source, but opening a selected result currently fails for at least one response shape in production traffic. The failure appears on the user path from discovery to detail/player entry, which is a critical conversion point.

Constraints:
- Preserve existing behavior for non-4read sources.
- Avoid introducing new external dependencies.
- Keep UI behavior consistent with existing error patterns in the app.

Stakeholders:
- End users trying to open 4read content.
- Product/support teams needing clearer failure diagnostics.

## Goals / Non-Goals

**Goals:**
- Ensure 4read results can be opened when minimum required metadata is present.
- Validate and normalize 4read payloads before navigation to detail/player flows.
- Surface actionable, source-specific errors when opening fails.
- Add diagnostic events/logging to isolate 4read open failures.

**Non-Goals:**
- Redesigning the global reader UI.
- Refactoring all source adapters beyond 4read-specific paths.
- Adding retry queues or offline caching in this change.

## Decisions

1. Add a 4read mapping/validation boundary before open navigation.
- Rationale: Centralizing validation prevents screen-level crashes and keeps source-specific parsing logic out of UI layers.
- Alternative considered: Validate in each screen before use. Rejected because it duplicates logic and creates inconsistent failure handling.

2. Use explicit fallback defaults for non-critical fields, but fail fast for critical fields.
- Critical fields: unique identifier and content URL/path needed to open.
- Rationale: Preserves user flow when optional metadata is missing while preventing invalid opens.
- Alternative considered: Hard-fail on any missing field. Rejected because this would block valid books with minor metadata issues.

3. Emit structured error telemetry for open failures.
- Rationale: Distinguishes parsing, validation, and navigation failures, reducing debugging time.
- Alternative considered: Generic logging only. Rejected because source-specific incidents become hard to triage.

4. Present user-facing messages tailored to 4read open failures.
- Rationale: Users need clear next actions rather than opaque crashes or silent failures.
- Alternative considered: Reuse generic error message. Rejected because support cannot correlate user reports to 4read-specific failures.

## Risks / Trade-offs

- [Risk] Validation rules may be too strict and reject valid 4read books. -> Mitigation: Start with minimal required fields, add logging to tune rules.
- [Risk] Fallback defaults may mask data quality issues. -> Mitigation: Log fallback usage with source and field-level tags.
- [Risk] Changes near navigation can introduce regressions for other sources. -> Mitigation: Keep adapter changes source-gated and add targeted tests for 4read/open path.

## Migration Plan

1. Implement adapter-level validation and mapping for 4read open payloads.
2. Integrate source-specific error handling in open flow.
3. Add telemetry hooks for failure and fallback paths.
4. Verify with targeted manual and automated tests on 4read search->open journey.

Rollback strategy:
- Revert the 4read-specific adapter/open changes if severe regressions appear.
- Keep logging improvements if safe and non-disruptive.

## Open Questions

- What exact 4read payload variants are currently observed in failing cases?
- Should user-facing error include a retry action immediately, or remain informational only in this change?
- Do we need to track open-failure rate as a dashboard metric now, or only log events first?