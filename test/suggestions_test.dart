import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/library/models.dart';
import 'package:music_player/library/suggestions.dart';

void main() {
  final now = DateTime(2026, 10, 13, 12);
  DateTime daysAgo(num d) => now.subtract(Duration(minutes: (d * 24 * 60).round()));

  Track t(int id, String artist, String album, {String? aa, String genre = 'Jazz', int year = 2015, int added = 0}) => Track(
    id: id,
    title: 'Song $id',
    artist: artist,
    albumArtist: aa,
    album: album,
    genre: genre,
    year: year,
    trackNo: id,
    addedAt: daysAgo(added).millisecondsSinceEpoch,
  );

  final tracks = [
    t(1, 'Ana', 'Blue', added: 100), t(2, 'Ana', 'Blue', added: 100), t(3, 'Ana', 'Green', added: 50),
    t(4, 'Bo', 'Mix', aa: 'Ana', added: 40), // album artist Ana, other track artist
    t(5, 'Cy', 'Late', year: 2018, added: 3), // same genre + decade as track 1
    t(6, 'Cy', 'Late', year: 1999, added: 3), // other decade
    t(7, 'Ana', 'Green', added: 50), // often skipped
    t(8, 'Dee', 'Old', genre: 'Rock', added: 400),
  ];
  final albums = <Album>[];
  for (final key in {for (final x in tracks) x.albumKey}) {
    albums.add(Album(key, tracks.where((x) => x.albumKey == key).toList()));
  }
  PlayEvent play(int id, num d) => PlayEvent(id, daysAgo(d), false);
  PlayEvent skip(int id, num d) => PlayEvent(id, daysAgo(d), true);
  final events = [
    play(8, 90), play(8, 80), play(8, 70), play(8, 60), // played often, long ago
    play(2, 5), play(2, 4), // most played recent
    play(1, 0.1), // seed: the last played track
    skip(7, 10), skip(7, 9), skip(7, 8),
    play(3, 1), // played lately: excluded from "because"
  ];
  final h = suggest(tracks, albums, events, now);

  test('play and skip rules', () {
    expect(ListenRules.counts(const Duration(minutes: 2), const Duration(minutes: 4)), isTrue);
    expect(ListenRules.counts(const Duration(minutes: 1), const Duration(minutes: 4)), isFalse);
    expect(ListenRules.counts(const Duration(minutes: 4), const Duration(minutes: 20)), isTrue);
    expect(ListenRules.isSkip(const Duration(seconds: 29)), isTrue);
    expect(ListenRules.isSkip(const Duration(seconds: 30)), isFalse);
  });

  test('jump back in lists albums by most recent play', () {
    expect([for (final p in h.jumpBackIn) p.item.title], ['Blue', 'Green', 'Old']);
    expect(h.jumpBackIn.first.why, 'You played this 2 h ago');
  });

  test('most played counts plays, never skips', () {
    expect([for (final p in h.mostPlayed) p.item.id], [8, 2, 1, 3]);
    expect(h.mostPlayed.first.why, 'Played 4 times');
  });

  test('not played in a while: played often, but not in the last 30 days', () {
    expect([for (final p in h.notLately) p.item.id], [8]);
    expect(h.notLately.single.why, 'Played 4 times, last 2 months ago');
  });

  test('recently added: newest albums first', () {
    expect(h.recentlyAdded.first.item.title, 'Late');
    expect(h.recentlyAdded.first.why, 'Added 3 days ago');
  });

  test('because you played: artist, then album artist, then genre + decade', () {
    expect(h.seed!.id, 1);
    // 2 = same artist; 3 played lately and 7 often skipped are left out;
    // 4 = album artist Ana; 5 = Jazz from the 2010s; 6 (1990s) and 8 (Rock) do not match.
    expect([for (final p in h.because) p.item.id], [2, 4, 5]);
    expect(h.because[0].why, contains('Same artist'));
    expect(h.because[1].why, startsWith('From Ana'));
    expect(h.because[2].why, startsWith('Jazz from the 2010s'));
  });
}
