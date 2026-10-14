import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/models.dart';
import 'theme.dart';

String fmtTime(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

String fmtLong(Duration d) {
  final m = d.inMinutes;
  return m >= 60 ? '${m ~/ 60} h ${m % 60} min' : '$m min';
}

String plural(int n, String word) => '${fmtInt(n)} $word${n == 1 ? '' : 's'}';

/// 20000 -> "20,000".
String fmtInt(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// Height of [lines] of text at the user's text size (cards size their grids with it).
double textHeight(BuildContext context, List<TextStyle> lines) {
  final s = MediaQuery.textScalerOf(context);
  return lines.fold(0.0, (h, t) => h + s.scale(t.fontSize!) * t.height!);
}

/// A raised, 1 px bordered surface.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.radius = R.panel, this.padding = EdgeInsets.zero, this.color = C.raised1});
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: C.border),
    ),
    child: child,
  );
}

class _MenuIntent extends Intent {
  const _MenuIntent();
}

/// Hover / pressed / selected / focus / disabled states for anything clickable.
/// Enter activates ([onActivate], else tap, else double-tap); the menu key or
/// Shift+F10 opens the right-click menu.
class Clickable extends StatefulWidget {
  const Clickable({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onActivate,
    this.onSecondaryTapDown,
    this.onHover,
    this.radius = R.small,
    this.hover = C.raised2,
    this.pressed = C.raised3,
    this.selected = false,
    this.selectedColor,
    this.padding = EdgeInsets.zero,
    this.tooltip,
    this.semanticLabel,
    this.cursor = SystemMouseCursors.click,
    this.spaceActivates = true,
    this.focusOnTap = false,
    this.onFocusChange,
  });
  final Widget child;
  final VoidCallback? onTap, onDoubleTap, onActivate;
  final GestureTapDownCallback? onSecondaryTapDown;
  final ValueChanged<bool>? onHover;
  final double radius;
  final Color hover, pressed;
  final Color? selectedColor;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final String? tooltip, semanticLabel;
  final MouseCursor cursor;

  /// False for list rows: Space stays play/pause there (Enter plays the row).
  final bool spaceActivates;

  /// List rows take the keyboard focus when clicked, so the arrow keys carry on from there.
  final bool focusOnTap;
  final ValueChanged<bool>? onFocusChange;

  /// Whether the focused widget should get Space itself (a button) instead of the global play/pause.
  static bool ownsSpace(BuildContext focused) {
    final c = focused.findAncestorWidgetOfExactType<Clickable>();
    if (c != null) return c.spaceActivates;
    return focused.findAncestorWidgetOfExactType<Switch>() != null || focused.findAncestorWidgetOfExactType<Checkbox>() != null;
  }

  @override
  State<Clickable> createState() => _ClickableState();
}

class _ClickableState extends State<Clickable> {
  bool _hover = false, _down = false, _focus = false;
  bool get _enabled => widget.onTap != null || widget.onDoubleTap != null || widget.onActivate != null;
  FocusNode? _node;

  @override
  void initState() {
    super.initState();
    if (widget.focusOnTap) _node = FocusNode();
  }

  @override
  void dispose() {
    _node?.dispose();
    super.dispose();
  }

  void _menu() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || widget.onSecondaryTapDown == null) return;
    final at = box.localToGlobal(Offset(S.x4, box.size.height));
    widget.onSecondaryTapDown!(TapDownDetails(globalPosition: at, kind: ui.PointerDeviceKind.mouse));
  }

  @override
  Widget build(BuildContext context) {
    final bg = !_enabled
        ? Colors.transparent
        : _down
        ? widget.pressed
        : widget.selected
        ? (widget.selectedColor ?? widget.hover)
        : _hover
        ? widget.hover
        : Colors.transparent;
    Widget w = FocusableActionDetector(
      focusNode: _node,
      onFocusChange: widget.onFocusChange,
      enabled: _enabled || widget.onSecondaryTapDown != null,
      mouseCursor: _enabled ? widget.cursor : MouseCursor.defer,
      onShowHoverHighlight: (v) {
        setState(() => _hover = v);
        widget.onHover?.call(v);
      },
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.contextMenu): _MenuIntent(),
        SingleActivator(LogicalKeyboardKey.f10, shift: true): _MenuIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => (widget.onActivate ?? widget.onTap ?? widget.onDoubleTap)?.call()),
        _MenuIntent: CallbackAction<_MenuIntent>(onInvoke: (_) => _menu()),
      },
      child: Listener(
        // On pointer down, not on tap: a tap competing with a double-tap fires late.
        onPointerDown: _node == null ? null : (_) => _node!.requestFocus(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            padding: widget.padding,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(widget.radius)),
            // The focus ring is drawn on top, so it never moves the content.
            // A selected row already shows where the focus is.
            foregroundDecoration: _focus && !(widget.selected && widget.selectedColor != null)
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.radius),
                    border: Border.all(color: C.accent, width: 1.5),
                  )
                : null,
            child: widget.child,
          ),
        ),
      ),
    );
    w = Semantics(container: true, button: _enabled, enabled: _enabled, selected: widget.selected, label: widget.semanticLabel, child: w);
    if (widget.tooltip != null) w = Tooltip(message: widget.tooltip!, excludeFromSemantics: widget.semanticLabel != null, child: w);
    return w;
  }
}

