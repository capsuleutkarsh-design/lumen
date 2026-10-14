import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../audio/sound.dart';
import '../../platform/android.dart';
import '../../platform/log.dart' show openPath;
import '../app.dart';
import '../theme.dart';
import '../widgets.dart';

const autoEqResults = 'https://github.com/jaakkopasanen/AutoEq/tree/master/results';

/// Output, equalizer, headphones and loudness, under a signal path that always shows what really happens.
class SoundPage extends StatelessWidget {
  const SoundPage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([sound, engine]),
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader('Sound', subtitle: 'How your music reaches your ears'),
        if (!Platform.isAndroid) ...[const _Narrow(child: SignalPathPanel()), const SizedBox(height: S.x4)],
        Expanded(
          child: ListView(
            key: const PageStorageKey('sound'),
            padding: EdgeInsets.zero,
            // Not const: the sections read [sound] and [engine], so they rebuild with this builder.
            children: [
              if (Platform.isAndroid) ...[const SignalPathPanel(), const SizedBox(height: S.x4)], // scrolls with the page
              _Narrow(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [_Output(), _Equalizer(), _Headphones(), _Loudness()],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Narrow extends StatelessWidget {
  const _Narrow({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 880), child: child),
  );
}

Widget _card(String title, String? subtitle, List<Widget> children, {Widget? trailing}) => Padding(
  padding: const EdgeInsets.only(bottom: S.x4),
  child: Panel(
    padding: const EdgeInsets.all(S.x5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: T.heading)),
            ?trailing,
          ],
        ),
        if (subtitle != null) ...[const SizedBox(height: S.x1), Text(subtitle, style: T.small)],
        const SizedBox(height: S.x4),
        ...children,
      ],
    ),
  ),
);

/// A setting with a title, a plain explanation and a switch.
Widget _switchRow(String title, String body, bool value, ValueChanged<bool> onChanged, {String? tag}) => Padding(
  padding: const EdgeInsets.only(bottom: S.x4),
  child: Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: S.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [Text(title, style: T.label), if (tag != null) _Tag(tag)],
            ),
            const SizedBox(height: 2),
            Text(body, style: T.small),
          ],
        ),
      ),
      const SizedBox(width: S.x4),
      Switch(value: value, onChanged: onChanged),
    ],
  ),
);

Widget _labelled(String label, Widget child, {String? caption}) => Padding(
  padding: const EdgeInsets.only(bottom: S.x4),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: T.label),
      const SizedBox(height: S.x2),
      child,
      if (caption != null) ...[const SizedBox(height: S.x2), Text(caption, style: T.caption)],
    ],
  ),
);

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(R.tiny),
      border: Border.all(color: C.borderStrong),
    ),
    child: Text(text, style: T.caption.copyWith(color: C.dim, fontWeight: FontWeight.w600)),
  );
}

/// One-of-a-few choice, as a row of pills.
class Choice<V> extends StatelessWidget {
  const Choice(this.values, this.label, this.selected, this.onChanged, {super.key});
  final List<V> values;
  final String Function(V) label;
  final V selected;
  final ValueChanged<V> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(S.x1 / 2),
    decoration: BoxDecoration(
      color: C.raised2,
      borderRadius: BorderRadius.circular(R.pill),
      border: Border.all(color: C.border),
    ),
    child: Wrap(
      children: [
        for (final v in values)
          Clickable(
            onTap: () => onChanged(v),
            selected: v == selected,
            selectedColor: C.raised3,
            hover: C.raised3,
            radius: R.pill,
            semanticLabel: label(v),
            padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x1 + 2),
            child: Text(label(v), style: T.label.copyWith(color: v == selected ? C.text : C.dim)),
          ),
      ],
    ),
  );
}

String _db(double v) => '${v > 0 ? '+' : v < 0 ? '−' : ''}${v.abs().toStringAsFixed(1)}';

// ------------------------------------------------------------ signal path

