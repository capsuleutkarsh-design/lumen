import 'dart:math';

enum Repeat { off, all, one }

/// One slot in the queue. The same track can be queued twice, so slots have
/// their own identity.
class Entry {
  Entry(this.trackId) : uid = _next++;
  final int trackId;
  final int uid;
  static int _next = 0;
  @override
  String toString() => 'Entry($trackId)';
}

/// The play queue: pure logic, no audio. [items] is the order things play in
/// (shuffled when shuffle is on); [original] keeps the unshuffled order.
class PlayQueue {
  PlayQueue({Random? random}) : _random = random ?? Random();
  final Random _random;

  /// Previous restarts the track when the position is past this.
  static const restartAfter = Duration(seconds: 3);

  List<Entry> items = [];
  List<Entry> original = [];
  int index = -1;
  bool shuffle = false;
  Repeat repeat = Repeat.off;

  /// Previously played entries, most recent last (for Previous).
  final List<Entry> history = [];

  /// When shuffle + repeat all wraps, the next cycle's order is fixed here
  /// so that [peekNext] and [next] agree.
  List<Entry>? _nextCycle;

  Entry? get current => index >= 0 && index < items.length ? items[index] : null;
  List<Entry> get upcoming => index < 0 ? items : items.sublist(index + 1);

  /// Replace the queue with [trackIds] and start at [start].
  void playNow(List<int> trackIds, [int start = 0]) {
    _leave();
    original = [for (final id in trackIds) Entry(id)];
    items = List.of(original);
    index = items.isEmpty ? -1 : start.clamp(0, items.length - 1);
    if (shuffle) _shuffleAroundCurrent();
  }

  /// Insert right after the current track.
  void playNext(List<int> trackIds) {
    final add = [for (final id in trackIds) Entry(id)];
    final cur = current;
    items.insertAll(index + 1, add);
    original.insertAll(cur == null ? 0 : original.indexOf(cur) + 1, add);
    if (index < 0) index = 0;
    _nextCycle = null;
  }

  /// Append to the end.
  void addToQueue(List<int> trackIds) {
    final add = [for (final id in trackIds) Entry(id)];
    items.addAll(add);
    original.addAll(add);
    if (index < 0) index = 0;
    _nextCycle = null;
  }

  /// Move an entry within [items] (drag to reorder). Unshuffled, the original
  /// order follows the same move.
  void move(int from, int to) {
    final e = items.removeAt(from);
    items.insert(to, e);
    if (from == index) {
      index = to;
    } else if (from < index && to >= index) {
      index--;
    } else if (from > index && to <= index) {
      index++;
    }
    if (!shuffle) original = List.of(items);
    _nextCycle = null;
  }

  /// Remove any entry except the current one.
  void remove(int i) {
    if (i == index) return;
    final e = items.removeAt(i);
    original.remove(e);
    history.remove(e);
    if (i < index) index--;
    _nextCycle = null;
  }

  /// Jump to an entry (click in the queue).
  void jump(int i) {
    if (i == index || i < 0 || i >= items.length) return;
    _leave();
    index = i;
  }

  /// What plays after the current track ends on its own (for gapless preload).
  Entry? peekNext() {
    if (current == null) return null;
    if (repeat == Repeat.one) return current;
    if (index + 1 < items.length) return items[index + 1];
    if (repeat == Repeat.all && items.isNotEmpty) return (_nextCycle ??= _newCycle()).first;
    return null;
  }

  /// Advance. [auto] = the track ended by itself (repeat-one repeats then).
  Entry? next({bool auto = false}) {
    if (current == null) return null;
    if (auto && repeat == Repeat.one) return current;
    if (index + 1 < items.length) {
      _leave();
      index++;
    } else if (repeat == Repeat.all || (repeat == Repeat.one && !auto)) {
      _leave();
      if (shuffle) {
        items = _nextCycle ?? _newCycle();
      }
      index = 0;
    } else {
      return null;
    }
    _nextCycle = null;
    return current;
  }

  /// Go back to the previously played entry (history). The caller handles the
  /// "more than 3 s in restarts the track" rule; null means restart.
  Entry? previous() {
    while (history.isNotEmpty) {
      final e = history.removeLast();
      final i = items.indexOf(e);
      if (i >= 0) {
        index = i;
        _nextCycle = null;
        return e;
      }
    }
    // Nothing played before (e.g. started mid-album): step back in the list.
    if (index > 0) {
      index--;
      _nextCycle = null;
      return current;
    }
    return null;
  }

  void setShuffle(bool on) {
    if (on == shuffle) return;
    shuffle = on;
    _nextCycle = null;
    if (on) {
      _shuffleAroundCurrent();
    } else {
      final cur = current;
      items = List.of(original);
      index = cur == null ? (items.isEmpty ? -1 : 0) : items.indexOf(cur);
    }
  }

  /// Current track first, everything else in random order: each track plays
  /// once before anything repeats.
  void _shuffleAroundCurrent() {
    final cur = current;
    final rest = [for (final e in original) if (e != cur) e]..shuffle(_random);
    items = [?cur, ...rest];
    index = items.isEmpty ? -1 : 0;
  }

  /// A new shuffled cycle that does not start with the track that just played.
  List<Entry> _newCycle() {
    if (!shuffle) return items;
    final cycle = List.of(original)..shuffle(_random);
    if (cycle.length > 1 && cycle.first == current) {
      cycle.add(cycle.removeAt(0));
    }
    return cycle;
  }

  void _leave() {
    final cur = current;
    if (cur == null) return;
    history.add(cur);
    if (history.length > 200) history.removeAt(0);
  }

  // Persistence: track ids + positions; entries get new identities on load.
  Map<String, Object?> toJson() => {
        'items': [for (final e in items) e.trackId],
        'original': [for (final e in original) items.indexOf(e)],
        'index': index,
        'shuffle': shuffle,
        'repeat': repeat.index,
      };

  void restore(Map<String, Object?> j, bool Function(int trackId) exists) {
    final ids = (j['items'] as List).cast<int>();
    items = [for (final id in ids) Entry(id)];
    final order = (j['original'] as List).cast<int>();
    original = [for (final i in order) if (i >= 0 && i < items.length) items[i]];
    index = (j['index'] as int).clamp(-1, items.length - 1);
    shuffle = j['shuffle'] as bool;
    repeat = Repeat.values[j['repeat'] as int];
    // Drop tracks that left the library.
    for (var i = items.length - 1; i >= 0; i--) {
      if (!exists(items[i].trackId)) {
        if (i == index) index = -1;
        original.remove(items[i]);
        items.removeAt(i);
        if (i < index) index--;
      }
    }
    if (index < 0 && items.isNotEmpty) index = 0;
  }
}
