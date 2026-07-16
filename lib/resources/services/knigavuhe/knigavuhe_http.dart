import 'package:http/http.dart' as http;

class KnigavuheBlockedException implements Exception {
  const KnigavuheBlockedException();

  static const message =
      'Knigavuhe is temporarily blocking app requests with a browser check. '
      'Try again later or disable Knigavuhe in Settings.';

  @override
  String toString() => message;
}

class KnigavuheHttp {
  static const baseUrl = 'https://knigavuhe.org';

  static const headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'Referer': '$baseUrl/',
  };

  static bool isBlocked(http.Response response) {
    if (response.statusCode == 501 || response.statusCode == 403) {
      return true;
    }
    final body = response.body.toLowerCase();
    return body.contains('/.well-known/ddos-guard/') ||
        body.contains('checking your browser');
  }
}
