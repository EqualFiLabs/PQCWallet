import 'package:flutter/material.dart';

ThemeData cyberpunkTheme() {
  const bg = Color(0xFF0B0E14);
  const surface = Color(0xFF11151F);
  const neon = Color(0xFF00E5FF);
  const magenta = Color(0xFFFF3D81);

  final colorScheme = ColorScheme.dark(
    surface: surface,
    primary: neon,
    secondary: magenta,
    onPrimary: Colors.black,
    onSecondary: Colors.white,
    error: Colors.redAccent,
  );

  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: bg,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: Colors.white70),
      bodyLarge: TextStyle(color: Colors.white),
      titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: neon,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12))),
        elevation: 0,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0x151BE0FF),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none),
      hintStyle: TextStyle(color: Colors.white54),
    ),
  );
}
