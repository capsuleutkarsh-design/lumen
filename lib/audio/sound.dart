// The Sound page's model, maths and filter-chain builder. Pure Dart (no Flutter,
// no mpv), so all of it is unit tested: test/sound_test.dart.
import 'dart:convert';
import 'dart:math';

// ------------------------------------------------------------ settings

enum BandType { peak, lowShelf, highShelf, lowPass, highPass, notch }

const bandTypeNames = {
  BandType.peak: 'Peak',
  BandType.lowShelf: 'Low shelf',
  BandType.highShelf: 'High shelf',
  BandType.lowPass: 'Low-pass',
  BandType.highPass: 'High-pass',
  BandType.notch: 'Notch',
};

/// Low-pass, high-pass and notch have no gain.
bool hasGain(BandType t) => t == BandType.peak || t == BandType.lowShelf || t == BandType.highShelf;

class Band {
  Band(this.type, this.freq, [this.gain = 0, this.q = 0.71]);
  BandType type;
  double freq, gain, q;

  Map<String, Object> toJson() => {'type': type.name, 'f': freq, 'g': gain, 'q': q};
  factory Band.fromJson(Map<String, Object?> j) => Band(
    BandType.values.byName(j['type'] as String? ?? 'peak'),
    (j['f'] as num? ?? 1000).toDouble(),
    (j['g'] as num? ?? 0).toDouble(),
    (j['q'] as num? ?? 0.71).toDouble(),
  );
}

/// The 10-band ISO graphic EQ: one octave apart, so Q = 1.41 (one octave wide).
const isoFreqs = [31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0];
const graphicQ = 1.41;
const maxBands = 10;

/// One equalizer setting (also what a preset is).
class Eq {
  Eq({
    this.name = 'Flat',
    this.on = false,
    this.advanced = false,
    List<double>? graphic,
    List<Band>? bands,
    List<(double, double)>? curve,
    this.preamp = 0,
    this.night = false,
    this.limit = false,
  }) : graphic = graphic ?? List.filled(10, 0.0),
       bands = bands ?? [],
       curve = curve ?? [];

  String name;
  bool on;

  /// false: the 10 graphic sliders apply; true: the parametric [bands] (+ an imported [curve]).
  bool advanced;
  List<double> graphic;
  List<Band> bands;

  /// An imported GraphicEQ curve: (Hz, dB) points, played through firequalizer.
  List<(double, double)> curve;
  double preamp;

  /// Late night: a gentle compressor. [limit]: the limiter even with Best quality off.
  bool night, limit;

  /// The biquads that play: the graphic sliders, or the parametric bands.
  List<Band> get active => advanced ? bands : [for (var i = 0; i < 10; i++) Band(BandType.peak, isoFreqs[i], graphic[i], graphicQ)];

  Map<String, Object> toJson() => {
    'name': name,
    'on': on,
    'advanced': advanced,
    'graphic': graphic,
    'bands': [for (final b in bands) b.toJson()],
    if (curve.isNotEmpty) 'curve': [for (final (f, g) in curve) [f, g]],
    'preamp': preamp,
    if (night) 'night': true,
    if (limit) 'limit': true,
  };

  factory Eq.fromJson(Map<String, Object?> j) => Eq(
    name: j['name'] as String? ?? 'Custom',
    on: j['on'] as bool? ?? false,
    advanced: j['advanced'] as bool? ?? false,
    graphic: [for (var i = 0; i < 10; i++) ((j['graphic'] as List?)?.elementAtOrNull(i) as num? ?? 0).toDouble()],
    bands: [for (final b in j['bands'] as List? ?? const []) Band.fromJson((b as Map).cast())],
    curve: [for (final p in j['curve'] as List? ?? const []) (((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())],
    preamp: (j['preamp'] as num? ?? 0).toDouble(),
    night: j['night'] as bool? ?? false,
    limit: j['limit'] as bool? ?? false,
  );

  Eq copy() => Eq.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, Object?>);
}

enum Crossfeed { off, light, medium, strong }

enum ReplayGain { off, track, album, auto }

/// Upsampling (Exclusive mode): to 2× or 4× the source family (44.1 → 88.2 / 176.4), or the device's highest rate.
enum Upsample { off, x2, x4, max }

class SoundSettings {
  /// soxr resampling, TPDF dither, automatic headroom and the -0.3 dBFS limiter.
  bool bestQuality = true;
  Upsample upsample = Upsample.off;
  bool largeBuffer = false;
  Eq eq = Eq();
  Crossfeed crossfeed = Crossfeed.off;
  ReplayGain replayGain = ReplayGain.off;
  double rgPreamp = 0;
  bool rgClip = true;

