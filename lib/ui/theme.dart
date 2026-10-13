import 'package:flutter/material.dart';

/// Design tokens. 4/8 grid, a small type scale, one accent, raised layers a
/// little lighter than the black background, nested radii, motion <= 200 ms.
abstract final class C {
  static const bg = Color(0xFF000000);
  static const raised1 = Color(0xFF0A0A0B); // panels
  static const raised2 = Color(0xFF131315); // hover, cards
  static const raised3 = Color(0xFF1B1B1E); // pressed, inputs, selected
  static const border = Color(0xFF1E1E21);
  static const borderStrong = Color(0xFF2C2C30);
  static const text = Color(0xFFF4F4F5);
  static const dim = Color(0xFFA1A1AA);
  static const faint = Color(0xFF63636B);
  static const accent = Color(0xFFFF6B4A); // the one accent: coral
  static const accentSoft = Color(0x26FF6B4A);
}

abstract final class S {
  static const x1 = 4.0, x2 = 8.0, x3 = 12.0, x4 = 16.0, x5 = 20.0, x6 = 24.0, x8 = 32.0, x10 = 40.0, x12 = 48.0;
}

abstract final class R {
  // Nested: an inner radius = outer radius - padding between them.
  static const panel = 20.0, card = 16.0, cover = 10.0, small = 8.0, pill = 999.0;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 180);
  static const curve = Curves.easeOutCubic;
}

abstract final class T {
  static const _f = 'Inter';
  static const tabular = [FontFeature.tabularFigures()];
  static const display = TextStyle(
    fontFamily: _f,
    fontSize: 32,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
    height: 1.15,
    color: C.text,
  );
  static const title = TextStyle(
    fontFamily: _f,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.25,
    color: C.text,
  );
  static const heading = TextStyle(
    fontFamily: _f,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.3,
    color: C.text,
  );
  static const body = TextStyle(fontFamily: _f, fontSize: 14, fontWeight: FontWeight.w400, height: 1.4, color: C.text);
  static const label = TextStyle(fontFamily: _f, fontSize: 13, fontWeight: FontWeight.w500, height: 1.35, color: C.text);
  static const small = TextStyle(fontFamily: _f, fontSize: 13, fontWeight: FontWeight.w400, height: 1.35, color: C.dim);
  static const caption = TextStyle(fontFamily: _f, fontSize: 12, fontWeight: FontWeight.w400, height: 1.3, color: C.faint);
  static const lyric = TextStyle(
    fontFamily: _f,
    fontSize: 30,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    height: 1.3,
    color: C.text,
  );
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    surface: C.raised1,
    primary: C.accent,
    onPrimary: Colors.black,
    secondary: C.accent,
    onSurface: C.text,
    outline: C.border,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: C.raised2,
    focusColor: C.accentSoft,
    dividerColor: C.border,
    textTheme: const TextTheme(bodyMedium: T.body, bodySmall: T.small, labelLarge: T.label),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      textStyle: T.caption.copyWith(color: C.text),
      padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1 + 2),
      decoration: BoxDecoration(
        color: C.raised3,
        borderRadius: BorderRadius.circular(R.small),
        border: Border.all(color: C.borderStrong),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: C.raised2,
      elevation: 8,
      textStyle: T.label,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.card - S.x1),
        side: const BorderSide(color: C.borderStrong),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.raised1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.panel),
        side: const BorderSide(color: C.borderStrong),
      ),
      titleTextStyle: T.title,
      contentTextStyle: T.body,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.raised3,
      contentTextStyle: T.label,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.small + 4),
        side: const BorderSide(color: C.borderStrong),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.raised2,
      hintStyle: T.body.copyWith(color: C.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.small + 2),
        borderSide: const BorderSide(color: C.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.small + 2),
        borderSide: const BorderSide(color: C.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.small + 2),
        borderSide: const BorderSide(color: C.accent),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : C.dim),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.accent : C.raised3),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.accent : C.borderStrong),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(C.borderStrong),
      radius: const Radius.circular(R.pill),
      thickness: WidgetStateProperty.all(6),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 4,
      activeTrackColor: C.text,
      inactiveTrackColor: C.raised3,
      thumbColor: C.text,
      overlayColor: Colors.transparent,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 0, pressedElevation: 0),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
      trackShape: RoundedRectSliderTrackShape(),
    ),
  );
}