/// What really happens to the sound, and whether it is verified bit-perfect.
class SignalPathPanel extends StatelessWidget {
  const SignalPathPanel({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([sound, engine]),
    builder: (context, _) {
      final x = sound.path;
      final perfect = x.why.isEmpty;
      return Panel(
        padding: const EdgeInsets.all(S.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Signal path', style: T.heading)),
                if (perfect)
                  Container(
                    key: const ValueKey('bitperfect'),
                    padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x1),
                    decoration: BoxDecoration(
                      color: C.accentSoft,
                      borderRadius: BorderRadius.circular(R.pill),
                      border: Border.all(color: C.accent),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.check, size: 14, color: C.accent),
                        const SizedBox(width: S.x1),
                        Text('Bit-perfect', style: T.label.copyWith(color: C.accent)),
                      ],
                    ),
                  )
                else
                  const _Tag('Not bit-perfect'),
              ],
            ),
            const SizedBox(height: S.x3),
            Wrap(
              spacing: S.x2,
              runSpacing: S.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < x.steps.length; i++) ...[
                  if (i > 0) Icon(LucideIcons.arrowRight, size: 14, color: C.faint),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: S.x2 + 2, vertical: S.x1),
                    decoration: BoxDecoration(
                      color: C.raised2,
                      borderRadius: BorderRadius.circular(R.small),
                      border: Border.all(color: C.border),
                    ),
                    child: Text(x.steps[i], style: T.label.copyWith(fontFeatures: T.tabular)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: S.x3),
            Text(
              perfect
                  ? 'Every sample of the file reaches the device unchanged.'
                  : 'Not bit-perfect because ${x.why.join(', ')}.',
              style: T.small,
            ),
          ],
        ),
      );
    },
  );
}

// ------------------------------------------------------------ output