  /// dynaudnorm for files without ReplayGain tags.
  bool levelling = false;

  /// Remember the EQ per output device (mpv device id -> EQ).
  bool perDevice = false;
  Map<String, Eq> deviceEq = {};
  List<Eq> presets = [];

  Map<String, Object> toJson() => {
    'bestQuality': bestQuality,
    'upsample': upsample.name,
    'largeBuffer': largeBuffer,
    'eq': eq.toJson(),
    'crossfeed': crossfeed.name,
    'replayGain': replayGain.name,
    'rgPreamp': rgPreamp,
    'rgClip': rgClip,
    'levelling': levelling,
    'perDevice': perDevice,
    'deviceEq': {for (final e in deviceEq.entries) e.key: e.value.toJson()},
    'presets': [for (final p in presets) p.toJson()],
  };

  /// Unknown or broken JSON gives the defaults; missing keys keep theirs.
  static SoundSettings parse(String? json) {
    final s = SoundSettings();
    if (json == null) return s;
    try {
      final j = jsonDecode(json) as Map<String, Object?>;
      T pick<T extends Enum>(List<T> all, Object? v, T d) => all.where((e) => e.name == v).firstOrNull ?? d;
      s
        ..bestQuality = j['bestQuality'] as bool? ?? true
        ..upsample = pick(Upsample.values, j['upsample'], Upsample.off)
        ..largeBuffer = j['largeBuffer'] as bool? ?? false
        ..eq = j['eq'] == null ? Eq() : Eq.fromJson((j['eq'] as Map).cast())
        ..crossfeed = pick(Crossfeed.values, j['crossfeed'], Crossfeed.off)
        ..replayGain = pick(ReplayGain.values, j['replayGain'], ReplayGain.off)
        ..rgPreamp = (j['rgPreamp'] as num? ?? 0).toDouble()
        ..rgClip = j['rgClip'] as bool? ?? true
        ..levelling = j['levelling'] as bool? ?? false
        ..perDevice = j['perDevice'] as bool? ?? false
        ..deviceEq = {for (final e in (j['deviceEq'] as Map? ?? {}).entries) e.key as String: Eq.fromJson((e.value as Map).cast())}
        ..presets = [for (final p in j['presets'] as List? ?? const []) Eq.fromJson((p as Map).cast())];
    } catch (_) {}
    return s;
  }
}

// ------------------------------------------------------------ presets

Eq _g(String name, List<double> g, {bool night = false, bool limit = false}) =>
    Eq(name: name, on: true, graphic: g, night: night, limit: limit);

/// Built-in presets (dB at 31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz).
final builtInPresets = <Eq>[
  _g('Flat', [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  _g('Bass boost', [6, 5, 4, 2, 0.5, 0, 0, 0, 0, 0]),
  _g('Bass reducer', [-6, -5, -4, -2, -0.5, 0, 0, 0, 0, 0]),
  _g('Treble boost', [0, 0, 0, 0, 0, 0.5, 2, 4, 5, 6]),
  _g('Vocal', [-2, -2, -1, 0, 1.5, 3, 3.5, 2, 0, -1]),
  _g('Rock', [4, 3, 2, 0, -1, -1, 0.5, 2, 3, 4]),
  _g('Pop', [-1, 0, 1.5, 3, 3.5, 2.5, 1, 0, 0, -0.5]),
  _g('Jazz', [3, 2, 1, 1.5, -1, -1, 0, 1, 2, 3]),
  _g('Classical', [3, 2, 1, 0, 0, 0, 0, 1, 2, 2.5]),
  _g('Electronic', [5, 4, 1.5, 0, -1.5, 0.5, 0, 1, 3.5, 4.5]),
  _g('Hip-hop', [5, 4.5, 2, 2.5, -1, -1, 0.5, 0, 1, 2]),
  _g('Acoustic', [2.5, 2, 1, 0.5, 1.5, 1.5, 2.5, 3, 2, 1]),
  _g('Piano', [1.5, 1, 0, 1.5, 2.5, 1, 2.5, 3.5, 2, 1.5]),
  _g('Podcast / Spoken', [-6, -4, -2, 0, 1.5, 3, 4, 3, 1, -2]),
  _g('Loudness', [6, 4, 2, 0, 0, 0, 0, 1, 3, 4.5], limit: true),
  _g('Late night', [-2, -1, 0, 0, 0, 0, 0, 0, -1, -2], night: true, limit: true),
  Eq(
    name: 'Small speakers',
    on: true,
    advanced: true,
    limit: true,
    bands: [Band(BandType.highPass, 100, 0, 0.71), Band(BandType.peak, 2500, 2, 1.0), Band(BandType.peak, 200, -1.5, 1.0)],
  ),
];

// ------------------------------------------------------------ biquad maths

/// RBJ cookbook coefficients [b0, b1, b2, a0, a1, a2], computed as FFmpeg's
/// biquad filters do with width_type q (equalizer, lowshelf, highshelf, lowpass, highpass, bandreject).
List<double> biquad(Band b, double fs) {
  final w0 = 2 * pi * b.freq / fs, c = cos(w0), alpha = sin(w0) / (2 * b.q);
  final a = pow(10, b.gain / 40).toDouble(), sa = 2 * sqrt(a) * alpha;
  return switch (b.type) {
    BandType.peak => [1 + alpha * a, -2 * c, 1 - alpha * a, 1 + alpha / a, -2 * c, 1 - alpha / a],
    BandType.lowShelf => [
      a * ((a + 1) - (a - 1) * c + sa),
      2 * a * ((a - 1) - (a + 1) * c),
      a * ((a + 1) - (a - 1) * c - sa),
      (a + 1) + (a - 1) * c + sa,
      -2 * ((a - 1) + (a + 1) * c),
      (a + 1) + (a - 1) * c - sa,
    ],
    BandType.highShelf => [
      a * ((a + 1) + (a - 1) * c + sa),
      -2 * a * ((a - 1) + (a + 1) * c),
      a * ((a + 1) + (a - 1) * c - sa),
      (a + 1) - (a - 1) * c + sa,
      2 * ((a - 1) - (a + 1) * c),
      (a + 1) - (a - 1) * c - sa,
    ],
    BandType.lowPass => [(1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha],
    BandType.highPass => [(1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha],
    BandType.notch => [1, -2 * c, 1, 1 + alpha, -2 * c, 1 - alpha],
  };
}

/// |H(f)| in dB of one biquad at sample rate [fs].
double bandDb(Band b, double f, double fs) {
  final k = biquad(b, fs), w = 2 * pi * f / fs;
  double mag2(double x0, double x1, double x2) {
    final re = x0 + x1 * cos(w) + x2 * cos(2 * w), im = -x1 * sin(w) - x2 * sin(2 * w);
    return re * re + im * im;
  }

  return 10 * log(mag2(k[0], k[1], k[2]) / mag2(k[3], k[4], k[5]) + 1e-30) / ln10;
}

/// The imported GraphicEQ curve at [f]: linear between points (firequalizer's default), flat beyond the ends.
double curveDb(List<(double, double)> c, double f) {
  if (c.isEmpty) return 0;
  if (f <= c.first.$1) return c.first.$2;
  for (var i = 1; i < c.length; i++) {
    final (f1, g1) = c[i];
    if (f <= f1) {
      final (f0, g0) = c[i - 1];
      return g0 + (g1 - g0) * (f - f0) / (f1 - f0);
    }
  }
  return c.last.$2;
}

/// FFmpeg's expression parser takes about 100 `entry()` terms; AutoEQ's GraphicEQ has 127.
/// A longer curve is resampled to [maxPoints] log-spaced points (about 1/10 octave apart).
const maxPoints = 96;
List<(double, double)> curvePoints(List<(double, double)> c) {
  if (c.length <= maxPoints) return c;
  final lo = c.first.$1, hi = c.last.$1;
  final fs = [for (var i = 0; i < maxPoints; i++) (lo * pow(hi / lo, i / (maxPoints - 1)) * 10).round() / 10];
  return [for (final f in fs) (f, (curveDb(c, f) * 100).round() / 100)];
}

/// The whole EQ (preamp + bands + curve) at [f], in dB.
double eqDb(Eq eq, double f, double fs) {
  var db = eq.preamp;
  for (final b in playable(eq, fs)) {
    db += bandDb(b, f, fs);
  }
  if (eq.advanced) db += curveDb(eq.curve, f);
  return db;
}

/// FFmpeg can build this band at [fs] (one at or above Nyquist is left out).
bool plays(Band b, double fs) => b.freq > 0 && b.freq < fs * 0.49 && b.q > 0;

Iterable<Band> playable(Eq eq, double fs) => eq.active.where((b) => plays(b, fs));

/// Log-spaced points from 20 Hz to 20 kHz.
List<double> freqGrid([int n = 240]) => [for (var i = 0; i < n; i++) 20 * pow(1000, i / (n - 1)).toDouble()];

/// Automatic headroom: the EQ's highest boost (preamp included), so the result never exceeds 0 dB.
double headroomDb(Eq eq, double fs) {
  if (!eq.on) return 0;
  var top = 0.0;
  for (final f in [...freqGrid(), for (final b in eq.active) b.freq]) {
    if (f < fs / 2) top = max(top, eqDb(eq, f, fs));
  }
  return top;
}

// ------------------------------------------------------------ the filter chain

class DeviceInfo {
  const DeviceInfo({
    this.id = 'auto',
    this.name = 'System default',
    this.exclusive = false,
    this.volume = 100,
    this.muted = false,
    this.outFormat = '',
    this.outRate = 0,
    this.outChannels = 0,
    this.android = false,
    this.bluetooth = false,
    this.nativeRate = 0,
  });
  final String id, name, outFormat;
  final bool exclusive, muted;
  final double volume;
  final int outRate, outChannels;

  /// Android: its mixer always sits between Lumen and the device; Bluetooth adds a lossy codec.
  final bool android, bluetooth;

  /// Android: the rate the output runs at (0 = unknown).
  final int nativeRate;
}

class SourceInfo {
  const SourceInfo({this.badge = '', this.format = '', this.rate = 0, this.bits = 0, this.channels = 0, this.rg, this.albumInOrder = false});
  final String badge, format;
  final int rate, bits, channels;

  /// ReplayGain tags: (track gain, track peak, album gain, album peak); null when the file has none.
  final (double, double, double?, double?)? rg;

  /// The queue plays an album in order (not shuffled): ReplayGain Auto uses album gain.
  final bool albumInOrder;
}

const limiterDb = -0.3;
const limiter = 'alimiter@lim=limit=0.966051:level=0';

String _n(double v) => (v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')).replaceFirst(RegExp(r'^-0$'), '0');

/// One filter in FFmpeg's syntax; each has a fixed instance name so live changes can be sent as commands.
String _filter(Band b, int i, double fs) {
  final f = 'f=${_n(b.freq)}:t=q:w=${_n(b.q)}';
  // Lumen's engine has no bandreject: the notch is FFmpeg's generic biquad with the same RBJ coefficients.
  // ponytail: coefficients are for the song's rate; a gapless change of rate runs the old ones until apply() (milliseconds).
  final k = biquad(b, fs);
  return switch (b.type) {
    BandType.peak => 'equalizer@b$i=$f:g=${_n(b.gain)}',
    BandType.lowShelf => 'lowshelf@b$i=$f:g=${_n(b.gain)}',
    BandType.highShelf => 'highshelf@b$i=$f:g=${_n(b.gain)}',
    BandType.lowPass => 'lowpass@b$i=$f',
    BandType.highPass => 'highpass@b$i=$f',
    BandType.notch => 'biquad@b$i=b0=${k[0]}:b1=${k[1]}:b2=${k[2]}:a0=${k[3]}:a1=${k[4]}:a2=${k[5]}',
  };
}

/// The target rate for upsampling (0 = leave the rate alone). Integer multiples are preferred: 44.1 -> 88.2 / 176.4.
int upsampleRate(Upsample u, int src) {
  if (u == Upsample.off || src <= 0) return 0;
  final cd = src % 11025 == 0;
  final to = switch (u) {
    Upsample.x2 => cd ? 88200 : 96000,
    Upsample.x4 => cd ? 176400 : 192000,
    _ => cd ? 352800 : 384000, // mpv's WASAPI picks the highest rate the device takes when this one isn't
  };
  return to > src ? to : 0;
}

/// The rate Lumen sends on Android (0 = the song's own): Best quality converts to the output's own rate
/// with soxr; otherwise the song's rate up to 96 kHz (higher rates go to 88.2 / 96 kHz, the same family).
int androidRate(SoundSettings s, DeviceInfo d, int src) {
  if (s.bestQuality && d.nativeRate > 0) return d.nativeRate == src ? 0 : d.nativeRate;
  if (src <= 96000) return 0;
  return src % 11025 == 0 ? 88200 : 96000;
}

/// The ReplayGain mode mpv gets.
String rgMode(SoundSettings s, SourceInfo src) => switch (s.replayGain) {
  ReplayGain.off => 'no',
  ReplayGain.track => 'track',
  ReplayGain.album => 'album',
  ReplayGain.auto => src.albumInOrder ? 'album' : 'track',
};

/// The gain mpv applies (dB), as its replaygain code computes it; null when off or the file has no tags.
double? rgGainDb(SoundSettings s, SourceInfo src) {
  final rg = src.rg;
  final mode = rgMode(s, src);
  if (mode == 'no' || rg == null) return null;
  final album = mode == 'album' && rg.$3 != null;
  var g = (album ? rg.$3! : rg.$1) + s.rgPreamp;
  final peak = album ? (rg.$4 ?? rg.$2) : rg.$2;
  if (s.rgClip && peak > 0) g = min(g, -20 * log(peak) / ln10);
  return g;
}

/// Everything Lumen asks of mpv for these settings: a lavfi chain for `af` (empty = no
/// filters, the clean path) and mpv options. The one place the chain is built.
({String chain, Map<String, String> options}) buildAudioChain(SoundSettings s, DeviceInfo d, SourceInfo src) {
  final fs = (src.rate > 0 ? src.rate : 48000).toDouble();
  final f = <String>[];
  if (s.levelling && src.rg == null) f.add('dynaudnorm@lev=f=250:g=11:p=0.9:m=4');
  if (s.crossfeed != Crossfeed.off) {
    // bs2b's feed level: jmeier 9.5 dB (lightest), cmoy 6 dB, default 4.5 dB (strongest).
    f.add('bs2b@xf=profile=${const ['', 'jmeier', 'cmoy', 'default'][s.crossfeed.index]}');
  }
  final eq = s.eq;
  if (eq.on) {
    final pre = eq.preamp - (s.bestQuality ? headroomDb(eq, fs) : 0);
    f.add('volume@pre=volume=${_n(pre)}dB');
    final bands = eq.active;
    for (var i = 0; i < bands.length; i++) {
      if (plays(bands[i], fs)) f.add(_filter(bands[i], i, fs));
    }
    if (eq.advanced && eq.curve.isNotEmpty) {
      f.add("firequalizer@fir=gain_entry='${[for (final (hz, g) in curvePoints(eq.curve)) 'entry(${_n(hz)},${_n(g)})'].join(';')}'");
    }
    if (eq.night) f.add('acompressor@night=threshold=0.063:ratio=3:attack=10:release=250:makeup=2');
  }
  if (f.isNotEmpty && (s.bestQuality || (eq.on && eq.limit))) f.add(limiter);
  if (f.isNotEmpty) f.insert(0, 'aformat=sample_fmts=fltp'); // 32-bit float processing: a boost can't clip inside the chain
  final up = d.exclusive ? upsampleRate(s.upsample, src.rate) : (d.android ? androidRate(s, d, src.rate) : 0);
  return (
    chain: f.join(','),
    options: {
      // soxr at very high quality (28 bits), TPDF dither when the output is integer.
      'audio-swresample-o': s.bestQuality ? 'resampler=soxr,precision=28,dither_method=triangular' : '',
      'audio-samplerate': '$up',
      'audio-buffer': s.largeBuffer ? '1.0' : '0.2',
      'replaygain': rgMode(s, src),
      'replaygain-preamp': _n(s.rgPreamp),
      'replaygain-clip': s.rgClip ? 'yes' : 'no',
      'replaygain-fallback': '0',
    },
  );
}

/// The commands that turn the running chain [from] into [to] without rebuilding it
/// (no gap, no click), or null when the chain's shape changed. Only gain, frequency,
/// width and the preamp change this way: what slider drags and typing change.
List<List<String>>? liveCommands(String from, String to) {
  if (from.isEmpty || to.isEmpty) return null;
  Map<String, String> parse(String filter) {
    final eq = filter.indexOf('=');
    return {
      '': eq < 0 ? filter : filter.substring(0, eq),
      for (final kv in eq < 0 ? const <String>[] : filter.substring(eq + 1).split(':')) kv.split('=').first: kv.substring(kv.indexOf('=') + 1),
    };
  }

  final split = RegExp(r",(?=(?:[^']*'[^']*')*[^']*$)"); // commas outside quotes
  final a = from.split(split), b = to.split(split);
  if (a.length != b.length) return null;
  final out = <List<String>>[];
  for (var i = 0; i < a.length; i++) {
    final x = parse(a[i]), y = parse(b[i]);
    if (x[''] != y[''] || x.length != y.length) return null;
    for (final k in y.keys) {
      if (x[k] == y[k]) continue;
      if (!const {'f', 'w', 'g', 'volume'}.contains(k) || !x.containsKey(k)) return null;
      out.add([k, y[k]!, y['']!]);
    }
  }
  return out;
}

// ------------------------------------------------------------ the signal path

const _bits = {'u8': 8, 's16': 16, 's24': 24, 's32': 32, 's64': 64};

/// "s32" -> "32-bit", "floatp" -> "32-bit float".
String formatName(String f) {
  f = f.endsWith('p') ? f.substring(0, f.length - 1) : f;
  return switch (f) {
    'float' => '32-bit float',
    'double' => '64-bit float',
    _ => _bits[f] == null ? f : '${_bits[f]}-bit',
  };
}

/// "s32 96000 Hz" -> "32-bit · 96 kHz".
String friendlyFormat(String mpv) {
  final m = RegExp(r'^(\w+)\s+(\d+)').firstMatch(mpv);
  return m == null ? mpv : '${formatName(m[1]!)} · ${khz(int.parse(m[2]!))}';
}

/// 44100 -> "44.1 kHz".
String khz(int hz) {
  final k = hz / 1000;
  return '${k == k.roundToDouble() ? k.round() : k} kHz';
}

String _db(double v) => '${v > 0 ? '+' : v < 0 ? '−' : ''}${v.abs().toStringAsFixed(1)} dB';

/// The device gets every sample unchanged: same rate and channels, and the same
/// integer samples (an integer format at least as wide, padded with zeros, keeps them exact).
bool sameSamples(String src, int srcBits, String out) {
  String base(String f) => f.endsWith('p') ? f.substring(0, f.length - 1) : f;
  final a = base(src), b = base(out);
  if (a == b) return true;
  final ab = _bits[a], bb = _bits[b];
  return ab != null && bb != null && bb >= (srcBits > 0 ? min(srcBits, ab) : ab);
}

/// What really happens to the sound, step by step, and why it is not bit-perfect (empty = bit-perfect).
({List<String> steps, List<String> why}) signalPath(SoundSettings s, DeviceInfo d, SourceInfo src) {
  final chain = buildAudioChain(s, d, src).chain;
  final steps = <String>[if (src.badge.isNotEmpty) src.badge];
  final why = <String>[];
  if (chain.contains('dynaudnorm@')) steps.add('Levelling');
  if (chain.contains('bs2b@')) steps.add('Crossfeed (${s.crossfeed.name})');
  if (s.eq.on) {
    final n = s.eq.advanced ? s.eq.bands.length : s.eq.graphic.where((g) => g != 0).length;
    steps.add(s.eq.advanced && s.eq.curve.isNotEmpty ? 'EQ (curve${n > 0 ? ' + $n bands' : ''})' : 'EQ ($n band${n == 1 ? '' : 's'})');
  }
  if (chain.contains('acompressor@')) steps.add('Compressor');
  if (chain.contains('alimiter@')) steps.add('Limiter');
  final rg = rgGainDb(s, src);
  if (rg != null && rg != 0) steps.add('ReplayGain ${_db(rg)}');
  if (d.muted) {
    steps.add('Muted');
  } else if (d.volume < 100) {
    steps.add('Volume ${d.volume.round()} %');
  }
  final resampled = d.outRate > 0 && src.rate > 0 && d.outRate != src.rate;
  if (resampled) steps.add(s.bestQuality ? 'soxr' : 'resampler');
  if (d.outRate > 0) steps.add('${khz(d.outRate)} ${formatName(d.outFormat)}');
  if (d.android) steps.add(d.nativeRate > 0 ? 'Android mixer (${khz(d.nativeRate)})' : 'Android mixer');
  if (d.bluetooth) steps.add('Bluetooth codec');
  steps.add('${d.name}${d.exclusive ? ' (exclusive)' : ''}');

  if (d.outFormat.isEmpty || src.format.isEmpty) why.add('nothing is playing');
  if (d.android) {
    why.add('Android mixes the sound');
  } else if (!d.exclusive) {
    why.add('shared mode: Windows mixes the sound');
  }
  if (d.bluetooth) why.add('Bluetooth sends it through a lossy codec (LDAC, aptX, AAC or SBC)');
  if (d.muted) why.add('muted');
  if (!d.muted && d.volume < 100) why.add('volume is ${d.volume.round()} %, not 100 %');
  if (chain.contains('dynaudnorm@')) why.add('volume levelling is on');
  if (chain.contains('bs2b@')) why.add('crossfeed is on');
  if (s.eq.on) why.add('EQ is on');
  if (rg != null && rg != 0) why.add('ReplayGain changes the level by ${_db(rg)}');
  if (resampled) why.add('resampled ${khz(src.rate)} → ${khz(d.outRate)}');
  if (d.outFormat.isNotEmpty && src.format.isNotEmpty && !sameSamples(src.format, src.bits, d.outFormat)) {
    why.add('converted ${formatName(src.format)} → ${formatName(d.outFormat)}');
  }
  if (d.outChannels > 0 && src.channels > 0 && d.outChannels != src.channels) why.add('channels changed ${src.channels} → ${d.outChannels}');
  return (steps: steps, why: why);
}

// ------------------------------------------------------------ AutoEQ / Equalizer APO import

final _filterLine = RegExp(
  r'^\s*Filter\s*\d*\s*:\s*(ON|OFF)\s+([A-Z]+)(?:\s+[\d.]+\s*dB)?\s+Fc\s+([\d.]+)\s*(?:Hz)?'
  r'(?:\s+Gain\s+([-+]?[\d.]+)\s*dB)?(?:\s+Q\s+([\d.]+)|\s+BW\s+Oct\s+([\d.]+))?',
  caseSensitive: false,
);
final _preampLine = RegExp(r'^\s*Preamp\s*:\s*([-+]?[\d.]+)\s*dB', caseSensitive: false);

/// Reads an AutoEQ / Equalizer APO `ParametricEQ.txt` (Preamp + Filter lines; PK, LSC, HSC,
/// LS, HS, LP, HP, NO) or a `GraphicEQ:` line. Returns the EQ (advanced, on) and how many
/// lines were not understood. Throws a FormatException when nothing usable is found.
(Eq, int) parseEqText(String text, {String name = 'Headphones'}) {
  final eq = Eq(name: name, on: true, advanced: true);
  var skipped = 0;
  var found = false;
  for (final line in const LineSplitter().convert(text)) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final pre = _preampLine.firstMatch(t);
    final fl = _filterLine.firstMatch(t);
    if (pre != null) {
      eq.preamp += double.parse(pre[1]!);
      found = true;
    } else if (t.toLowerCase().startsWith('graphiceq:')) {
      for (final p in t.substring(10).split(';')) {
        final xs = p.trim().split(RegExp(r'\s+'));
        if (xs.length < 2) continue;
        final f = double.tryParse(xs[0]), g = double.tryParse(xs[1]);
        if (f != null && g != null && f > 0) eq.curve.add((f, g));
      }
      eq.curve.sort((a, b) => a.$1.compareTo(b.$1));
      found = eq.curve.isNotEmpty || found;
    } else if (fl != null) {
      if (fl[1]!.toUpperCase() == 'OFF') continue;
      final type = switch (fl[2]!.toUpperCase()) {
        'PK' || 'PEQ' || 'MODAL' => BandType.peak,
        'LS' || 'LSC' || 'LSQ' => BandType.lowShelf,
        'HS' || 'HSC' || 'HSQ' => BandType.highShelf,
        'LP' || 'LPQ' => BandType.lowPass,
        'HP' || 'HPQ' => BandType.highPass,
        'NO' => BandType.notch,
        _ => null,
      };
      if (type == null) {
        skipped++;
        continue;
      }
      final bw = double.tryParse(fl[6] ?? '');
      final q = double.tryParse(fl[5] ?? '') ?? (bw != null ? sqrt(pow(2, bw)) / (pow(2, bw) - 1) : (type == BandType.peak ? 1.41 : 0.71));
      eq.bands.add(Band(type, double.parse(fl[3]!), double.tryParse(fl[4] ?? '') ?? 0, q));
      found = true;
    } else if (!RegExp(r'^(Device|Channel|Include|Stage|Eval|Copy|Delay|Convolution)\b', caseSensitive: false).hasMatch(t)) {
      skipped++;
    }
  }
  if (!found || (eq.bands.isEmpty && eq.curve.isEmpty)) {
    throw const FormatException('No EQ filters found. Paste the text of a ParametricEQ.txt or GraphicEQ.txt file.');
  }
  return (eq, skipped);
}

/// Presets as a JSON file: {"lumen": "eq-presets", "presets": [...]}.
String exportPresets(List<Eq> presets) =>
    const JsonEncoder.withIndent('  ').convert({'lumen': 'eq-presets', 'version': 1, 'presets': [for (final p in presets) p.toJson()]});

/// Reads [exportPresets]' file, or a single preset object.
List<Eq> importPresets(String json) {
  final j = jsonDecode(json);
  final list = j is Map && j['presets'] is List ? j['presets'] as List : [j];
  return [for (final p in list) Eq.fromJson((p as Map).cast())];
}
