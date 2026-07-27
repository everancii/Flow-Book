import 'dart:async';

class AppEvents {
  /// Fire when the enabled search sources change (from Settings). Listeners
  /// (search chips, search BLoC) should refresh so the change takes effect
  /// without needing to leave and re-enter the Search tab.
  static final searchSourcesChanged = StreamController<void>.broadcast();

  static void dispose() {
    searchSourcesChanged.close();
  }
}