class _Output extends StatelessWidget {
  const _Output();
  @override
  Widget build(BuildContext context) {
    final s = sound.s;
    if (Platform.isAndroid) return _androidOutput(s);
    return _card('Output', null, [
      _labelled(
        'Output device',
        Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x3),
          decoration: BoxDecoration(
            color: C.raised2,
            borderRadius: BorderRadius.circular(R.small + 2),
            border: Border.all(color: C.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: engine.devices.any((d) => d.name == engine.device) ? engine.device : null,
              hint: Text(engine.device == 'auto' ? 'System default' : engine.device, style: T.label),
              isExpanded: true,
              dropdownColor: C.raised2,
              borderRadius: BorderRadius.circular(R.small + 2),
              style: T.label,
              icon: Icon(LucideIcons.chevronDown, size: 16, color: C.dim),
              items: [
                for (final d in engine.devices)
                  DropdownMenuItem(
                    value: d.name,
                    child: Text(d.name == 'auto' ? 'System default' : d.description, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => v == null ? null : engine.setDevice(v),
            ),
          ),
        ),
      ),
      _switchRow(
        'Exclusive mode',
        'Lumen takes the device for itself and sends the file\'s samples unchanged, at their own rate. '
            'Other apps go quiet while it plays. Needed for bit-perfect sound.',
        engine.exclusive,
        engine.setExclusive,
      ),
      _switchRow(
        'Best quality on this device',
        'Converts to the rate your device runs at with the best resampler (soxr, highest quality), so Windows never does a rough '
            'conversion. Works in 32-bit float, adds fine dither when the device takes whole numbers, lowers the level just enough '
            'for EQ boosts, and a gentle limiter stops peaks just below full scale so nothing ever crackles on cheap speakers.',
        s.bestQuality,
        (v) => sound.change((s) => s.bestQuality = v),
      ),
      _labelled(
        'Upsampling',
        Choice(
          Upsample.values,
          (u) => const ['Off', '88.2 / 96 kHz', '176.4 / 192 kHz', 'Device maximum'][u.index],
          s.upsample,
          (u) => sound.change((s) => s.upsample = u),
        ),
        caption: engine.exclusive
            ? 'Sends a higher rate to your DAC, converted with soxr. 44.1 kHz music goes to 88.2 or 176.4 kHz (an exact multiple), 48 kHz music to 96 or 192 kHz.'
            : 'Works in Exclusive mode. In Shared mode Windows fixes the rate, and Best quality already converts to it with soxr.',
      ),
      _labelled(
        'Buffer',
        Choice([false, true], (b) => b ? 'Large' : 'Normal', s.largeBuffer, (b) => sound.change((s) => s.largeBuffer = b)),
        caption: 'Choose Large if the sound drops out or crackles when the computer is busy.',
      ),
    ]);
  }
}

/// Android: where the sound goes (no device picker or exclusive mode there), Best quality and the buffer.
Widget _androidOutput(SoundSettings s) {
  final r = audioRoute.value;
  return _card('Output', null, [
    _labelled(
      'Playing on',
      Text(
        [
          r?.name ?? 'Phone speaker',
          if (r != null && r.product.isNotEmpty && r.kind != 'speaker') r.product,
          if (engine.outRate > 0) 'Lumen sends ${friendlyFormat(engine.outputFormat)}',
          if ((r?.nativeRate ?? 0) > 0) 'Android mixes at ${khz(r!.nativeRate)}',
        ].join(' · '),
        style: T.small,
      ),
    ),
    if (r != null && r.bluetooth)
      Container(
        key: const ValueKey('ldacTip'),
        margin: const EdgeInsets.only(bottom: S.x4),
        padding: const EdgeInsets.all(S.x4),
        decoration: BoxDecoration(
          color: C.raised2,
          borderRadius: BorderRadius.circular(R.small + 2),
          border: Border.all(color: C.border),
        ),
        child: Text(bluetoothTip, style: T.small),
      ),
    _switchRow(
      'Best quality on this device',
      'Converts to the rate Android plays at with the best resampler (soxr, highest quality), so Android never does a rough '
          'conversion. Works in 32-bit float, lowers the level just enough for EQ boosts, and a gentle limiter stops peaks '
          'just below full scale. Off, Lumen sends each song at its own rate (up to 96 kHz).',
      s.bestQuality,
      (v) => sound.change((s) => s.bestQuality = v),
    ),
    _labelled(
      'Buffer',
      Choice([false, true], (b) => b ? 'Large' : 'Normal', s.largeBuffer, (b) => sound.change((s) => s.largeBuffer = b)),
      caption: 'Choose Large if the sound drops out or crackles when the phone is busy.',
    ),
  ]);
}

/// Shown while Bluetooth headphones play: apps can't choose the codec; the phone's developer options can.
const bluetoothTip =
    'For the best Bluetooth sound with LDAC: Settings → Developer options → Bluetooth audio codec: LDAC, '
    'sample rate 96 kHz, bits 24, LDAC playback quality: Optimized for audio quality (990 kbps). '
    'Bluetooth codecs (LDAC too) are lossy, so Bluetooth is never bit-perfect.';

// ------------------------------------------------------------ equalizer

const _isoLabels = ['31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];

class _Equalizer extends StatefulWidget {
  const _Equalizer();
  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer> {
  int _selected = 0;

  /// A manual edit: the EQ turns on and is no longer the named preset.
  void _edit(void Function(Eq eq) f) => sound.change((s) {
    f(s.eq);
    s.eq
      ..on = true
      ..name = 'Custom';
  });

  @override
  Widget build(BuildContext context) {
    final s = sound.s, eq = s.eq;
    final fs = (sound.source.rate > 0 ? sound.source.rate : 48000).toDouble();
    final room = s.bestQuality ? headroomDb(eq, fs) : 0.0;
    return _card(
      'Equalizer',
      null,
      trailing: Switch(value: eq.on, onChanged: (v) => sound.change((s) => s.eq.on = v)),
      [
        Wrap(
          spacing: S.x3,
          runSpacing: S.x3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Choice([false, true], (a) => a ? 'Advanced' : 'Graphic', eq.advanced, (a) => sound.change((s) => s.eq.advanced = a)),
            Builder(
              builder: (b) => PillButton(
                'Preset: ${eq.name}',
                icon: LucideIcons.chevronDown,
                dense: true,
                onTap: () => _presetMenu(b),
              ),
            ),
            PillButton(
              'Reset',
              icon: LucideIcons.rotateCcw,
              dense: true,
              onTap: () => sound.change((s) => s.eq = Eq(on: s.eq.on, advanced: s.eq.advanced)),
            ),
          ],
        ),
        const SizedBox(height: S.x4),
        AnimatedOpacity(
          duration: Motion.normal,
          opacity: eq.on ? 1 : 0.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EqCurve(
                eq,
                fs: fs,
                selected: eq.advanced ? _selected : null,
                onSelect: (i) => setState(() => _selected = i),
                onDrag: eq.advanced
                    ? (i, f, g) => _edit((eq) {
                        eq.bands[i].freq = f;
                        if (hasGain(eq.bands[i].type)) eq.bands[i].gain = g;
                      })
                    : null,
                onQ: eq.advanced ? (i, q) => _edit((eq) => eq.bands[i].q = q) : null,
              ),
              const SizedBox(height: S.x2),
              Text(
                [
                  if (eq.on && room > 0) 'Automatic headroom ${_db(-room)} dB so boosts can\'t clip',
                  if (s.bestQuality || eq.limit) 'limiter at −0.3 dBFS',
                  if (eq.advanced) 'drag the points, scroll over one to change its width',
                ].join(' · '),
                style: T.caption,
              ),
              const SizedBox(height: S.x4),
              eq.advanced ? _advanced(eq) : _graphic(eq),
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        if (!Platform.isAndroid) // Android has no device picker to switch with
        _switchRow(
          'Remember the EQ for each output device',
          'Each device keeps its own EQ, and Lumen switches when you change device: your headphones\' correction only on the headphones.',
          s.perDevice,
          (v) => sound.change((s) {
            s.perDevice = v;
            if (!v) s.deviceEq.clear();
          }),
        ),
      ],
    );
  }

  Widget _graphic(Eq eq) {
    Widget column(String label, double value, ValueChanged<double> onChanged, {bool strong = false}) => Expanded(
      child: Column(
        children: [
          Text(_db(value), style: T.caption.copyWith(color: value == 0 ? C.faint : C.text, fontFeatures: T.tabular)),
          SizedBox(
            height: 150,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(activeTrackColor: C.raised3, inactiveTrackColor: C.raised3),
                child: Semantics(
                  label: '$label Hz',
                  child: Slider(value: value.clamp(-12, 12), min: -12, max: 12, onChanged: (v) => onChanged((v * 2).round() / 2)),
                ),
              ),
            ),
          ),
          Text(label, style: T.caption.copyWith(color: strong ? C.text : C.faint)),
        ],
      ),
    );
    return Row(
      children: [
        column('Pre', eq.preamp, (v) => _edit((eq) => eq.preamp = v), strong: true),
        Container(width: 1, height: 150, color: C.border),
        for (var i = 0; i < 10; i++) column(_isoLabels[i], eq.graphic[i], (v) => _edit((eq) => eq.graphic[i] = v)),
      ],
    );
  }

  Widget _advanced(Eq eq) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < eq.bands.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: S.x2),
          child: Container(
            padding: const EdgeInsets.fromLTRB(S.x3, S.x1, S.x1, S.x1),
            decoration: BoxDecoration(
              color: i == _selected ? C.raised3 : C.raised2,
              borderRadius: BorderRadius.circular(R.small + 2),
              border: Border.all(color: i == _selected ? C.borderStrong : C.border),
            ),
            child: Row(
              children: [
                SizedBox(width: 24, child: Text('${i + 1}', style: T.caption)),
                SizedBox(
                  width: 120,
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<BandType>(
                      value: eq.bands[i].type,
                      isExpanded: true,
                      dropdownColor: C.raised2,
                      style: T.label,
                      icon: Icon(LucideIcons.chevronDown, size: 14, color: C.dim),
                      items: [for (final t in BandType.values) DropdownMenuItem(value: t, child: Text(bandTypeNames[t]!))],
                      onChanged: (t) => t == null ? null : _edit((eq) => eq.bands[i].type = t),
                    ),
                  ),
                ),
                const SizedBox(width: S.x3),
                NumField(eq.bands[i].freq, 'Hz', 10, 24000, (v) => _edit((eq) => eq.bands[i].freq = v)),
                const SizedBox(width: S.x2),
                NumField(
                  eq.bands[i].gain,
                  'dB',
                  -24,
                  24,
                  (v) => _edit((eq) => eq.bands[i].gain = v),
                  enabled: hasGain(eq.bands[i].type),
                ),
                const SizedBox(width: S.x2),
                NumField(eq.bands[i].q, 'Q', 0.1, 20, (v) => _edit((eq) => eq.bands[i].q = v), digits: 2),
                const Spacer(),
                IconBtn(
                  LucideIcons.trash2,
                  size: 14,
                  box: 32,
                  tooltip: 'Remove band',
                  onTap: () => _edit((eq) => eq.bands.removeAt(i)),
                ),
              ],
            ),
          ),
        ),
      if (eq.bands.isEmpty && eq.curve.isEmpty) Text('No bands yet. Add one, pick a preset, or import a headphone correction.', style: T.small),
      if (eq.curve.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: S.x2),
          child: Row(
            children: [
              Expanded(child: Text('Imported curve: ${eq.curve.length} points (GraphicEQ)', style: T.small)),
              PillButton('Remove curve', dense: true, onTap: () => _edit((eq) => eq.curve.clear())),
            ],
          ),
        ),
      const SizedBox(height: S.x2),
      Row(
        children: [
          PillButton(
            'Add band',
            icon: LucideIcons.plus,
            dense: true,
            onTap: eq.bands.length >= maxBands
                ? null
                : () {
                    _edit((eq) => eq.bands.add(Band(BandType.peak, 1000, 0, 1.0)));
                    setState(() => _selected = eq.bands.length - 1);
                  },
          ),
          const SizedBox(width: S.x4),
          Text('Preamp', style: T.label),
          const SizedBox(width: S.x2),
          NumField(eq.preamp, 'dB', -24, 12, (v) => _edit((eq) => eq.preamp = v)),
        ],
      ),
    ],
  );

  Future<void> _presetMenu(BuildContext b) async {
    final box = b.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset(0, box.size.height + S.x1));
    final s = sound.s;
    final mine = s.presets.indexWhere((p) => p.name == s.eq.name);
    PopupMenuItem<String> item(String v, String label, {IconData? icon}) => PopupMenuItem(
      value: v,
      height: 34,
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 15, color: C.dim), const SizedBox(width: S.x2)],
          Flexible(child: Text(label, style: T.label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
      items: [
        for (var i = 0; i < builtInPresets.length; i++) item('b$i', builtInPresets[i].name),
        if (s.presets.isNotEmpty) ...[
          const PopupMenuDivider(height: 8),
          for (var i = 0; i < s.presets.length; i++) item('u$i', s.presets[i].name, icon: LucideIcons.user),
        ],
        const PopupMenuDivider(height: 8),
        item('save', 'Save as preset…', icon: LucideIcons.save),
        if (mine >= 0) ...[
          item('rename', 'Rename “${s.eq.name}”…', icon: LucideIcons.pencil),
          item('delete', 'Delete “${s.eq.name}”', icon: LucideIcons.trash2),
        ],
        const PopupMenuDivider(height: 8),
        item('autoeq', 'Headphone correction (AutoEQ)…', icon: LucideIcons.headphones),
        item('import', 'Import presets (JSON)…', icon: LucideIcons.import),
        if (s.presets.isNotEmpty && !Platform.isAndroid) item('export', 'Export my presets (JSON)…', icon: LucideIcons.share),
      ],
    );
    if (v == null || !mounted) return;
    if (v.startsWith('b') || v.startsWith('u')) {
      final p = (v[0] == 'b' ? builtInPresets : s.presets)[int.parse(v.substring(1))];
      return sound.change((s) => s.eq = p.copy()..on = true);
    }
    switch (v) {
      case 'save':
        final name = await askText(context, 'Save preset', initial: s.eq.name == 'Custom' ? '' : s.eq.name);
        if (name == null) return;
        sound.change((s) {
          s.eq.name = name;
          s.presets
            ..removeWhere((p) => p.name == name)
            ..add(s.eq.copy());
        });
      case 'rename':
        final name = await askText(context, 'Rename preset', initial: s.eq.name);
        if (name == null) return;
        sound.change((s) {
          s.presets[mine].name = name;
          s.eq.name = name;
        });
      case 'delete':
        if (await confirm(context, 'Delete “${s.eq.name}”?', 'The preset is removed. The EQ keeps its current settings.')) {
          sound.change((s) => s.presets.removeAt(mine));
        }
      case 'autoeq':
        await showDialog<void>(context: context, builder: (_) => const AutoEqDialog());
      case 'import':
        final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'Lumen EQ presets', extensions: ['json'])]);
        if (f == null) return;
        try {
          final got = importPresets(await f.readAsString());
          sound.change((s) {
            for (final p in got) {
              s.presets
                ..removeWhere((x) => x.name == p.name)
                ..add(p..on = true);
            }
          });
          notify('Imported ${plural(got.length, 'preset')}');
        } catch (_) {
          notify('That file has no Lumen EQ presets');
        }
      case 'export':
        final to = await getSaveLocation(
          suggestedName: 'Lumen EQ presets.json',
          acceptedTypeGroups: const [XTypeGroup(label: 'JSON', extensions: ['json'])],
        );
        if (to == null) return;
        File(to.path).writeAsStringSync(exportPresets(s.presets));
        notify('Saved ${plural(s.presets.length, 'preset')}');
    }
  }
}

