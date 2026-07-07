import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'models/latest_version_fetch_model.dart';
import '../utils/app_logger.dart';

class LatestVersionFetch {
  static const _updateChannel = MethodChannel('app_update_channel');
  static const _apiUrl =
      'https://api.github.com/repos/everancii/Flow-Book/releases/latest';

  Future<Either<String, LatestVersionFetchModel>> getLatestVersion() async {
    try {
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return Right(LatestVersionFetchModel.fromJson(json));
      } else {
        return Left('Failed to fetch latest version (${response.statusCode})');
      }
    } catch (e) {
      return Left('Failed to fetch latest version');
    }
  }

  Future<String?> getApkPath(String version) async {
    final directory = await getExternalStorageDirectory();
    if (directory == null) return null;
    final file = File('${directory.path}/$version.apk');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  Future<bool> downloadUpdate(String downloadUrl, String version) async {
    try {
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode == 200) {
        final directory = await getExternalStorageDirectory();
        if (directory == null) return false;
        final file = File('${directory.path}/$version.apk');
        await file.writeAsBytes(response.bodyBytes);
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.error('Error downloading update: $e', 'LatestVersionFetch');
      return false;
    }
  }

  Future<void> installUpdate(String version) async {
    try {
      final apkPath = await getApkPath(version);
      if (apkPath != null) {
        await _updateChannel.invokeMethod('installApk', {'apkPath': apkPath});
      }
    } catch (e) {
      AppLogger.error('Installation error: $e', 'LatestVersionFetch');
      rethrow;
    }
  }

  Future<void> downloadAndInstallUpdate(
    LatestVersionFetchModel updateInfo,
  ) async {
    final version = updateInfo.latestVersion;
    if (version == null || version.isEmpty) {
      throw StateError('Update version is missing.');
    }

    final downloadUrl = await _downloadUrlForDevice(updateInfo);
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw StateError('No compatible APK was found for this device.');
    }

    final downloaded = await downloadUpdate(downloadUrl, version);
    if (!downloaded) {
      throw StateError('Could not download the update APK.');
    }

    await installUpdate(version);
  }

  Future<String?> _downloadUrlForDevice(
    LatestVersionFetchModel updateInfo,
  ) async {
    if (!Platform.isAndroid) return updateInfo.apkDownloadUrl;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    return updateInfo.apkDownloadUrlForAbis(androidInfo.supportedAbis);
  }
}
