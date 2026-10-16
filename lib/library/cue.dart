/// One track of a CUE sheet: its file (as the sheet names it), number, start (INDEX 01) and tags.
class CueTrack {
  CueTrack(this.file, this.no, this.startMs, {this.title, this.performer});
  final String file;
  final int no, startMs;
  final String? title, performer;
}

/// A parsed CUE sheet: the album's tags (TITLE, PERFORMER, REM DATE / GENRE) and its tracks.
class Cue {
  String? title, performer, genre;
  int? year;
  final tracks = <CueTrack>[];

  /// The tracks played from [audioFile] (a file name), when the sheet splits it into two or more:
  /// matched by name, else by name without extension (a sheet written for the .wav before it became .flac).
  List<CueTrack> tracksOf(String audioFile) {
    String base(String n) => n.toLowerCase().replaceFirst(RegExp(r'\.[^.\\/]*$'), '');
    final name = audioFile.toLowerCase();
    var out = [
      for (final t in tracks)
        if (t.file.toLowerCase() == name) t,
    ];
    if (out.isEmpty) {
      out = [
        for (final t in tracks)
          if (base(t.file) == base(name)) t,
      ];
    }
    return out.length >= 2 ? out : const [];
  }
}

final _line = RegExp(r'^\s*(REM\s+)?(\w+)\s*(.*?)\s*$', caseSensitive: false);
final _time = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2})$');

/// Reads a CUE sheet's text. Lines it does not know are skipped; it never throws.
Cue parseCue(String text) {
  final cue = Cue();
  String? file;
  int? no;
  String? title, performer;
  int? start;
  void flush() {
    final (f, n, s) = (file, no, start);
    if (f != null && n != null && s != null) cue.tracks.add(CueTrack(f, n, s, title: title, performer: performer));
    no = start = null;
    title = performer = null;
  }

  for (final raw in text.split(RegExp(r'\r\n?|\n'))) {
    final m = _line.firstMatch(raw);
    if (m == null) continue;
    final key = m[2]!.toUpperCase();
    final rest = m[3]!;
    final value = _unquote(rest);
    final inTrack = no != null;
    switch (key) {
      case 'FILE':
        flush();
        // FILE "name.flac" WAVE: the name, without the type word after it.
        file = rest.startsWith('"') ? value : rest.replaceFirst(RegExp(r'\s+\w+$'), '');
      case 'TRACK':
        flush();
        no = int.tryParse(rest.split(RegExp(r'\s+')).first);
      case 'INDEX':
        final parts = rest.split(RegExp(r'\s+'));
        final t = parts.length == 2 && int.tryParse(parts[0]) == 1 ? _time.firstMatch(parts[1]) : null;
        if (t != null) {
          // mm:ss:ff, 75 frames a second.
          start = (int.parse(t[1]!) * 60 + int.parse(t[2]!)) * 1000 + (int.parse(t[3]!) * 1000 / 75).round();
        }
      case 'TITLE' when inTrack:
        title = value;
      case 'TITLE':
        cue.title = value;
      case 'PERFORMER' when inTrack:
        performer = value;
      case 'PERFORMER':
        cue.performer = value;
      case 'DATE':
        cue.year ??= int.tryParse(RegExp(r'\d{4}').firstMatch(value)?[0] ?? '');
      case 'GENRE':
        cue.genre ??= value;
    }
  }
  flush();
  return cue;
}

String _unquote(String s) {
  if (s.startsWith('"')) {
    final end = s.indexOf('"', 1);
    return end < 0 ? s.substring(1) : s.substring(1, end);
  }
  return s;
}
