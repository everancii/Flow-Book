## ADDED Requirements

### Requirement: Search knigavuhe.org catalog
The system SHALL search the knigavuhe.org audiobook catalog by query string and return results as `Audiobook` objects with pagination support.

#### Scenario: Successful search
- **WHEN** the user submits a search query with knigavuhe source selected
- **THEN** the system fetches `https://knigavuhe.org/search/?q=<encoded_query>&page=<page>` and parses book cards into `Audiobook` objects

#### Scenario: Search with pagination
- **WHEN** the user loads more search results or navigates to page 2+
- **THEN** the system fetches the corresponding page URL with the incremented page parameter

#### Scenario: Network error
- **WHEN** the HTTP request fails or returns a non-200 status
- **THEN** the system returns an empty result set and logs an error (does not crash)

### Requirement: Parse book cards from HTML
The system SHALL parse knigavuhe search results HTML to extract book metadata: title, author, cover image URL, description, duration, download count, rating, narrators, genre, and book ID.

#### Scenario: Standard book card parsing
- **WHEN** a book card contains all expected fields
- **THEN** the system extracts: title from book-item-title, author from book-item-author, cover from img src, description from book-item-description, duration from "X часов Y минут" pattern, downloads from numeric field, rating if available, narrators from comma-separated list, genre from genre tag, and book ID from href attribute

#### Scenario: Relative cover URL
- **WHEN** the cover image URL is relative (does not start with http)
- **THEN** the system prepends `https://knigavuhe.org` to create an absolute URL

#### Scenario: Missing optional fields
- **WHEN** a book card is missing optional fields (description, rating, narrators)
- **THEN** the system uses sensible defaults: empty description, null rating, empty narrators list

### Requirement: Parse Russian duration format
The system SHALL parse duration strings in Russian format ("X часов Y минут") into total minutes.

#### Scenario: Standard duration format
- **WHEN** the duration text is "2 часа 30 минут"
- **THEN** the system returns 150 minutes (2 * 60 + 30)

#### Scenario: Singular hour format
- **WHEN** the duration text is "1 час 15 минут"
- **THEN** the system returns 75 minutes (1 * 60 + 15)

#### Scenario: Malformed duration
- **WHEN** the duration text does not match the expected pattern
- **THEN** the system returns 0 minutes (fallback)

### Requirement: Map to Audiobook model
The system SHALL map parsed knigavuhe data to the `Audiobook` model with correct field mappings.

#### Scenario: Field mapping
- **WHEN** mapping parsed data to Audiobook
- **THEN** the system sets:
  - `id` = book URL (absolute)
  - `title` = extracted title
  - `author` = extracted author
  - `description` = narrators appended to description (e.g. "Narrated by: X, Y, Z")
  - `lowQCoverImage` = absolute cover URL
  - `totalTime` = parsed duration in minutes
  - `downloads` = download count
  - `rating` = rating if available, null otherwise
  - `language` = "uk" (Ukrainian)
  - `origin` = "knigavuhe"

### Requirement: Display in search UI
The system SHALL display knigavuhe search results in the existing search UI alongside other sources.

#### Scenario: Multi-source search
- **WHEN** the user searches with "all" sources selected
- **THEN** knigavuhe results appear in their designated section/row of the search results screen

#### Scenario: Knigavuhe-only search
- **WHEN** the user searches with knigavuhe source selected
- **THEN** only knigavuhe results are displayed

#### Scenario: Empty results
- **WHEN** knigavuhe returns no books for the query
- **THEN** the knigavuhe section shows an empty state or is hidden

### Requirement: Handle HTML entity decoding
The system SHALL decode HTML entities in text fields (&amp;, &quot;, &#039;, &nbsp;) to displayable characters.

#### Scenario: Standard HTML entities
- **WHEN** text contains &amp;, &quot;, &#039;, or &nbsp;
- **THEN** the system decodes them to &, ", ', or space respectively

### Requirement: Error handling and resilience
The system SHALL handle parsing and network errors gracefully without crashing the search flow.

#### Scenario: Parse error on individual card
- **WHEN** a single book card fails to parse (missing required fields)
- **THEN** the system skips that card and continues parsing remaining cards

#### Scenario: Network timeout or failure
- **WHEN** the HTTP request times out or fails
- **THEN** the system returns an empty result set for knigavuhe and allows other sources to display their results

#### Scenario: HTML structure change
- **WHEN** knigavuhe changes their HTML structure and parsing fails
- **THEN** the system logs a warning and returns empty results (no crash)
