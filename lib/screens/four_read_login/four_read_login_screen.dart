import 'package:audiobookflow/resources/services/four_read/four_read_auth_service.dart';
import 'package:audiobookflow/screens/four_read_login/four_read_webview_login.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FourReadLoginScreen extends StatefulWidget {
  const FourReadLoginScreen({super.key});

  @override
  State<FourReadLoginScreen> createState() => _FourReadLoginScreenState();
}

class _FourReadLoginScreenState extends State<FourReadLoginScreen> {
  final _authService = FourReadAuthService();
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final loggedIn = await _authService.isLoggedIn();
    setState(() => _isLoggedIn = loggedIn);
  }

  Future<void> _loginWithWebView() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const FourReadWebViewLogin(),
      ),
    );

    if (result == true) {
      setState(() => _isLoggedIn = true);
    }
  }

  Future<void> _logout() async {
    await _authService.clearCredentials();
    setState(() => _isLoggedIn = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logged out successfully'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '4Read Login',
          style: GoogleFonts.ubuntu(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              _isLoggedIn ? Icons.check_circle : Icons.login,
              size: 64,
              color: _isLoggedIn ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _isLoggedIn ? 'Logged In' : 'Login to 4Read',
              textAlign: TextAlign.center,
              style: GoogleFonts.ubuntu(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isLoggedIn
                  ? 'Access exclusive audiobooks'
                  : 'Login via browser to access exclusive content',
              textAlign: TextAlign.center,
              style: GoogleFonts.ubuntu(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            if (!_isLoggedIn) ...[
              ElevatedButton.icon(
                onPressed: _loginWithWebView,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Login via Browser'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'You will be redirected to 4read.org to login securely',
                textAlign: TextAlign.center,
                style: GoogleFonts.ubuntu(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
