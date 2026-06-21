class LatestVersionFetchModel {
  String? latestVersion;
  String? tagName;
  String? body;
  String? apkDownloadUrl;

  LatestVersionFetchModel({
    this.latestVersion,
    this.tagName,
    this.body,
    this.apkDownloadUrl,
  });

  LatestVersionFetchModel.fromJson(Map<String, dynamic> json) {
    tagName = json['tag_name'] ?? '';
    latestVersion = tagName?.replaceFirst('v', '') ?? '';
    body = json['body'] ?? '';

    final assets = json['assets'] as List<dynamic>?;
    if (assets != null) {
      for (final asset in assets) {
        final name = asset['name'] as String?;
        if (name != null && name.endsWith('.apk') && name.contains('arm64')) {
          apkDownloadUrl = asset['browser_download_url'];
          break;
        }
      }
      if (apkDownloadUrl == null && assets.isNotEmpty) {
        apkDownloadUrl = assets[0]['browser_download_url'];
      }
    }
  }

  List<String> get changelogs {
    if (body == null || body!.isEmpty) return [];
    return body!
        .split('\n')
        .where((line) => line.trim().startsWith('-') || line.trim().startsWith('*'))
        .map((line) => line.trim().replaceFirst(RegExp(r'^[-*]\s*'), ''))
        .where((line) => line.isNotEmpty)
        .toList();
  }
}
