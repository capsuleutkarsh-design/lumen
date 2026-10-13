import 'dart:convert';

import 'package:path/path.dart' as p;

import 'models.dart';

String toM3u8(List<Track> tracks) => [
  '#EXTM3U',
  for (final t in tracks) ...['#EXTINF:${t.durationMs ~/ 1000},${t.artist} - ${t.title}', t.path],
].join('\r\n');

/// Paths in an M3U/M3U8 file, made absolute against the playlist's folder.
List<String> parseM3u(String text, String playlistDir) => [
  for (final l in const LineSplitter().convert(text.replaceFirst('\uFEFF', '')))
    if (l.trim().isNotEmpty && !l.startsWith('#')) p.normalize(p.isAbsolute(l.trim()) ? l.trim() : p.join(playlistDir, l.trim())),
];
