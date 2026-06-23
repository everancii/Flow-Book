import 'dart:async';

class AppEvents {
  /// Fire when visible languages change. Listeners should refresh their data.
  static final languagesChanged = StreamController<void>.broadcast();

  /// Fire when the enabled search sources change (from Settings). Listeners
  /// (search chips, search BLoC) should refresh so the change takes effect
  /// without needing to leave and re-enter the Search tab.
  static final searchSourcesChanged = StreamController<void>.broadcast();

  static void dispose() {
    languagesChanged.close();
    searchSourcesChanged.close();
  }
}