class IconBtn extends StatelessWidget {
  const IconBtn(this.icon, {super.key, this.onTap, this.tooltip, this.size = 18, this.box = 36, this.color = C.dim, this.active = false});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size, box;
  final Color color;
  final bool active;
  @override
  Widget build(BuildContext context) => Clickable(
    onTap: onTap,
    tooltip: tooltip,
    semanticLabel: tooltip?.split('  ').first,
    radius: R.pill,
    child: Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: SizedBox(
        width: box,
        height: box,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: size, color: active ? C.accent : color),
            if (active)
              Positioned(
                bottom: S.x1 - 1,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(color: C.accent, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Pill button. One primary per view; the rest are secondary.
class PillButton extends StatelessWidget {
  const PillButton(this.label, {super.key, this.icon, this.onTap, this.primary = false, this.dense = false, this.glass = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary, dense;

  /// Secondary button sitting on cover art (hero, Now Playing).
  final bool glass;
  @override
  Widget build(BuildContext context) {
    final fg = primary ? C.onLight : C.text;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: primary ? C.text : (glass ? C.glass : Colors.transparent),
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: primary ? C.text : (glass ? C.glassBorder : C.borderStrong)),
        ),
        child: Clickable(
          onTap: onTap,
          radius: R.pill,
          semanticLabel: label,
          hover: primary ? const Color(0x1A000000) : C.raised2,
          pressed: primary ? const Color(0x33000000) : C.raised3,
          padding: EdgeInsets.symmetric(horizontal: dense ? S.x3 : S.x5, vertical: dense ? S.x1 + 2 : S.x2 + 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: S.x2)],
              Text(label, style: T.label.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ cover art

/// FNV-1a: the same album always gets the same colours, run after run.
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// The two colours of an album without art: a hue picked by the album + artist.
(Color, Color) noCoverColors(String seed) {
  final h = stableHash(seed.toLowerCase());
  final hue = (h % 360).toDouble();
  final shift = 20.0 + (h >> 9) % 30;
  return (HSLColor.fromAHSL(1, hue, 0.42, 0.36).toColor(), HSLColor.fromAHSL(1, (hue + shift) % 360, 0.5, 0.13).toColor());
}

/// "Velvet Static" -> "VS", "Deep Water (Remastered)" -> "DW", "1989" -> "19".
String initialsOf(String name) {
  final words = name
      .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ')
      .split(RegExp(r'[\s\-_/·:,.&+]+'))
      .where((w) => w.isNotEmpty && !const {'the', 'a', 'an', 'of'}.contains(w.toLowerCase()))
      .toList();
  if (words.isEmpty) return name.trim().isEmpty ? '♪' : name.trim().characters.first.toUpperCase();
  if (words.length == 1) return words.first.characters.take(2).toString().toUpperCase();
  return (words[0].characters.first + words[1].characters.first).toUpperCase();
}

/// Cover art from the thumbnail cache, or a tinted gradient with the album's
/// initials when the file has none (most real files).
class CoverArt extends StatelessWidget {
  const CoverArt(this.path, {super.key, this.size, this.radius = R.cover, this.round = false, this.seed, this.label});
  CoverArt.track(Track t, {super.key, this.size, this.radius = R.cover, this.round = false})
    : path = t.cover,
      seed = '${t.album.isEmpty ? t.title : t.album}\u0000${t.albumArtist}',
      label = t.album.isEmpty ? t.title : t.album;
  CoverArt.album(Album a, {super.key, this.size, this.radius = R.cover, this.round = false})
    : path = a.cover,
      seed = '${a.title}\u0000${a.artist}',
      label = a.title.isEmpty ? a.first.title : a.title;
  final String? path;
  final double? size;
  final double radius;
  final bool round;

  /// What picks the colours (album + artist) and the initials (album title).
  final String? seed, label;

  @override
  Widget build(BuildContext context) {
    final r = round ? BorderRadius.circular(R.pill) : BorderRadius.circular(radius);
    final placeholder = NoCover(seed: seed, label: label, radius: r, round: round);
    final px = ((size ?? 320) * MediaQuery.devicePixelRatioOf(context)).round();
    final child = path == null
        ? placeholder
        : ClipRRect(
            borderRadius: r,
            child: Image.file(
              File(path!),
              fit: BoxFit.cover,
              cacheWidth: px,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => placeholder,
              frameBuilder: (_, child, frame, sync) =>
                  sync ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: Motion.normal, child: child),
            ),
          );
    return SizedBox(
      width: size,
      height: size,
      child: AspectRatio(aspectRatio: 1, child: child),
    );
  }
}

class NoCover extends StatelessWidget {
  const NoCover({super.key, this.seed, this.label, required this.radius, this.round = false});
  final String? seed, label;
  final BorderRadius radius;
  final bool round;
  @override
  Widget build(BuildContext context) {
    if (seed == null) {
      return DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, color: C.raised3),
        child: const Center(child: Icon(LucideIcons.music, color: C.faint, size: 18)),
      );
    }
    final (a, b) = noCoverColors(seed!);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 120.0;
        final text = Text(
          initialsOf(label ?? ''),
          maxLines: 1,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: w * (round ? 0.32 : 0.3),
            fontWeight: FontWeight.w600,
            letterSpacing: -w * 0.01,
            height: 1,
            color: Colors.white.withValues(alpha: 0.88),
          ),
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: RadialGradient(
                center: const Alignment(-0.7, -0.8),
                radius: 1.1,
                colors: [Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0)],
              ),
            ),
            child: round
                ? Center(child: text)
                : Padding(
                    padding: EdgeInsets.fromLTRB(w * 0.1, 0, w * 0.08, w * 0.08),
                    child: Align(alignment: Alignment.bottomLeft, child: text),
                  ),
          ),
        );
      },
    );
  }
}

