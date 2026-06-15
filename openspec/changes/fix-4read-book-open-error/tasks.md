## 1. Reproduce and Map Failure

- [ ] 1.1 Reproduce the 4read search -> open failure and capture the failing payload shape(s).
- [x] 1.2 Identify current 4read mapping/open entry points in services and screens that participate in navigation.
- [x] 1.3 Define and document required vs optional 4read fields for open flow.

## 2. Implement 4read Validation and Normalization

- [x] 2.1 Add a 4read-specific validation boundary before details/player navigation.
- [x] 2.2 Implement normalization with fallback defaults for optional metadata fields.
- [x] 2.3 Stop open flow on missing critical fields and emit a typed validation failure.
- [x] 2.4 Ensure non-4read sources bypass this logic and preserve existing behavior.

## 3. Error Feedback and Telemetry

- [x] 3.1 Add user-facing 4read-specific error messaging for validation and runtime open failures.
- [x] 3.2 Ensure runtime failures return control safely without crash loops.
- [x] 3.3 Emit structured telemetry events for 4read open failures with failure type and source tags.
- [x] 3.4 Add logging for fallback-field usage to support payload quality tuning.

## 4. Verification

- [x] 4.1 Add or update tests for successful 4read open, missing-required-field failure, and optional-field fallback behavior.
- [x] 4.2 Add or update tests for user-facing error states and telemetry event emission.
- [ ] 4.3 Run targeted manual QA for 4read discover -> open across at least one valid and one invalid payload case.