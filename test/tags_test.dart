// Tag reader edge cases on tiny crafted files (test/fixtures/make_fixtures.dart writes them).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart' hide Tags;
import 'package:music_player/library/models.dart';
import 'package:music_player/library/tags.dart';

Tags read(String name) => readTags('test/fixtures/$name');

void main() {
  test('C3: a tag size of 256 MB on a tiny file does not allocate it', () {
    final before = ProcessInfo.maxRss;
    final t = read('id3_huge.mp3');
    expect(t.title, 'Real title');
    expect(ProcessInfo.maxRss - before, lessThan(64 << 20));
  });

  test('W3: FLAC with an ID3v2 tag in front is still FLAC', () {
    final t = read('id3_then_flac.flac');
    expect([t.codec, t.sampleRate, t.durationMs, t.title, t.artist], ['FLAC', 44100, 1000, 'From ID3', 'Ana']);
  });

  test('W4 + W17: chapter track first and a 64-bit moov size', () {
    final t = read('chapters64.m4a');
    expect([t.codec, t.sampleRate, t.channels, t.title], ['AAC', 44100, 2, 'Real title']);
    expect(t.bitrate, 8); // the 1000-byte mdat over 1 s, not the whole file
  });

  test('W5: a broken cover in a Vorbis comment keeps the fields after it', () {
    expect(read('vorbis.flac').title, 'Real title');
  });

  test('W6 + W7: old iTunes v2.4 sizes and an empty frame', () {
    final t = read('itunes.mp3');
    expect(t.title, 'Real title');
    expect(t.genre, 'Rock'); // "(17)"
  });

  test('W8: WAV INFO in Windows-1252; a bogus LIST size keeps the duration', () {
    final t = read('cp1252.wav');
    expect(t.artist, 'Beyoncé');
    expect(t.durationMs, 10);
  });

  test('W9: DSD (DSF and DFF) has format, length and tags', () {
    final s = read('dsd.dsf');
    expect([s.codec, s.sampleRate, s.channels, s.durationMs, s.title, s.artist], ['DSD', 2822400, 2, 1000, 'DSD title', 'Ana']);
    expect(formatBadge(s.codec, s.bitDepth, s.sampleRate, s.bitrate), 'DSD64');
    final d = read('dsd.dff');
    expect([d.codec, d.sampleRate, d.channels, d.durationMs, d.title], ['DSD', 5644800, 2, 2, 'DFF title']);
  });

  test('APE: format and length from the header', () {
    final t = read('multi.ape');
    expect([t.codec, t.bitDepth, t.sampleRate, t.channels, t.durationMs], ['APE', 16, 44100, 2, 1000]);
  });

  test('W14: raw AAC (ADTS) is AAC, not MP3', () {
    final t = read('adts.aac');
    expect([t.codec, t.sampleRate, t.channels, t.durationMs], ['AAC', 44100, 2, 232]);
  });

  test('W15 + W19: every artist value is kept (APE NUL, ID3 NUL, repeated Vorbis)', () {
    expect(read('multi.ape').artists, ['Ana', 'Bo']);
    expect(read('itunes.mp3').artists, ['Ana', 'Bo']);
    final v = read('vorbis.flac');
    expect(v.artists, ['Ana', 'Bo']);
    expect(v.artistsTag, ['Ana', 'Bo']);
    expect(v.artist, 'Ana, Bo');
  });

  test('W16: a d/m/y date gives the year', () => expect(read('vorbis.flac').year, 2017));

  test('W18 + WebM bad float: Matroska segment title and DISC; a NaN duration does not lose the rest', () {
    final t = read('segment.mka');
    expect([t.title, t.disc, t.codec, t.sampleRate, t.channels, t.durationMs], ['Segment title', 2, 'FLAC', 48000, 2, 0]);
  });

  test('FLAC above 524 kHz has a positive sample rate', () => expect(read('hirate.flac').sampleRate, 705600));

  test('ReplayGain: Vorbis, R128, ID3 TXXX and MP4 freeform', () {
    final v = read('vorbis.flac');
    expect([v.rgTrackGain, v.rgTrackPeak, v.rgAlbumGain], [-6.5, 0.988, 3.0]); // R128 -512/256 + 5
    expect(read('itunes.mp3').rgAlbumGain, 1.25);
    expect(read('chapters64.m4a').rgTrackGain, -3.0);
  });

  test('classical, sort names and MusicBrainz album id', () {
    final v = read('vorbis.flac');
    expect([v.composer, v.work, v.movementName, v.movement], ['Bach', 'Mass in B minor', 'Kyrie', 2]);
    expect([v.artistSort, v.albumArtistSort, v.albumSort, v.mbAlbumId], ['Ana', 'Ana, The', 'Mass', '0f1e-ab']);
    final m = read('itunes.mp3');
    expect(
      [m.composer, m.work, m.movementName, m.movement, m.albumArtistSort, m.mbAlbumId],
      ['Bach', 'Mass', 'Gloria', 3, 'Ana, The', 'abc-123'],
    );
    final a = read('chapters64.m4a');
    expect([a.composer, a.work, a.movementName, a.movement, a.albumArtistSort], ['Bach', 'Mass', 'Credo', 4, 'Ana, The']);
  });

  test('artist names: feat. always splits; & only between known names, never a known act', () {
    bool band(String s) => s == 'simon & garfunkel';
    bool solo(String s) => {'ana', 'bo', 'simon & garfunkel'}.contains(s);
    expect(splitArtist('Ana feat. Bo', band: band, solo: solo), ['Ana', 'Bo']);
    expect(splitArtist('Ana (ft. Cy & Bo)', band: band, solo: solo), ['Ana', 'Cy', 'Bo']);
    expect(splitArtist('Ana & Bo', band: band, solo: solo), ['Ana', 'Bo']);
    expect(splitArtist('Ana x Bo', band: band, solo: solo), ['Ana', 'Bo']);
    expect(splitArtist('Simon & Garfunkel', band: band, solo: solo), ['Simon & Garfunkel']);
    expect(splitArtist('Earth, Wind & Fire', band: band, solo: solo), ['Earth, Wind & Fire']);
    expect(primaryArtist('Ana featuring Bo'), 'Ana');
    expect(splitGenres('Rock; Pop/Jazz'), ['Rock', 'Pop', 'Jazz']);
  });
}
