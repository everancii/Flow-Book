## ADDED Requirements

### Requirement: Fetch Top 100 list
The system SHALL fetch and parse the 4read Top 100 page (`https://4read.org/top-100.html`) into an ordered list of up to 100 `Audiobook` objects with rank, title, author, cover image URL, and article URL populated.

#### Scenario: Successful fetch
- **WHEN** the Top 100 screen is opened
- **THEN** the system fetches `https://4read.org/top-100.html` and parses all `linek` card entries into ranked `Audiobook` objects

#### Scenario: Network error
- **WHEN** the HTTP request fails or returns a non-200 status
- **THEN** the screen displays an error message with a retry button

#### Scenario: Empty or unparseable response
- **WHEN** the page returns no parseable `linek` cards
- **THEN** the screen displays an empty state message

### Requirement: Display ranked list
The system SHALL display the Top 100 books as a scrollable list where each item shows: rank number (1–100), cover image, title, and author.

#### Scenario: List renders with rank badges
- **WHEN** the top books list is loaded successfully
- **THEN** each item displays a rank badge (e.g. "#1"), a cover thumbnail, the book title, and the author name

#### Scenario: Cover image missing
- **WHEN** a book entry has no cover image URL
- **THEN** a placeholder cover is shown

### Requirement: Navigate to book details
The system SHALL navigate to `AudiobookDetailsScreen` in 4read mode when a top-books list item is tapped.

#### Scenario: Tap a book
- **WHEN** the user taps a book in the Top 100 list
- **THEN** the app navigates to `AudiobookDetailsScreen` with `isFourRead: true` and the book's article URL as the ID

### Requirement: Parse title and author from card
The system SHALL split the `.linek__title` string (format: `"Title - Author"`) into separate title and author fields. If no ` - ` separator is found, the full string is used as the title and author is left empty.

#### Scenario: Standard title - author format
- **WHEN** the linek__title text is `"Терор - Ден Сіммонс"`
- **THEN** title is `"Терор"` and author is `"Ден Сіммонс"`

#### Scenario: Title contains no separator
- **WHEN** the linek__title text contains no ` - `
- **THEN** the full string is used as the title and author is empty string

#### Scenario: Title contains multiple separators
- **WHEN** the linek__title text is `"Казки - Том 1 - Автор"`
- **THEN** split is performed on the **last** ` - ` occurrence, yielding title `"Казки - Том 1"` and author `"Автор"`
