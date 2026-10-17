import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverConstraints, SliverGridLayout;
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../art/art_cache.dart';
import '../art/art_sources.dart';
import '../library/models.dart';
import '../platform/window.dart' show isTouch;
import 'app.dart';
import 'phone.dart' show phoneLayout;
import 'theme.dart';
import 'tracks.dart' show selection;

String fmtTime(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

String fmtLong(Duration d) {
  final m = d.inMinutes;
  if (m == 0 && d > Duration.zero) return 'under 1 min';
  return m >= 60 ? '${m ~/ 60} h ${m % 60} min' : '$m min';
}

/// The words for a touch screen or a mouse ("Tap" / "Double-click", "long-press" / "right-click").
String get tapWord => isTouch ? 'Tap' : 'Double-click';
String get menuWord => isTouch ? 'long-press' : 'right-click';

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
  const Panel({super.key, required this.child, this.radius = R.panel, this.padding = EdgeInsets.zero, this.color});
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? color; // C.raised1
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? C.raised1,
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
    this.hover,
    this.pressed,
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
  final Color? hover, pressed; // C.raised2, C.raised3
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
        ? widget.pressed ?? C.raised3
        : widget.selected
        ? (widget.selectedColor ?? widget.hover ?? C.raised2)
        : _hover
        ? widget.hover ?? C.raised2
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
          // Touch: a tap does what a double-click does (play), a long press opens the right-click menu.
          onTap: isTouch ? widget.onDoubleTap ?? widget.onTap : widget.onTap,
          onDoubleTap: isTouch ? null : widget.onDoubleTap,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          onLongPressStart: isTouch && widget.onSecondaryTapDown != null
              ? (d) {
                  HapticFeedback.selectionClick();
                  widget.onSecondaryTapDown!(TapDownDetails(globalPosition: d.globalPosition));
                }
              : null,
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
    // Touch: no keyboard, so no "(Space)" hints (TalkBack reads tooltips).
    final tip = isTouch ? widget.tooltip?.split('  ').first : widget.tooltip;
    if (tip != null) w = Tooltip(message: tip, excludeFromSemantics: widget.semanticLabel != null, child: w);
    return w;
  }
}

/// A star rating, 0-5. With [onRate] the stars can be clicked (hovering shows what a click gives;
/// clicking the current rating clears it). Ratings live in the database only.
class Stars extends StatefulWidget {
  const Stars(this.rating, {super.key, this.onRate, this.size = 14});
  final int rating;
  final ValueChanged<int>? onRate;
  final double size;
  @override
  State<Stars> createState() => _StarsState();
}

