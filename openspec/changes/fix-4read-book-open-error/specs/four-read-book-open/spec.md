## ADDED Requirements

### Requirement: 4read open payload SHALL be validated before navigation
The system SHALL validate required 4read book-open fields before attempting to navigate to any details or playback screen.

#### Scenario: Required fields are present
- **WHEN** a user selects a 4read search result and all required open fields are present
- **THEN** the system MUST normalize the payload and continue to the open flow

#### Scenario: Required fields are missing
- **WHEN** a user selects a 4read search result and one or more required open fields are missing
- **THEN** the system MUST stop navigation and classify the failure as a 4read open validation error

### Requirement: 4read metadata SHALL use fallback defaults for non-critical fields
The system SHALL apply fallback values for non-critical metadata fields so valid 4read books can still be opened.

#### Scenario: Optional metadata is missing
- **WHEN** a 4read result lacks optional fields such as subtitle, image, or description
- **THEN** the system MUST use predefined defaults and continue the open flow

### Requirement: 4read open handling SHALL be source-isolated
The system SHALL gate 4read-specific parsing and validation logic by source so non-4read open behavior is unchanged.

#### Scenario: Non-4read source is opened
- **WHEN** a user opens a book from a source other than 4read
- **THEN** the system MUST bypass 4read-specific validation and preserve existing source behavior