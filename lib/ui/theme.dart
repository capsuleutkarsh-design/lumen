import 'package:flutter/material.dart';

import '../platform/window.dart' show isTouch;

/// One set of colours. [Palette.dark] is Lumen's look; [Palette.light] is the
/// same design on paper. Text, dim, faint and the accent are at least 4.5:1 on
/// every surface in both (test/extras_test.dart checks it).
class Palette {
  const Palette({
    required this.brightness,
    required this.bg,
    required this.raised1,
    required this.raised2,
    required this.raised3,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.dim,
    required this.faint,
    required this.accent,
    required this.onLight,
    required this.scrim,
    required this.shadow,
    required this.glass,
    required this.glassBorder,
  });
  final Brightness brightness;
  final Color bg, raised1, raised2, raised3, border, borderStrong, text, dim, faint, accent, onLight, scrim, shadow, glass, glassBorder;

  static const dark = Palette(
    brightness: Brightness.dark,
    bg: Color(0xFF000000),
    raised1: Color(0xFF0A0A0B),
    raised2: Color(0xFF131315),
    raised3: Color(0xFF1B1B1E),
    border: Color(0xFF1E1E21),
    borderStrong: Color(0xFF2C2C30),
    text: Color(0xFFF4F4F5),
    dim: Color(0xFFA1A1AA),
    faint: Color(0xFF8A8A93),
    accent: Color(0xFFFF6B4A),
    onLight: Color(0xFF000000),
    scrim: Color(0xB3000000),
    shadow: Color(0x99000000),
    glass: Color(0x59000000),
    glassBorder: Color(0x14FFFFFF),
  );

  /// The coral is a deeper shade here so it stays readable as text on white.
  static const light = Palette(
    brightness: Brightness.light,
    bg: Color(0xFFF3F3F4),
    raised1: Color(0xFFFFFFFF),
    raised2: Color(0xFFF1F1F3),
    raised3: Color(0xFFE7E7EA),
    border: Color(0xFFE4E4E7),
    borderStrong: Color(0xFFD4D4D8),
    text: Color(0xFF18181B),
    dim: Color(0xFF3F3F46),
    faint: Color(0xFF5F5F68),
    accent: Color(0xFFB83214),
    onLight: Color(0xFFFFFFFF),
    scrim: Color(0xB3F3F3F4),
    shadow: Color(0x24000000),
    glass: Color(0x8CFFFFFF),
    glassBorder: Color(0x14000000),
  );
}

/// Settings → Theme: 'dark', 'light' or 'system' (follow Windows).
Palette paletteFor(String mode, Brightness windows) => switch (mode) {
  'light' => Palette.light,
  'system' => windows == Brightness.light ? Palette.light : Palette.dark,
  _ => Palette.dark,
};

/// Design tokens: a 4/8 grid, five type sizes (12 / 14 / 18 / 28 / 44), four
/// radii, one accent used sparingly, motion <= 200 ms. Every colour the UI
/// paints comes from here; [use] switches the palette (then the app rebuilds).
abstract final class C {
  static Palette _p = Palette.dark;
  static Palette get palette => _p;
  static void use(Palette p) => _p = p;
  static bool get isLight => _p.brightness == Brightness.light;

  static Color get bg => _p.bg;
  static Color get raised1 => _p.raised1; // panels
  static Color get raised2 => _p.raised2; // hover, cards
  static Color get raised3 => _p.raised3; // pressed, inputs, selected
  static Color get border => _p.border;
  static Color get borderStrong => _p.borderStrong;
  static Color get text => _p.text;
  static Color get dim => _p.dim;
  static Color get faint => _p.faint; // >= 4.5:1 on every surface
  static Color get accent => _p.accent; // the one accent: coral (now playing, focus, active toggles)
  static Color get accentSoft => _p.accent.withValues(alpha: 0.15);
  static Color get onLight => _p.onLight; // text on the primary button (which is C.text)
  static Color get scrim => _p.scrim; // behind overlays
  static Color get shadow => _p.shadow;
  static Color get glass => _p.glass; // buttons floating on cover art
  static Color get glassBorder => _p.glassBorder;
  static const closeHover = Color(0xFFC42B1C); // the Windows close-button red