/// Blurred cover colour behind a hero, the lyrics or Now Playing. Without art
/// it glows with the album's gradient colours.
class CoverGlow extends StatelessWidget {
  const CoverGlow(this.path, {super.key, this.opacity = 0.55, this.seed, this.blur = 70});
  final String? path, seed;
  final double opacity, blur;
  @override
  Widget build(BuildContext context) {
    final Widget art;
    if (path != null) {
      art = Image.file(File(path!), fit: BoxFit.cover, cacheWidth: 64, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox());
    } else if (seed != null) {
      final (a, b) = noCoverColors(seed!);
      art = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [a, b, a.withValues(alpha: 0.6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.decal),
          child: Opacity(opacity: opacity, child: art),
        ),
      ),
    );
  }
}

/// "FLAC 24/96". Neutral: the coral is kept for what is playing now.
class FormatBadge extends StatelessWidget {
  const FormatBadge(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final hiRes = RegExp(r' (24|32)/').hasMatch(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x1 + 2, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R.tiny),
        border: Border.all(color: C.borderStrong),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: T.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: hiRes ? C.text : C.faint,
          letterSpacing: 0.2,
          fontFeatures: T.tabular,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action, this.extra});
  final IconData icon;
  final String title, body;
  final Widget? action, extra;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(S.x6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: C.raised2,
                borderRadius: BorderRadius.circular(R.card),
                border: Border.all(color: C.border),
              ),
              child: Icon(icon, color: C.dim, size: 24),
            ),
            const SizedBox(height: S.x4),
            Text(title, style: T.heading, textAlign: TextAlign.center),
            const SizedBox(height: S.x2),
            Text(body, style: T.small, textAlign: TextAlign.center),
            if (extra != null) ...[const SizedBox(height: S.x5), extra!],
            if (action != null) ...[const SizedBox(height: S.x5), action!],
          ],
        ),
      ),
    ),
  );
}

