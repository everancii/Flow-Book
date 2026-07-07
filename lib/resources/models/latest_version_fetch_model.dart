class LatestVersionFetchModel {
  String? latestVersion;
  String? tagName;
  String? body;
  String? apkDownloadUrl;
  final Map<String, String> apkDownloadUrlsByAbi = {};

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
        final downloadUrl = asset['browser_download_url'] as String?;
        if (name == null || downloadUrl == null || !name.endsWith('.apk')) {
          continue;
        }

        if (name.contains('arm64-v8a')) {
          apkDownloadUrlsByAbi['arm64-v8a'] = downloadUrl;
        } else if (name.contains('armeabi-v7a')) {
          apkDownloadUrlsByAbi['armeabi-v7a'] = downloadUrl;
        } else if (name.contains('x86_64')) {
          apkDownloadUrlsByAbi['x86_64'] = downloadUrl;
        } else {
          apkDownloadUrlsByAbi['universal'] = downloadUrl;
        }

        apkDownloadUrl ??= downloadUrl;
      }

      if (apkDownloadUrl == null) {
        for (final asset in assets) {
          final name = asset['name'] as String?;
          if (name != null && name.endsWith('.apk')) {
            apkDownloadUrl = asset['browser_download_url'];
            break;
          }
        }
      }
      if (apkDownloadUrl == null && assets.isNotEmpty) {
        apkDownloadUrl = assets[0]['browser_download_url'];
      }
    }
  }

  String? apkDownloadUrlForAbis(List<String> supportedAbis) {
    for (final abi in supportedAbis) {
      final url = apkDownloadUrlsByAbi[abi];
      if (url != null) return url;
    }
    return apkDownloadUrlsByAbi['universal'] ?? apkDownloadUrl;
  }

  List<String> get changelogs {
    if (body == null || body!.isEmpty) return [];
    return body!
        .split('\n')
        .where((line) =>
            line.trim().startsWith('-') || line.trim().startsWith('*'))
        .map((line) => line.trim().replaceFirst(RegExp(r'^[-*]\s*'), ''))
        .where((line) => line.isNotEmpty)
        .toList();
  }
}
