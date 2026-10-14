import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

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

/// Hover / pressed / focus / disabled states for anything clickable.
class Clickable extends StatefulWidget {
  const Clickable({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapDown,
    this.radius = R.small,
    this.hover = C.raised2,
    this.pressed = C.raised3,
    this.selected = false,
    this.padding = EdgeInsets.zero,
    this.tooltip,
    this.cursor = SystemMouseCursors.click,
  });
  final Widget child;
  final VoidCallback? onTap, onDoubleTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final double radius;
  final Color hover, pressed;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final String? tooltip;
  final MouseCursor cursor;
  @override
  State<Clickable> createState() => _ClickableState();
}

class _ClickableState extends State<Clickable> {
  bool _hover = false, _down = false, _focus = false;
  bool get _enabled => widget.onTap != null || widget.onDoubleTap != null;

  @override
  Widget build(BuildContext context) {
    final bg = !_enabled
        ? Colors.transparent
        : _down
        ? widget.pressed
        : (_hover || widget.selected)
        ? widget.hover
        : Colors.transparent;
    Widget w = FocusableActionDetector(
      enabled: _enabled,
      mouseCursor: _enabled ? widget.cursor : MouseCursor.defer,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap?.call())},
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
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: _focus ? C.accent : Colors.transparent, width: 1.5),
          ),
          child: Opacity(opacity: _enabled || widget.onSecondaryTapDown != null ? 1 : 0.35, child: widget.child),
        ),
      ),
    );
    if (widget.tooltip != null) w = Tooltip(message: widget.tooltip!, child: w);
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
    radius: R.pill,
    child: SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: size, color: active ? C.accent : color),
          if (active)
            Positioned(
              bottom: 3,
              child: Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(color: C.accent, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Pill button. One primary per view; the rest are secondary.
class PillButton extends StatelessWidget {
  const PillButton(this.label, {super.key, this.icon, this.onTap, this.primary = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.black : C.text;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: primary ? C.text : Colors.transparent,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: primary ? C.text : C.borderStrong),
      ),
      child: Clickable(
        onTap: onTap,
        radius: R.pill,
        hover: primary ? const Color(0x1A000000) : C.raised2,
        pressed: primary ? const Color(0x33000000) : C.raised3,
        padding: const EdgeInsets.symmetric(horizontal: S.x5, vertical: S.x2 + 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: S.x2)],
            Text(label, style: T.label.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// Cover art from the thumbnail cache, or a quiet placeholder.
class CoverArt extends StatelessWidget {
  const CoverArt(this.path, {super.key, this.size, this.radius = R.cover, this.round = false});
  final String? path;
  final double? size;
  final double radius;
  final bool round;
  @override
  Widget build(BuildContext context) {
    final r = round ? BorderRadius.circular(R.pill) : BorderRadius.circular(radius);
    final placeholder = Container(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: const LinearGradient(colors: [C.raised3, C.raised2], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      child: Icon(LucideIcons.music, color: C.faint, size: (size ?? 120) * 0.3),
    );
    final px = ((size ?? 300) * MediaQuery.devicePixelRatioOf(context)).round();
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

/// Blurred cover colour behind a hero or the lyrics view.
class CoverGlow extends StatelessWidget {
  const CoverGlow(this.path, {super.key, this.opacity = 0.55});
  final String? path;
  final double opacity;
  @override
  Widget build(BuildContext context) {
    if (path == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70, tileMode: TileMode.decal),
          child: Opacity(
            opacity: opacity,
            child: Image.file(
              File(path!),
              fit: BoxFit.cover,
              cacheWidth: 64,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox(),
            ),
          ),
        ),
      ),
    );
  }
}

class FormatBadge extends StatelessWidget {
  const FormatBadge(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final hiRes = RegExp(r' (24|32)/').hasMatch(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R.small - 3),
        border: Border.all(color: hiRes ? C.accent.withValues(alpha: 0.5) : C.borderStrong),
      ),
      child: Text(
        text,
        style: T.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: hiRes ? C.accent : C.dim,
          letterSpacing: 0.2,
          fontFeatures: T.tabular,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title, body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
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
          if (action != null) ...[const SizedBox(height: S.x5), action!],
        ],
      ),
    ),
  );
}

/// Page title + subtitle, Wora style.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x2, S.x4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: T.display),
              if (subtitle != null) ...[const SizedBox(height: S.x1), Text(subtitle!, style: T.small)],
            ],
          ),
        ),
        ?trailing,
      ],
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
              Text(title, style: T.title),
              if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: T.small)],
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
  Widget build(BuildContext context) => AnimatedBuilder(
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

void toast(BuildContext context, String text, {String? action, VoidCallback? onAction}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        width: 360,
        duration: Duration(seconds: action == null ? 2 : 4),
        action: action == null ? null : SnackBarAction(label: action, onPressed: onAction ?? () {}),
      ),
    );
}

/// True when a text field has keyboard focus (so global keys stay out of the way).
bool get typing => FocusManager.instance.primaryFocus?.context?.widget is EditableText;

bool get ctrl => HardwareKeyboard.instance.isControlPressed;

/// A grid of cards that are as tall as they are wide plus [extra] (square cover + text).
Widget sliverCards({required int count, required IndexedWidgetBuilder builder, double maxWidth = 220, double extra = 82}) =>
    SliverLayoutBuilder(
      builder: (context, c) {
        final w = c.crossAxisExtent;
        final cols = ((w + S.x2) / (maxWidth + S.x2)).ceil().clamp(1, 99);
        final itemW = (w - S.x2 * (cols - 1)) / cols;
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisExtent: itemW + extra,
            crossAxisSpacing: S.x2,
            mainAxisSpacing: S.x2,
          ),
          itemCount: count,
          itemBuilder: builder,
        );
      },
    );