/// A number you can type: applied on Enter or when the field loses focus, clamped to [min]..[max].
class NumField extends StatefulWidget {
  const NumField(this.value, this.unit, this.min, this.max, this.onChanged, {super.key, this.digits = 1, this.enabled = true});
  final double value, min, max;
  final String unit;
  final int digits;
  final bool enabled;
  final ValueChanged<double> onChanged;
  @override
  State<NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<NumField> {
  late final _c = TextEditingController(text: _text);
  final _focus = FocusNode();
  String get _text => widget.unit == 'Hz' ? widget.value.round().toString() : widget.value.toStringAsFixed(widget.digits);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit(_c.text);
    });
  }

  @override
  void didUpdateWidget(NumField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _c.text != _text) _c.text = _text;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String t) {
    final v = double.tryParse(t.replaceAll('−', '-').replaceAll(',', '.').trim());
    if (v == null) {
      _c.text = _text;
      return;
    }
    final x = v.clamp(widget.min, widget.max).toDouble();
    if (x != widget.value) widget.onChanged(x);
    _c.text = widget.unit == 'Hz' ? x.round().toString() : x.toStringAsFixed(widget.digits);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.unit == 'Hz' ? 96 : 84,
    child: TextField(
      controller: _c,
      focusNode: _focus,
      enabled: widget.enabled,
      style: T.label.copyWith(fontFeatures: T.tabular, color: widget.enabled ? C.text : C.faint),
      decoration: InputDecoration(
        isDense: true,
        suffixText: widget.unit,
        suffixStyle: T.caption,
        contentPadding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x2),
      ),
      onSubmitted: _submit,
    ),
  );
}

