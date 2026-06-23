import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:audiobookflow/resources/services/four_read/four_read_auth_service.dart';
import 'package:audiobookflow/utils/app_logger.dart';

class FourReadWebViewLogin extends StatefulWidget {
  const FourReadWebViewLogin({super.key});

  @override
  State<FourReadWebViewLogin> createState() => _FourReadWebViewLoginState();
}

class _FourReadWebViewLoginState extends State<FourReadWebViewLogin> {
  InAppWebViewController? _webViewController;
  final FourReadAuthService _authService = FourReadAuthService();
  bool _isLoggedIn = false;
  bool _isLoading = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('4Read Login'),
        actions: [
          if (_isLoggedIn)
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Done', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri('https://4read.org/'),
            ),
            initialSettings: InAppWebViewSettings(
              useOnLoadResource: true,
              javaScriptEnabled: true,
              useShouldOverrideUrlLoading: true,
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final url = navigationAction.request.url.toString();
              if (url.startsWith('intent://') || url.startsWith('market://')) {
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
            onLoadStart: (controller, url) {
              AppLogger.debug('[FourReadWebView] Loading: $url', 'FourReadWebView');
            },
            onLoadStop: (controller, url) async {
              AppLogger.debug('[FourReadWebView] Loaded: $url', 'FourReadWebView');
              
              // Check if we're logged in by looking for logout link or user profile
              final isLoggedIn = await controller.evaluateJavascript(
                source: '''
                  document.querySelector('.header__btn-login')?.textContent?.includes('Вийти') ||
                  document.querySelector('.header__btn-login')?.textContent?.includes('Вихід') ||
                  document.querySelector('[href*="logout"]') !== null ||
                  document.querySelector('.user-menu') !== null
                ''',
              );
              
              AppLogger.debug('[FourReadWebView] Is logged in: $isLoggedIn', 'FourReadWebView');
              
              if (isLoggedIn == true) {
                // Extract cookies from CookieManager
                final cookieManager = CookieManager.instance();
                final cookies = await cookieManager.getCookies(url: WebUri('https://4read.org/'));
                AppLogger.debug('[FourReadWebView] Cookies: $cookies', 'FourReadWebView');
                
                if (cookies != null && cookies.isNotEmpty) {
                  final cookieString = cookies
                      .map((cookie) => '${cookie.name}=${cookie.value}')
                      .join('; ');
                  
                  await _authService.saveCookies(cookieString);
                  setState(() => _isLoggedIn = true);
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Login successful!'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
              
              setState(() => _isLoading = false);
            },
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
