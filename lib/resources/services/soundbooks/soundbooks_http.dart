import 'package:http/http.dart' as http;

class SoundBooksBlockedException implements Exception {
  const SoundBooksBlockedException();

  static const message =
      'Sound-Books is temporarily blocking app requests with a browser check. '
      'Try again later or disable Sound-Books in Settings.';

  @override
  String toString() => message;
}

class SoundBooksHttp {
  static const baseUrl = 'https://sound-books.net';

  static const headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'uk-UA,uk;q=0.9,en-US;q=0.8,en;q=0.7',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'Referer': '$baseUrl/',
  };

  static bool isBlocked(http.Response response) {
    final server = response.headers['server']?.toLowerCase() ?? '';
    final body = response.body.toLowerCase();
    return server.contains('ddos-guard') ||
        body.contains('ddos-guard') ||
        body.contains('/.well-known/ddos-guard/') ||
        body.contains('checking your browser');
  }
}