/// The EQ's real frequency response (the same biquad maths FFmpeg runs), without the preamp. In Advanced
/// mode the bands are points you can drag; the scroll wheel over a point changes its width (Q).
class EqCurve extends StatefulWidget {
  const EqCurve(this.eq, {super.key, this.fs = 48000, this.height = 200, this.selected, this.onSelect, this.onDrag, this.onQ});
  final Eq eq;
  final double fs, height;
  final int? selected;
  final ValueChanged<int>? onSelect;
  final void Function(int band, double freq, double gain)? onDrag;
  final void Function(int band, double q)? onQ;
  @override
  State<EqCurve> createState() => _EqCurveState();
}

class _EqCurveState extends State<EqCurve> {
  int? _drag;
  static const range = 15.0;

  static double xOf(double f, double w) => log(f / 20) / log(1000) * w;
  static double fOf(double x, double w) => 20 * pow(1000, (x / w).clamp(0.0, 1.0)).toDouble();
  static double yOf(double db, double h) => h / 2 - db.clamp(-range, range) / range * h / 2;
  static double dbOf(double y, double h) => ((h / 2 - y) / (h / 2) * range).clamp(-12.0, 12.0);

  int? _hit(Offset p, Size size) {
    final bands = widget.eq.bands;
    int? best;
    var bestD = 24.0;
    for (var i = 0; i < bands.length; i++) {
      final b = bands[i];
      final c = Offset(xOf(b.freq, size.width), yOf(hasGain(b.type) ? b.gain : 0, size.height));
      final d = (c - p).distance;
      if (d < bestD) (best, bestD) = (i, d);
    }
    return best;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final size = Size(c.maxWidth, widget.height);
      final edit = widget.onDrag != null;
      void move(Offset p) {
        if (_drag == null) return;
        widget.onDrag!(_drag!, fOf(p.dx, size.width).roundToDouble(), (dbOf(p.dy, size.height) * 10).round() / 10);
      }

      return Listener(
        onPointerSignal: (e) {
          if (!edit || e is! PointerScrollEvent) return;
          final i = _hit(e.localPosition, size);
          if (i == null) return;
          final q = widget.eq.bands[i].q * (e.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1);
          widget.onQ?.call(i, (q.clamp(0.1, 20) * 100).round() / 100);
        },
        child: GestureDetector(
          onPanStart: edit
              ? (d) {
                  _drag = _hit(d.localPosition, size);
                  if (_drag != null) widget.onSelect?.call(_drag!);
                }
              : null,
          onPanUpdate: edit ? (d) => move(d.localPosition) : null,
          onPanEnd: edit ? (_) => _drag = null : null,
          onTapDown: edit
              ? (d) {
                  final i = _hit(d.localPosition, size);
                  if (i != null) widget.onSelect?.call(i);
                }
              : null,
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: C.raised2,
              borderRadius: BorderRadius.circular(R.small + 2),
              border: Border.all(color: C.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(R.small + 2),
              child: CustomPaint(size: size, painter: _CurvePainter(widget.eq, widget.fs, widget.selected)),
            ),
          ),
        ),
      );
    },
  );
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.eq, this.fs, this.selected) : json = eq.toJson().toString();
  final palette = C.palette; // repaint when the theme switches
  final Eq eq;
  final double fs;
  final int? selected;
  final String json;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final grid = Paint()
      ..color = C.border
      ..strokeWidth = 1;
    final label = TextPainter(textDirection: TextDirection.ltr);
    void text(String s, Offset at) {
      label
        ..text = TextSpan(text: s, style: T.caption.copyWith(fontSize: 10))
        ..layout();
      label.paint(canvas, at);
    }

    for (final db in [-12.0, -6.0, 0.0, 6.0, 12.0]) {
      final y = _EqCurveState.yOf(db, h);
      canvas.drawLine(Offset(0, y), Offset(w, y), grid..color = db == 0 ? C.borderStrong : C.border);
      text('${db > 0 ? '+' : ''}${db.round()}', Offset(4, y - 13));
    }
    for (final (f, s) in [(100.0, '100'), (1000.0, '1k'), (10000.0, '10k')]) {
      final x = _EqCurveState.xOf(f, w);
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid..color = C.border);
      text(s, Offset(x + 3, h - 14));
    }
    final pts = [
      for (final f in freqGrid(220))
        // The bands' shape: the preamp is its own value, so the points sit on the curve.
        if (f < fs / 2) Offset(_EqCurveState.xOf(f, w), _EqCurveState.yOf(eqDb(eq, f, fs) - eq.preamp, h)),
    ];
    if (pts.isEmpty) return;
    final line = Path()..addPolygon(pts, false);
    final fill = Path.from(line)
      ..lineTo(pts.last.dx, h / 2)
      ..lineTo(pts.first.dx, h / 2)
      ..close();
    final on = eq.on;
    canvas.drawPath(fill, Paint()..color = on ? C.accentSoft : C.text.withValues(alpha: 0.08));
    canvas.drawPath(
      line,
      Paint()
        ..color = on ? C.accent : C.dim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    if (!eq.advanced) return;
    for (var i = 0; i < eq.bands.length; i++) {
      final b = eq.bands[i];
      final c = Offset(_EqCurveState.xOf(b.freq, w), _EqCurveState.yOf(hasGain(b.type) ? b.gain : 0, h));
      final sel = i == selected;
      canvas.drawCircle(c, sel ? 8 : 6, Paint()..color = sel ? C.text : C.raised3);
      canvas.drawCircle(
        c,
        sel ? 8 : 6,
        Paint()
          ..color = sel ? C.accent : C.text
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      text('${i + 1}', c + const Offset(9, -18));
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.json != json || old.fs != fs || old.selected != selected || old.palette != palette;
}

/// Headphone correction: paste or open an AutoEQ / Equalizer APO file.
class AutoEqDialog extends StatefulWidget {
  const AutoEqDialog({super.key, this.initial = ''});
  final String initial;
  @override
  State<AutoEqDialog> createState() => _AutoEqDialogState();
}

class _AutoEqDialogState extends State<AutoEqDialog> {
  late final _text = TextEditingController(text: widget.initial)..addListener(_parse);
  final _name = TextEditingController(text: 'Headphones');
  (Eq, int)? _got;
  String? _error;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    super.dispose();
  }

  void _parse() => setState(() {
    _got = null;
    _error = null;
    if (_text.text.trim().isEmpty) return;
    try {
      _got = parseEqText(_text.text);
    } on FormatException catch (e) {
      _error = e.message;
    }
  });

  Future<void> _open() async {
    final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: 'EQ text', extensions: ['txt'])]);
    if (f != null) _text.text = await f.readAsString();
  }

  void _import() {
    final name = _name.text.trim().isEmpty ? 'Headphones' : _name.text.trim();
    final eq = _got!.$1..name = name;
    sound.change((s) {
      s.eq = eq.copy();
      s.presets
        ..removeWhere((p) => p.name == name)
        ..add(eq.copy());
    });
    Navigator.pop(context);
    notify("Using '$name' — saved in your presets");
  }

  @override
  Widget build(BuildContext context) {
    final got = _got;
    return AlertDialog(
      title: const Text('Headphone correction'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The AutoEQ project has measured thousands of headphones and made a correction EQ for each, '
                'so they sound neutral, the way the music was mixed. To use yours:',
                style: T.small,
              ),
              const SizedBox(height: S.x2),
              for (final step in const [
                '1.  Open the AutoEQ results page and press Ctrl + F to find your headphone model (for example “WH-1000XM5”).',
                '2.  Open your model\'s folder, then the file whose name ends in “ParametricEQ.txt”.',
                '3.  Copy all of its text and paste it here, or download the file and press Open file.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: S.x1),
                  child: Text(step, style: T.small.copyWith(color: C.text)),
                ),
              const SizedBox(height: S.x3),
              Wrap(
                spacing: S.x3,
                runSpacing: S.x2,
                children: [
                  PillButton('Open AutoEQ results', icon: LucideIcons.externalLink, dense: true, onTap: () => openPath(autoEqResults)),
                  PillButton('Open file…', icon: LucideIcons.fileText, dense: true, onTap: _open),
                ],
              ),
              const SizedBox(height: S.x4),
              TextField(
                controller: _text,
                minLines: 5,
                maxLines: 8,
                style: T.small.copyWith(color: C.text, fontFamily: 'Consolas'),
                decoration: const InputDecoration(hintText: 'Preamp: -6.2 dB\nFilter 1: ON PK Fc 105 Hz Gain -2.3 dB Q 0.70\n…'),
              ),
              const SizedBox(height: S.x3),
              Row(
                children: [
                  Text('Name', style: T.label),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      style: T.body,
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x3),
              if (_error != null) Text(_error!, style: T.small.copyWith(color: C.accent)),
              if (got != null) ...[
                Text(
                  [
                    if (got.$1.bands.isNotEmpty) plural(got.$1.bands.length, 'filter'),
                    if (got.$1.curve.isNotEmpty) '${got.$1.curve.length}-point curve',
                    'preamp ${_db(got.$1.preamp)} dB',
                    if (got.$2 > 0) '${plural(got.$2, 'line')} not understood (skipped)',
                  ].join(' · '),
                  style: T.small,
                ),
                const SizedBox(height: S.x2),
                EqCurve(got.$1, height: 130),
              ],
              const SizedBox(height: S.x3),
              Text(
                'Equalizer APO files and AutoEQ\'s GraphicEQ.txt work too. Lumen downloads nothing: the link opens your browser.',
                style: T.caption,
              ),
            ],
          ),
        ),
      ),
      actions: [
        PillButton('Cancel', onTap: () => Navigator.pop(context)),
        PillButton('Use this correction', primary: true, onTap: got == null ? null : _import),
      ],
    );
  }
}