  /// The page background at [a] opacity: fades over cover glows (black in dark, paper in light).
  static Color veil(double a) => _p.bg.withValues(alpha: a);
}

abstract final class S {
  static const x1 = 4.0, x2 = 8.0, x3 = 12.0, x4 = 16.0, x5 = 20.0, x6 = 24.0, x8 = 32.0, x10 = 40.0, x12 = 48.0, x16 = 64.0;
}

abstract final class R {
  // Nested: an inner radius = outer radius - the padding between them.
  static const panel = 20.0, card = 16.0, cover = 8.0, small = 8.0, tiny = 4.0, pill = 999.0;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 200); // the ceiling
  static const curve = Curves.easeOutCubic;

  /// Colour changes (the accent taken from the cover art) blend a little slower so they never flash.
  static const colour = Duration(milliseconds: 300);
}

abstract final class T {
  static const _f = 'Inter';
  static const tabular = [FontFeature.tabularFigures()];

  /// Hero titles (album, artist, playlist, Now Playing).
  static TextStyle get display => TextStyle(
    fontFamily: _f,
    fontSize: 44,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
    height: 1.1,
    color: C.text,
  );

  /// Page titles and lyrics.
  static TextStyle get title => TextStyle(
    fontFamily: _f,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
    height: 1.2,
    color: C.text,
  );

  /// Section titles, dialog titles, panel titles.
  static TextStyle get heading => TextStyle(
    fontFamily: _f,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
    color: C.text,
  );
  static TextStyle get body => TextStyle(fontFamily: _f, fontSize: 14, fontWeight: FontWeight.w400, height: 1.4, color: C.text);
  static TextStyle get label => TextStyle(fontFamily: _f, fontSize: 14, fontWeight: FontWeight.w500, height: 1.35, color: C.text);
  static TextStyle get small => TextStyle(fontFamily: _f, fontSize: 14, fontWeight: FontWeight.w400, height: 1.35, color: C.dim);
  static TextStyle get caption => TextStyle(fontFamily: _f, fontSize: 12, fontWeight: FontWeight.w400, height: 1.3, color: C.faint);
  static TextStyle get lyric => title;
}

ThemeData buildTheme() {
  final scheme = (C.isLight ? const ColorScheme.light() : const ColorScheme.dark()).copyWith(
    surface: C.raised1,
    primary: C.accent,
    onPrimary: C.onLight,
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
    dividerTheme: DividerThemeData(color: C.borderStrong, thickness: 1),
    textTheme: TextTheme(bodyMedium: T.body, bodySmall: T.small, labelLarge: T.label),
    tooltipTheme: TooltipThemeData(
      triggerMode: isTouch ? TooltipTriggerMode.manual : null, // a long press opens menus there, not tooltips
      waitDuration: const Duration(milliseconds: 400),
      textStyle: T.caption.copyWith(color: C.text),
      padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1),
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
        side: BorderSide(color: C.borderStrong),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.raised1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.panel),
        side: BorderSide(color: C.borderStrong),
      ),
      titleTextStyle: T.heading,
      contentTextStyle: T.body,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.raised3,
      contentTextStyle: T.label,
      behavior: SnackBarBehavior.floating,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.card - S.x1),
        side: BorderSide(color: C.borderStrong),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.raised2,
      hintStyle: T.body.copyWith(color: C.faint),
      contentPadding: const EdgeInsets.all(S.x3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.small),
        borderSide: BorderSide(color: C.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.small),
        borderSide: BorderSide(color: C.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.small),
        borderSide: BorderSide(color: C.accent),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.text : C.dim),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.accent : C.raised3),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.accent : C.borderStrong),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(C.borderStrong),
      radius: const Radius.circular(R.pill),
      thickness: WidgetStateProperty.all(6),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: C.text,
      inactiveTrackColor: C.raised3,
      thumbColor: C.text,
      overlayColor: Colors.transparent,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 0, pressedElevation: 0),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
      trackShape: const RoundedRectSliderTrackShape(),
    ),
  );
}
