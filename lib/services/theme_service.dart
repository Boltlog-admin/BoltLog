import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple app-wide theme controller.
///
/// - Supports only light and dark modes.
/// - Persists the selection using SharedPreferences.
class ThemeService {
  static const _themeKey = 'theme_mode_v1';

  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  /// Load saved theme from storage at app start.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeKey);
    if (value == 'dark') {
      themeMode.value = ThemeMode.dark;
    } else {
      themeMode.value = ThemeMode.light;
    }
  }

  static ThemeMode currentMode() => themeMode.value;

  static Future<void> _persist(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode == ThemeMode.dark ? 'dark' : 'light');
  }

  static void setLight() {
    themeMode.value = ThemeMode.light;
    _persist(ThemeMode.light);
  }

  static void setDark() {
    themeMode.value = ThemeMode.dark;
    _persist(ThemeMode.dark);
  }
}

