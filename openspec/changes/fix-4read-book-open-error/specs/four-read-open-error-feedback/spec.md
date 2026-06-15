## ADDED Requirements

### Requirement: 4read open failures SHALL show actionable user feedback
The system SHALL display a user-facing error message specific to 4read open failures, with guidance that the user can act on.

#### Scenario: Open fails due to validation error
- **WHEN** opening a 4read book fails because required payload fields are invalid or missing
- **THEN** the system MUST show an error message explaining the book cannot be opened right now and suggest retrying or selecting another title

#### Scenario: Open fails due to runtime processing error
- **WHEN** opening a 4read book fails during mapping, parsing, or navigation runtime
- **THEN** the system MUST show a non-crashing error state and return control to the user

### Requirement: 4read open failures SHALL emit diagnostic telemetry
The system SHALL log structured diagnostic events for 4read open failures, including failure category and source context.

#### Scenario: Validation failure is logged
- **WHEN** a 4read open attempt fails validation
- **THEN** the system MUST record a telemetry event with failure type `validation` and source `4read`

#### Scenario: Runtime failure is logged
- **WHEN** a 4read open attempt fails at runtime after validation
- **THEN** the system MUST record a telemetry event with failure type `runtime` and source `4read`