import 'dart:convert';
import 'package:audiobookflow/utils/app_logger.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

class FourReadAuthService {
  static const String _boxName = 'four_read_auth';
  static const String _credentialsKey = 'credentials';
  static const String _cookiesKey = 'cookies';

  Box get _box => Hive.box(_boxName);

  Future<bool> isLoggedIn() async {
    final cookies = _box.get(_cookiesKey) as String?;
    return cookies != null && cookies.isNotEmpty;
  }

  Future<Map<String, String>?> getCredentials() async {
    final data = _box.get(_credentialsKey) as String?;
    if (data == null) return null;
    return jsonDecode(data) as Map<String, String>;
  }

  Future<void> saveCredentials(String username, String password) async {
    await _box.put(_credentialsKey, jsonEncode({
      'username': username,
      'password': password,
    }));
  }

  Future<void> clearCredentials() async {
    await _box.delete(_credentialsKey);
    await _box.delete(_cookiesKey);
  }

  Future<void> saveCookies(String cookies) async {
    await _box.put(_cookiesKey, cookies);
  }

  Future<String?> getCookies() async {
    return _box.get(_cookiesKey) as String?;
  }

  Future<bool> login(String username, String password) async {
    try {
      // First get the login page to extract CSRF token and session cookies
      final initialResponse = await http.get(
        Uri.parse('https://4read.org/'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      );

      // Extract initial cookies
      final initialCookies = <String>[];
      initialResponse.headers.forEach((key, value) {
        if (key.toLowerCase() == 'set-cookie') {
          initialCookies.add(value.split(';').first);
        }
      });

      // Extract dle_login_hash from HTML
      final hashMatch = RegExp(r"dle_login_hash\s*=\s*'([^']+)'").firstMatch(initialResponse.body);
      final loginHash = hashMatch?.group(1) ?? '';
      AppLogger.debug('[FourReadAuth] Login hash: $loginHash', 'FourReadAuth');

      // Now login with cookies and hash
      final response = await http.post(
        Uri.parse('https://4read.org/'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Referer': 'https://4read.org/',
          'Origin': 'https://4read.org',
          if (initialCookies.isNotEmpty) 'Cookie': initialCookies.join('; '),
        },
        body: {
          'login_name': username,
          'login_password': password,
          'login': 'submit',
          'login_hash': loginHash,
        },
      );

      AppLogger.debug('[FourReadAuth] Login response: ${response.statusCode}', 'FourReadAuth');

      // Collect ALL cookies from all responses
      final allCookies = <String>[];
      allCookies.addAll(initialCookies);
      
      response.headers.forEach((key, value) {
        if (key.toLowerCase() == 'set-cookie') {
          allCookies.add(value.split(';').first);
        }
      });

      // Also follow any redirects to get more cookies
      if (response.statusCode == 302 || response.statusCode == 301) {
        final location = response.headers['location'];
        if (location != null) {
          final redirectUrl = location.startsWith('http') ? location : 'https://4read.org$location';
          final redirectResponse = await http.get(
            Uri.parse(redirectUrl),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
              'Cookie': allCookies.join('; '),
            },
          );
          redirectResponse.headers.forEach((key, value) {
            if (key.toLowerCase() == 'set-cookie') {
              allCookies.add(value.split(';').first);
            }
          });
        }
      }

      // Save credentials and cookies
      final cookieString = allCookies.join('; ');
      AppLogger.debug('[FourReadAuth] All cookies: $cookieString', 'FourReadAuth');

      if (allCookies.isNotEmpty) {
        await saveCredentials(username, password);
        await saveCookies(cookieString);
        
        // Check if login was successful
        final isLoggedIn = cookieString.contains('dle_user_id') || 
                          response.body.contains('logout') ||
                          response.body.contains('Вихід') ||
                          response.body.contains('Профіль');
        
        AppLogger.debug('[FourReadAuth] Login ${isLoggedIn ? "successful" : "may have failed"}', 'FourReadAuth');
        return true;
      }

      AppLogger.debug('[FourReadAuth] Login failed - no cookies received', 'FourReadAuth');
      return false;
    } catch (e) {
      AppLogger.debug('[FourReadAuth] Login error: $e', 'FourReadAuth');
      return false;
    }
  }

  /// Get authenticated headers for 4read requests
  Future<Map<String, String>> getAuthHeaders() async {
    final cookies = await getCookies();
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Referer': 'https://4read.org/',
    };

    if (cookies != null && cookies.isNotEmpty) {
      headers['Cookie'] = cookies;
    }

    return headers;
  }
}
