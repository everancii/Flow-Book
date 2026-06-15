import 'dart:convert';

import 'package:audiobookflow/resources/models/audiobook_file.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;

class KnigavuheDetailResult {
  final List<AudiobookFile> files;
  final String? description;

  KnigavuheDetailResult({required this.files, this.description});
}

class KnigavuheDetailService {
  Future<Either<String, KnigavuheDetailResult>> getAudiobookFiles(
      String bookUrl) async {
    try {
      final response = await http.get(
        Uri.parse(bookUrl),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Referer': 'https://knigavuhe.org/',
        },
      );

      if (response.statusCode != 200) {
        return Left('Failed to load knigavuhe page: ${response.statusCode}');
      }

      return _parsePage(response.body);
    } catch (e) {
      return Left('Failed to load knigavuhe audiobook: $e');
    }
  }

  Either<String, KnigavuheDetailResult> _parsePage(String html) {
    // Check if the book is blocked/restricted
    final bookDataMatch =
        RegExp(r'cur\.book\s*=\s*(\{[^}]+\})').firstMatch(html);
    if (bookDataMatch != null) {
      try {
        final bookData =
            jsonDecode(bookDataMatch.group(1)!) as Map<String, dynamic>;
        if (bookData['blocked'] == true) {
          return Left(
              'This audiobook is not available for streaming on knigavuhe.');
        }
      } catch (_) {}
    }

    // Extract full description from book_description div
    String? description;
    final descMatch = RegExp(
            r'<div[^>]*class="book_description"[^>]*>(.*?)</div>',
            dotAll: true)
        .firstMatch(html);
    if (descMatch != null) {
      description = descMatch
          .group(1)!
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&#039;', "'")
          .replaceAll('&nbsp;', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    // Extract the BookPlayer constructor call which contains the tracks JSON
    final match = RegExp(r'new BookPlayer\(\d+,\s*(\[.*?\])\s*,',
            dotAll: true)
        .firstMatch(html);

    if (match == null) {
      return Left(
          'Could not find audio tracks. This book may not be available for streaming.');
    }

    try {
      final tracksJson = jsonDecode(match.group(1)!) as List;
      final files = <AudiobookFile>[];

      for (var i = 0; i < tracksJson.length; i++) {
        final track = tracksJson[i];
        final url = track['url'] as String?;
        final title = track['title'] as String?;
        final duration = (track['duration'] as num?)?.toDouble();

        if (url == null || url.isEmpty) continue;

        files.add(AudiobookFile.fromMap({
          'identifier': 'knigavuhe',
          'title': title ?? 'Track ${i + 1}',
          'name': title,
          'track': i + 1,
          'size': 0,
          'length': duration,
          'url': url,
          'highQCoverImage': null,
          'startMs': null,
          'durationMs': null,
        }));
      }

      if (files.isEmpty) {
        return Left('No audio tracks found');
      }

      return Right(KnigavuheDetailResult(files: files, description: description));
    } catch (e) {
      return Left('Failed to parse knigavuhe tracks: $e');
    }
  }
}
