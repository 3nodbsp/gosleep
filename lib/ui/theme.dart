import 'package:flutter/material.dart';

/// 睡眠主题：深夜蓝底、低饱和靛蓝主色，暗光环境友好。
ThemeData buildSleepTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6C8FE0),
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF080C16),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
  );
}

/// 卡片底色（深夜蓝卡片）。
const Color kCardColor = Color(0xFF101728);
