## MODIFIED Requirements

### Requirement: Home screen content sections
The home screen SHALL display the following sections in order, and SHALL NOT display any other discovery or recommendation sections:
1. Welcome section
2. Recently Played (History) section
3. Local Imports section
4. YouTube Imports section
5. 4Read Imports section
6. Favourites section
7. Footer guidance text

The home screen SHALL NOT display:
- A "Recommended for You" horizontal scroll section
- A "Popular All Time" horizontal scroll section
- A "Trending This Week" horizontal scroll section
- A "Browse Genres" grid section

#### Scenario: Home screen renders without discovery sections
- **WHEN** the user navigates to the Home tab
- **THEN** the screen SHALL NOT contain any widget labelled "Recommended for you", "Popular All Time", "Trending This Week", or "Browse Genres"
- **THEN** the screen SHALL still render Welcome, History, Local Imports, YouTube Imports, 4Read Imports, Favourites, and footer guidance sections

#### Scenario: No network calls for discovery data on home load
- **WHEN** the home screen initialises
- **THEN** no Internet Archive API calls SHALL be made for popular, trending, or genre-based audiobook lists
- **THEN** no recommendation genre computation SHALL be performed

#### Scenario: Home screen state is minimal
- **WHEN** the `_HomeState` is created
- **THEN** it SHALL NOT instantiate any `HomeBloc`, `ScrollController` for discovery, or `RecommendationService`

## REMOVED Requirements

### Requirement: Recommended for You section
**Reason**: Removed to simplify the home screen; genre-based discovery is still accessible via Search.
**Migration**: Users who want genre-based discovery should use the Search screen's "Subjects" filter.

### Requirement: Popular All Time section
**Reason**: Removed to reduce clutter and eliminate unnecessary Archive.org API calls on home load.
**Migration**: No replacement; content is accessible via Search.

### Requirement: Trending This Week section
**Reason**: Removed for the same reasons as Popular All Time.
**Migration**: No replacement; content is accessible via Search.

### Requirement: Browse Genres grid on home screen
**Reason**: Removed to simplify the home screen; genre browsing is still accessible from audiobook detail pages.
**Migration**: Use the genre chips on any audiobook detail screen, or use the Search screen's "Subjects" filter.