/// Page title + subtitle, Wora style. The trailing buttons drop below the title when narrow.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x2, S.x5),
    child: LayoutBuilder(
      builder: (context, c) {
        final head = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: T.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle != null) ...[
              const SizedBox(height: S.x1),
              Text(subtitle!, style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ],
        );
        if (trailing == null) return head;
        if (c.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              head,
              const SizedBox(height: S.x3),
              trailing!,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: head),
            const SizedBox(width: S.x4),
            trailing!,
          ],
        );
      },
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(S.x2, S.x6, S.x2, S.x3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: T.heading, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle != null) ...[
                const SizedBox(height: S.x1 / 2),
                Text(subtitle!, style: T.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Small animated bars shown on the playing row.
class PlayingBars extends StatefulWidget {
  const PlayingBars({super.key, required this.playing, this.color = C.accent});
  final bool playing;
  final Color color;
  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(PlayingBars old) {
    super.didUpdateWidget(old);
    widget.playing ? _c.repeat() : _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.playing ? 'Playing' : 'Paused',
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final phase in [0.0, 0.35, 0.7])
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 3,
              height: 4 + 10 * (widget.playing ? (0.5 + 0.5 * _wave((_c.value + phase) % 1)) : 0.3),
              decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
            ),
        ],
      ),
    ),
  );
  double _wave(double t) => (t < 0.5 ? t * 2 : 2 - t * 2) * 2 - 1;
}

/// A simple confirm/prompt dialog for names.
Future<String?> askText(BuildContext context, String title, {String initial = '', String action = 'Save'}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: c,
          autofocus: true,
          style: T.body,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
        ),
      ),
      actions: [
        PillButton('Cancel', onTap: () => Navigator.pop(ctx)),
        PillButton(action, primary: true, onTap: () => Navigator.pop(ctx, c.text.trim().isEmpty ? null : c.text.trim())),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String body, {String action = 'Delete'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body, style: T.small),
        actions: [
          PillButton('Cancel', onTap: () => Navigator.pop(ctx, false)),
          PillButton(action, primary: true, onTap: () => Navigator.pop(ctx, true)),
        ],
      ),
    ) ??
    false;

/// The app's messenger, so toasts can come from anywhere (engine errors too).
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// A short message above the player bar (never over it), with optional actions
/// such as "Show queue" or "Undo".
/// [action] + [onAction] is the single-action form the playback track uses.
void toast(BuildContext? context, String text, {String? action, VoidCallback? onAction, List<(String, VoidCallback)> actions = const []}) {
  if (action != null) actions = [(action, onAction ?? () {}), ...actions];
  final m = messengerKey.currentState ?? (context == null ? null : ScaffoldMessenger.maybeOf(context));
  if (m == null) return;
  final media = MediaQuery.of(m.context);
  final width = media.size.width;
  final scale = media.textScaler.scale(1);
  final side = ((width - 480) / 2).clamp(S.x4, double.infinity);
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: Duration(seconds: actions.isEmpty ? 2 : 5),
        margin: EdgeInsets.fromLTRB(side, 0, side, 136 + (scale - 1) * 48),
        padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x2, S.x2),
        content: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x2),
                child: Text(text, style: T.label, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ),
            for (final (label, onTap) in actions) ...[
              const SizedBox(width: S.x1),
              Clickable(
                onTap: () {
                  m.hideCurrentSnackBar();
                  onTap();
                },
                radius: R.pill,
                hover: C.borderStrong,
                padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
                child: Text(label, style: T.label.copyWith(color: C.accent)),
              ),
            ],
          ],
        ),
      ),
    );
}

/// A toast from code with no widget at hand (e.g. a playback error).
void notify(String text) => toast(null, text);

/// True when a text field has keyboard focus (so global keys stay out of the way).
bool get typing => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;

bool get ctrl => HardwareKeyboard.instance.isControlPressed;
bool get shift => HardwareKeyboard.instance.isShiftPressed;

/// A grid of cards that are as tall as they are wide plus [extra] (square cover + text).
Widget sliverCards({required int count, required IndexedWidgetBuilder builder, double maxWidth = 220, double extra = 82}) =>
    SliverLayoutBuilder(
      builder: (context, c) {
        final w = c.crossAxisExtent;
        final cols = ((w + S.x4) / (maxWidth + S.x4)).ceil().clamp(1, 99);
        final itemW = (w - S.x4 * (cols - 1)) / cols;
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisExtent: itemW + extra,
            crossAxisSpacing: S.x4,
            mainAxisSpacing: S.x4,
          ),
          itemCount: count,
          itemBuilder: builder,
        );
      },
    );