class _StarsState extends State<Stars> {
  int? _hover;
  @override
  Widget build(BuildContext context) {
    final shown = _hover ?? widget.rating;
    final rate = widget.onRate;
    return Semantics(
      label: '${widget.rating} of 5 stars',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            MouseRegion(
              cursor: rate == null ? MouseCursor.defer : SystemMouseCursors.click,
              onEnter: rate == null ? null : (_) => setState(() => _hover = i),
              onExit: rate == null ? null : (_) => setState(() => _hover = null),
              child: GestureDetector(
                onTap: rate == null ? null : () => rate(i == widget.rating ? 0 : i),
                child: Padding(
                  padding: EdgeInsets.all(isTouch && rate != null ? (48 - widget.size) / 2 : 1), // touch: 48 dp targets
                  child: Icon(i <= shown ? Icons.star_rounded : LucideIcons.star, size: widget.size, color: i <= shown ? C.accent : C.faint),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  const IconBtn(this.icon, {super.key, this.onTap, this.tooltip, this.size = 18, this.box = 36, this.color, this.active = false, this.activeColor});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size, box;
  final Color? color; // C.dim
  final bool active;

  /// The icon and dot while [active] (C.accent; white over cover art, where gold can vanish).
  final Color? activeColor;
  @override
  Widget build(BuildContext context) => Clickable(
    onTap: onTap,
    tooltip: tooltip,
    semanticLabel: tooltip?.split('  ').first,
    radius: R.pill,
    child: Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: SizedBox(
        width: isTouch ? max(box, 48) : box, // a finger needs 48 dp
        height: isTouch ? max(box, 48) : box,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: size, color: active ? activeColor ?? C.accent : color ?? C.dim),
            if (active)
              Positioned(
                bottom: S.x1 - 1,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(color: activeColor ?? C.accent, shape: BoxShape.circle),
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
          hover: primary ? C.veil(0.1) : C.raised2,
          pressed: primary ? C.veil(0.2) : C.raised3,
          padding: EdgeInsets.symmetric(horizontal: dense ? S.x3 : S.x5, vertical: dense ? S.x1 + 2 : S.x2 + 2),
          child: ConstrainedBox(
            // A finger needs 48 dp (the border adds 2).
            constraints: BoxConstraints(minHeight: isTouch ? 46 - (dense ? 12 : 20) : 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: S.x2)],
                Text(label, style: T.label.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ cover art

/// What to show for a cover that is not an album's (artists, empty playlists): [path] unless
/// it is low quality, else generated art seeded by [seed]. Null: nothing to show.
Art? resolveArt(String? path, {String? seed}) {
  if (path != null && !lib.lowCovers.contains(path)) return Art.file(path);
  return seed == null ? null : autoArt(seed, lib.artSourcesOn);
}

/// A song's album art as an image file: its cover, or the generated art (drawn first if needed).
/// The one place to get a cover as a file (the Windows media overlay, accent colours...).
Future<String?> coverFile(Track t, {double px = 384}) => ArtCache.ensure(lib.artFor(t.albumKey, t.cover), px);

/// An album's cover, or the art Gleo draws for it when it has none or only a low-quality one
/// (and whatever the user picked with Change cover).
class CoverArt extends StatelessWidget {
  CoverArt(String? path, {super.key, this.size, this.radius = R.cover, this.round = false, String? seed}) : art = resolveArt(path, seed: seed);
  CoverArt.track(Track t, {super.key, this.size, this.radius = R.cover, this.round = false}) : art = lib.artFor(t.albumKey, t.cover);
  CoverArt.album(Album a, {super.key, this.size, this.radius = R.cover, this.round = false}) : art = lib.artFor(a.key, a.cover);
  const CoverArt.art(this.art, {super.key, this.size, this.radius = R.cover, this.round = false});
  final Art? art;
  final double? size;
  final double radius;
  final bool round;

  /// What [CoverArt.track] shows for [t] at [px] pixels: the cover file, or the art Gleo draws
  /// (drawn when first read), plus a colour for when the image can't be read.
  /// The accent-from-art reads covers only through here.
  static (ImageProvider?, Color) source(Track t, int px) {
    final art = lib.artFor(t.albumKey, t.cover);
    return (art.file != null ? ResizeImage(FileImage(File(art.file!)), width: px) : GeneratedArtImage(art, px), C.raised3);
  }

  @override
  Widget build(BuildContext context) {
    final r = round ? BorderRadius.circular(R.pill) : BorderRadius.circular(radius);
    final child = art == null
        ? DecoratedBox(
            decoration: BoxDecoration(borderRadius: r, color: C.raised3),
            child: Center(child: Icon(LucideIcons.music, color: C.faint, size: 18)),
          )
        : ClipRRect(
            borderRadius: r,
            child: LayoutBuilder(builder: (context, c) => ArtImage(art!, px: (size ?? c.maxWidth) * MediaQuery.devicePixelRatioOf(context))),
          );
    return SizedBox(
      width: size,
      height: size,
      child: AspectRatio(
        aspectRatio: 1,
        // On the phone's light theme a white cover keeps its edge.
        child: isTouch && C.isLight
            ? DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: r,
                  border: Border.all(color: C.border),
                ),
                child: child,
              )
            : child,
      ),
    );
  }
}

/// Shows [art] at about [px] pixels: the cover file, or generated art once it is drawn
/// (a quiet placeholder until then; drawing never blocks a frame).
class ArtImage extends StatefulWidget {
  const ArtImage(this.art, {super.key, required this.px, this.fit = BoxFit.cover});
  final Art art;
  final double px;
  final BoxFit fit;
  @override
  State<ArtImage> createState() => _ArtImageState();
}

class _ArtImageState extends State<ArtImage> {
  String? _file;
  ArtJob? _job;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ArtImage old) {
    super.didUpdateWidget(old);
    if (old.art != widget.art || ArtCache.bucket(old.px) != ArtCache.bucket(widget.px)) _resolve(sameArt: old.art == widget.art);
  }

  /// Until generated art is drawn at this size, another size of it is shown if drawn. Else the
  /// previous image stays only if it is this same art (a resize); new art starts on the plain
  /// tile, never on the previous album's cover.
  void _resolve({bool sameArt = false}) {
    _job?.release();
    _job = null;
    final ready = ArtCache.file(widget.art, widget.px);
    if (ready != null || ArtCache.dir == null) {
      _file = ready;
      return;
    }
    _file = [for (final s in ArtCache.sizes) ?ArtCache.file(widget.art, s.toDouble())].lastOrNull ?? (sameArt ? _file : null);
    final job = _job = ArtCache.want(widget.art, widget.px);
    job.done.then((f) {
      if (mounted && _job == job) setState(() => _file = f);
    });
  }

  @override
  void dispose() {
    _job?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: C.raised3, child: const SizedBox.expand());
    if (_file == null) return placeholder;
    // On the placeholder colour, so a fading-in image never shows what is behind it.
    return ColoredBox(
      color: C.raised3,
      child: Image.file(
        File(_file!),
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: widget.px.round(),
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
        frameBuilder: (_, child, frame, sync) =>
            sync ? child : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: Motion.normal, child: child),
      ),
    );
  }
}

/// Blurred cover colours behind a hero, the lyrics or Now Playing. The blur is drawn once
/// into a small image (per art and size) and stretched, so a spinning disc on top never
/// makes the GPU blur the whole window again on every frame.
class CoverGlow extends StatelessWidget {
  const CoverGlow(this.art, {super.key, this.opacity = 0.55, this.blur = 70});
  final Art? art;
  final double opacity, blur;
  @override
  Widget build(BuildContext context) {
    if (art == null) return const SizedBox.shrink();
    return Positioned.fill(child: LayoutBuilder(builder: (context, c) => _Glow(art!, c.biggest, opacity, blur)));
  }
}

class _Glow extends StatefulWidget {
  const _Glow(this.art, this.size, this.opacity, this.blur);
  final Art art;
  final Size size;
  final double opacity, blur;
  @override
  State<_Glow> createState() => _GlowState();
}

class _GlowState extends State<_Glow> {
  ui.Image? _image;
  Object? _key;

  @override
  void initState() {
    super.initState();
    _bake();
  }

  @override
  void didUpdateWidget(_Glow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bake();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _bake() async {
    final w = widget.size.width, h = widget.size.height;
    if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) return;
    // Same art, same look, about the same size (32 px steps): keep the image.
    final key = (widget.art, widget.opacity, widget.blur, (w / 32).round(), (h / 32).round());
    if (key == _key) return;
    _key = key;
    try {
      final file = await ArtCache.ensure(widget.art, 64);
      if (file == null) return;
      final codec = await ui.instantiateImageCodec(await File(file).readAsBytes(), targetWidth: 64, targetHeight: 64);
      final art = (await codec.getNextFrame()).image;
      codec.dispose();
      final k = 96 / max(w, h); // a 96 px image is plenty for a blur this soft
      final out = Size((w * k).ceilToDouble(), (h * k).ceilToDouble());
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final s = max(out.width, out.height); // cover-fit the square art
      c.saveLayer(
        Offset.zero & out,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: widget.blur * k, sigmaY: widget.blur * k, tileMode: TileMode.decal)
          ..color = Color.fromRGBO(0, 0, 0, widget.opacity),
      );
      c.drawImageRect(art, const Offset(0, 0) & const Size(64, 64), Rect.fromCenter(center: out.center(Offset.zero), width: s, height: s), Paint());
      c.restore();
      final pic = rec.endRecording();
      final image = await pic.toImage(out.width.toInt(), out.height.toInt());
      pic.dispose();
      art.dispose();
      if (!mounted || key != _key) return image.dispose();
      final old = _image;
      setState(() => _image = image);
      old?.dispose();
    } catch (_) {} // no glow
  }

  @override
  Widget build(BuildContext context) =>
      RawImage(image: _image, width: widget.size.width, height: widget.size.height, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
}

/// What lies under a full-window cover (Now Playing, Disc mode, the phone's queue): its animations pause,
/// and once the cover has faded in it is not drawn at all (the GPU drew it under the cover on every
/// frame while the disc turned). It shows again at once when the cover goes.
class Covered extends StatefulWidget {
  const Covered({super.key, required this.covered, required this.child});
  final bool covered;
  final Widget child;
  @override
  State<Covered> createState() => _CoveredState();
}

class _CoveredState extends State<Covered> {
  bool _hidden = false;
  Timer? _hide;

  @override
  void didUpdateWidget(Covered old) {
    super.didUpdateWidget(old);
    if (widget.covered == old.covered) return;
    _hide?.cancel();
    _hidden = false;
    if (widget.covered) _hide = Timer(Motion.slow, () => mounted ? setState(() => _hidden = true) : null);
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Visibility(
    visible: !(_hidden && widget.covered),
    // Keeps its size (a Stack may size itself by it), state, animations and keyboard focus: only the drawing stops.
    maintainSize: true,
    maintainAnimation: true,
    maintainState: true,
    maintainFocusability: true,
    child: TickerMode(enabled: !widget.covered, child: widget.child),
  );
}

/// "FLAC 24/96". Neutral: the gold is kept for what is playing now.
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
        style: T.caption.copyWith(fontWeight: FontWeight.w600, color: hiRes ? C.text : C.faint, letterSpacing: 0.2, fontFeatures: T.tabular),
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

/// A page subtitle, or null when it would say nothing: a count of nothing ("0 songs · 0 min")
/// is left to the empty state below.
String? shownSubtitle(String? s) => s == null || s.isEmpty || s.startsWith('0 ') ? null : s;

/// Page title + subtitle, Wora style. The trailing buttons drop below the title when narrow.
class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final subtitle = shownSubtitle(this.subtitle);
    // A phone on its side has little height: the title as a top bar, its count beside it.
    if (phoneLayout(context) && MediaQuery.orientationOf(context) == Orientation.landscape) {
      return SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: S.x2),
            Flexible(
              child: Text(title, style: T.heading, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: S.x3),
              Flexible(
                child: Text(subtitle, style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
            const Spacer(),
            ?trailing,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x2, S.x5),
      child: LayoutBuilder(
        builder: (context, c) {
          final head = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: T.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle != null) ...[const SizedBox(height: S.x1), Text(subtitle, style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis)],
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
  const PlayingBars({super.key, required this.playing, this.color});
  final bool playing;
  final Color? color; // C.accent
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

  // Painted, not rebuilt, on each frame: a row that changes size every frame laid out the song's row
  // (and Now Playing's queue) again 60 times a second.
  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.playing ? 'Playing' : 'Paused',
    child: CustomPaint(size: const Size(15, 14), painter: _Bars(_c, widget.playing, widget.color ?? C.accent, _wave)),
  );
  double _wave(double t) => (t < 0.5 ? t * 2 : 2 - t * 2) * 2 - 1;
}

/// [PlayingBars]: three 3 px bars 2 px apart, bottoms level, as a centred row of them was.
class _Bars extends CustomPainter {
  _Bars(this.c, this.playing, this.color, this.wave) : super(repaint: c);
  final Animation<double> c;
  final bool playing;
  final Color color;
  final double Function(double) wave;

  @override
  void paint(Canvas canvas, Size size) {
    final hs = [for (final phase in [0.0, 0.35, 0.7]) 4 + 10 * (playing ? (0.5 + 0.5 * wave((c.value + phase) % 1)) : 0.3)];
    final bottom = size.height / 2 + hs.reduce(max) / 2;
    final paint = Paint()..color = color;
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(1 + i * 5.0, bottom - hs[i], 3, hs[i]), const Radius.circular(2)), paint);
    }
  }

  @override
  bool shouldRepaint(_Bars old) => old.playing != playing || old.color != color;
}

/// A simple confirm/prompt dialog for names.
Future<String?> askText(BuildContext context, String title, {String initial = '', String action = 'Save', String? hint}) {
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
          decoration: InputDecoration(hintText: hint),
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
void toast(
  BuildContext? context,
  String text, {
  String? action,
  VoidCallback? onAction,
  List<(String, VoidCallback)> actions = const [],
  int? seconds,
}) {
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
        duration: Duration(seconds: seconds ?? (actions.isEmpty ? 2 : 5)),
        // Above the player bar, and above the selection bar while that shows.
        margin: EdgeInsets.fromLTRB(side, 0, side, 136 + (scale - 1) * 48 + (selection.length > 1 ? 64 : 0)),
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
    SliverGrid.builder(gridDelegate: _CardGrid(maxWidth, extra), itemCount: count, itemBuilder: builder);

/// [sliverCards]' columns, worked out from the width at layout. (A SliverLayoutBuilder did this before
/// and rebuilt every card on every scrolled frame: its constraints carry the scroll offset.)
class _CardGrid extends SliverGridDelegate {
  const _CardGrid(this.maxWidth, this.extra);
  final double maxWidth, extra;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final w = constraints.crossAxisExtent;
    final cols = ((w + S.x4) / (maxWidth + S.x4)).ceil().clamp(1, 99);
    final itemW = (w - S.x4 * (cols - 1)) / cols;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: cols,
      mainAxisExtent: itemW + extra,
      crossAxisSpacing: S.x4,
      mainAxisSpacing: S.x4,
    ).getLayout(constraints);
  }

  @override
  bool shouldRelayout(_CardGrid old) => old.maxWidth != maxWidth || old.extra != extra;
}