// ------------------------------------------------------------ headphones and loudness

class _Headphones extends StatelessWidget {
  const _Headphones();
  @override
  Widget build(BuildContext context) => _card('Headphones', null, [
    _labelled(
      'Crossfeed',
      Choice(
        Crossfeed.values,
        (c) => const ['Off', 'Light', 'Medium', 'Strong'][c.index],
        sound.s.crossfeed,
        (c) => sound.change((s) => s.crossfeed = c),
      ),
      caption: 'Mixes a little of each side into the other, as speakers do, so music on headphones feels less “inside your head”.',
    ),
  ]);
}

class _Loudness extends StatelessWidget {
  const _Loudness();
  @override
  Widget build(BuildContext context) {
    final s = sound.s;
    final src = sound.source;
    final gain = rgGainDb(s, src);
    return _card('Loudness', null, [
      _labelled(
        'ReplayGain',
        Choice(
          ReplayGain.values,
          (r) => const ['Off', 'Track', 'Album', 'Auto'][r.index],
          s.replayGain,
          (r) => sound.change((s) => s.replayGain = r),
        ),
        caption:
            'Evens out the loudness between songs, using the ReplayGain tags in your files. Album keeps the level changes '
            'inside an album; Auto uses album gain when you play an album in order and track gain when you shuffle.'
            '${engine.current == null || s.replayGain == ReplayGain.off ? '' : gain == null ? '\nThis song has no ReplayGain tags.' : '\nThis song: ${_db(gain)} dB.'}',
      ),
      if (s.replayGain != ReplayGain.off) ...[
        _labelled(
          'Pre-amp  ${_db(s.rgPreamp)} dB',
          SizedBox(
            width: 360,
            child: Slider(
              value: s.rgPreamp,
              min: -12,
              max: 12,
              onChanged: (v) => sound.change((s) => s.rgPreamp = (v * 2).round() / 2),
            ),
          ),
        ),
        _switchRow(
          'Prevent clipping',
          'Lowers the gain of a song when raising it would push its peaks past full scale.',
          s.rgClip,
          (v) => sound.change((s) => s.rgClip = v),
        ),
      ],
      _switchRow(
        'Volume levelling for files without ReplayGain',
        'Gently evens out loudness on songs that have no ReplayGain tags. It changes the sound, so it is off by default.',
        s.levelling,
        (v) => sound.change((s) => s.levelling = v),
        tag: 'Not bit-perfect',
      ),
    ]);
  }
}
