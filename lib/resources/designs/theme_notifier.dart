import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'themes.dart';

enum AppTheme { light, dark, blue }

class ThemeNotifier extends ChangeNotifier {
  AppTheme _currentTheme = AppTheme.light;
  AppTheme get currentTheme => _currentTheme;

  final Box<dynamic> _themeBox = Hive.box('theme_mode_box');

  ThemeNotifier() {
    _loadTheme();
  }

  void _loadTheme() {
    final saved = _themeBox.get('theme_mode_box', defaultValue: 'light') as String;

    switch (saved) {
      case 'dark':
        _currentTheme = AppTheme.dark;
        break;
      case 'blue':
        _currentTheme = AppTheme.blue;
        break;
      default:
        _currentTheme = AppTheme.light;
    }
    notifyListeners();
  }

  void setTheme(AppTheme theme) {
    _currentTheme = theme;
    final value = theme.name;
    _themeBox.put('theme_mode_box', value);
    notifyListeners();
  }

  ThemeData getThemeData() {
    switch (_currentTheme) {
      case AppTheme.dark:
        return Themes.darkTheme;
      case AppTheme.blue:
        return Themes.blueTheme;
      case AppTheme.light:
      default:
        return Themes.lightTheme;
    }
  }

  ThemeMode get themeMode {
    if (_currentTheme == AppTheme.dark) return ThemeMode.dark;
    return ThemeMode.light;
  }
}
