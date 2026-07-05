/// Compares two semantic version strings (e.g., "1.1.8" vs "1.2.0").
///
/// Returns:
///   -1 if a < b
///    0 if a == b
///    1 if a > b
int compareVersions(String a, String b) {
  final aParts = a.split('.').map(int.tryParse).toList();
  final bParts = b.split('.').map(int.tryParse).toList();

  final length = aParts.length > bParts.length ? aParts.length : bParts.length;

  for (var i = 0; i < length; i++) {
    final aVal = (i < aParts.length) ? (aParts[i] ?? 0) : 0;
    final bVal = (i < bParts.length) ? (bParts[i] ?? 0) : 0;

    if (aVal < bVal) return -1;
    if (aVal > bVal) return 1;
  }

  return 0;
}
