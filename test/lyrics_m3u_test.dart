import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/library/lyrics.dart';
import 'package:music_player/library/m3u.dart';
import 'package:music_player/library/models.dart';

void main() {
  test('LRC: stamps, repeated lines, offset; plain text stays unsynced', () {
    final l = parseLyrics('[ar:X]\n[offset:+500]\n[00:01.50]One\n[00:03.00][00:05.25]Two\n[00:04:10]Mid');
    expect(l.synced, isTrue);
    expect([for (final x in l.lines) x.$2], ['One', 'Two', 'Mid', 'Two']);
    expect(l.lines.first.$1, const Duration(milliseconds: 1000)); // 1.5 s - 0.5 s offset
    expect(l.lineAt(const Duration(milliseconds: 3600)), 2);
    expect(l.lineAt(Duration.zero), -1);
    final plain = parseLyrics('Just words\nMore words');
    expect(plain.synced, isFalse);
    expect(plain.lines.length, 2);
  });

  test('LRC: a UTF-16 file reads right; a 20-digit stamp is not a stamp', () {
    final tmp = Directory.systemTemp.createTempSync('mp_lrc');
    const s = '[00:01.00]Héllo';
    File('${tmp.path}/song.lrc').writeAsBytesSync([
      0xFF,
      0xFE,
      for (final c in s.codeUnits) ...[c & 0xFF, c >> 8],
    ]);
    final l = loadLyrics('${tmp.path}/song.flac', null)!;
    tmp.deleteSync(recursive: true);
    expect([l.synced, l.lines.single.$2], [true, 'Héllo']);
    expect(parseLyrics('[99999999999999999999:00.00]x').synced, isFalse);
  });

  test('M3U8 export and import round trip with relative paths', () {
    final t = Track(id: 1, title: 'Song', artist: 'Ana', path: r'C:\Music\Ana\01 Song.flac', durationMs: 61000);
    expect(toM3u8([t]), '#EXTM3U\r\n#EXTINF:61,Ana - Song\r\nC:\\Music\\Ana\\01 Song.flac');
    expect(parseM3u('#EXTM3U\n#EXTINF:1,x\nAna\\01 Song.flac\n\nC:\\Other\\b.mp3\n', r'C:\Music'), [
      r'C:\Music\Ana\01 Song.flac',
      r'C:\Other\b.mp3',
    ]);
  });
}
