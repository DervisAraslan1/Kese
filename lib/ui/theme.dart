import 'package:flutter/material.dart';

import '../core/models.dart';

class KeseTheme {
  const KeseTheme({
    required this.id,
    required this.name,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.accent,
    required this.onAccent,
    required this.ink,
    required this.inkSoft,
    required this.good,
    required this.danger,
  });

  final String id;
  final String name;
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color accent;
  final Color onAccent;
  final Color ink;
  final Color inkSoft;
  final Color good;
  final Color danger;
}

const themes = [
  KeseTheme(
    id: 'zumrut',
    name: 'Zümrüt',
    brightness: Brightness.dark,
    background: Color(0xFF08160F),
    surface: Color(0xFF0F2219),
    surfaceHigh: Color(0xFF173126),
    accent: Color(0xFF3FD6A0),
    onAccent: Color(0xFF04140D),
    ink: Color(0xFFECF6F1),
    inkSoft: Color(0xFFA9C4B8),
    good: Color(0xFF6EE7B7),
    danger: Color(0xFFF87171),
  ),
  KeseTheme(
    id: 'gece',
    name: 'Gece',
    brightness: Brightness.dark,
    background: Color(0xFF0A1228),
    surface: Color(0xFF101B36),
    surfaceHigh: Color(0xFF192849),
    accent: Color(0xFF6EA8FF),
    onAccent: Color(0xFF07122B),
    ink: Color(0xFFEEF3FF),
    inkSoft: Color(0xFFA9B8D8),
    good: Color(0xFF34D399),
    danger: Color(0xFFF87171),
  ),
  KeseTheme(
    id: 'kehribar',
    name: 'Kehribar',
    brightness: Brightness.dark,
    background: Color(0xFF0C0D11),
    surface: Color(0xFF16181E),
    surfaceHigh: Color(0xFF22252D),
    accent: Color(0xFFF5A524),
    onAccent: Color(0xFF1A1203),
    ink: Color(0xFFF3F1EA),
    inkSoft: Color(0xFFB3B3AC),
    good: Color(0xFF34D399),
    danger: Color(0xFFF87171),
  ),
  KeseTheme(
    id: 'kum',
    name: 'Kum',
    brightness: Brightness.light,
    background: Color(0xFFF6F2E9),
    surface: Color(0xFFFFFDF8),
    surfaceHigh: Color(0xFFEFE8DA),
    accent: Color(0xFF0B7A55),
    onAccent: Color(0xFFFFFFFF),
    ink: Color(0xFF1A1B20),
    inkSoft: Color(0xFF5A5A55),
    good: Color(0xFF047857),
    danger: Color(0xFFB91C1C),
  ),
];

KeseTheme themeById(String id) =>
    themes.firstWhere((t) => t.id == id, orElse: () => themes.first);

ThemeData buildTheme(KeseTheme t) {
  final scheme = ColorScheme(
    brightness: t.brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    secondary: t.accent,
    onSecondary: t.onAccent,
    // Selected chips and the navigation icon sit on these: without them they
    // inherit the dark on-accent color and vanish on dark themes.
    secondaryContainer: t.accent.withValues(alpha: 0.22),
    onSecondaryContainer: t.ink,
    error: t.danger,
    onError: t.onAccent,
    surface: t.surface,
    onSurface: t.ink,
    onSurfaceVariant: t.inkSoft,
    surfaceContainerHighest: t.surfaceHigh,
    surfaceContainerHigh: t.surfaceHigh,
    surfaceContainer: t.surface,
    outline: t.inkSoft.withValues(alpha: 0.5),
    outlineVariant: t.inkSoft.withValues(alpha: 0.18),
  );
  final radius = BorderRadius.circular(18);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.background,
    extensions: [KeseColors(good: t.good, danger: t.danger)],
    appBarTheme: AppBarTheme(
      backgroundColor: t.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: t.ink,
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      indicatorColor: t.accent.withValues(alpha: 0.2),
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surfaceHigh,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.surfaceHigh,
      contentTextStyle: TextStyle(color: t.ink),
      actionTextColor: t.accent,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

class KeseColors extends ThemeExtension<KeseColors> {
  const KeseColors({required this.good, required this.danger});

  final Color good;
  final Color danger;

  @override
  KeseColors copyWith({Color? good, Color? danger}) =>
      KeseColors(good: good ?? this.good, danger: danger ?? this.danger);

  @override
  KeseColors lerp(KeseColors? other, double t) => other == null
      ? this
      : KeseColors(
          good: Color.lerp(good, other.good, t)!,
          danger: Color.lerp(danger, other.danger, t)!,
        );
}

extension KeseThemeContext on BuildContext {
  KeseColors get keseColors => Theme.of(this).extension<KeseColors>()!;
}

IconData categoryIcon(Category category) => switch (category) {
      Category.market => Icons.shopping_basket_outlined,
      Category.yemek => Icons.restaurant_outlined,
      Category.ulasim => Icons.directions_bus_outlined,
      Category.fatura => Icons.receipt_long_outlined,
      Category.ev => Icons.home_outlined,
      Category.eglence => Icons.local_activity_outlined,
      Category.saglik => Icons.favorite_outline,
      Category.abonelik => Icons.autorenew,
      Category.diger => Icons.category_outlined,
      Category.gelir => Icons.south_west,
    };

Color categoryColor(Category category) => switch (category) {
      Category.market => const Color(0xFF3BA776),
      Category.yemek => const Color(0xFFE07B39),
      Category.ulasim => const Color(0xFF4A8DF0),
      Category.fatura => const Color(0xFFD9A520),
      Category.ev => const Color(0xFF9A7BF0),
      Category.eglence => const Color(0xFFDC5F92),
      Category.saglik => const Color(0xFFE5534B),
      Category.abonelik => const Color(0xFF2FB3C4),
      Category.diger => const Color(0xFF8A94A6),
      Category.gelir => const Color(0xFF34B583),
    };
