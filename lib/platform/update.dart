import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log.dart';

/// The version from pubspec.yaml, baked into lumen.exe and passed in by main.cpp ("dev" in tests).
var appVersion = 'dev';

/// "0.2.0-beta" from "0.2.0-beta+3".
String get shortVersion => appVersion.split('+').first;

const releasesApi = 'https://api.github.com/repos/capsuleutkarsh-design/lumen/releases?per_page=1';

/// The result of the last check: (what to say, the release page or null).
final updateStatus = ValueNotifier<(String, String?)?>(null);

/// True when the release [tag] ("v0.3.0", "v0.2.0-beta") is newer than [current] ("0.2.0-beta+3").
bool isNewer(String tag, String current) {
  List<int> nums(String v) => [
    for (final x in v.replaceFirst(RegExp('^v'), '').split(RegExp('[-+]')).first.split('.')) int.tryParse(x) ?? 0,
    0, 0, 0, // pad
  ];
  final a = nums(tag), b = nums(current);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return !tag.contains('-') && current.split('+').first.contains('-'); // 0.2.0 is newer than 0.2.0-beta
}

/// Asks GitHub for the newest release. Only runs when the user turned it on or pressed Check now.
/// Nothing is downloaded; the result links to the release page.
Future<void> checkForUpdate() async {
  updateStatus.value = ('Checking…', null);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse(releasesApi));
    req.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'Lumen/$shortVersion');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) throw HttpException('GitHub answered ${res.statusCode}');
    final r = (jsonDecode(body) as List).firstOrNull as Map?;
    final tag = r?['tag_name'] as String?;
    updateStatus.value = tag != null && isNewer(tag, appVersion)
        ? ('Lumen ${tag.replaceFirst('v', '')} is available.', r!['html_url'] as String?)
        : ('Lumen $shortVersion is the newest version.', null);
  } catch (e) {
    log('Update check: $e');
    updateStatus.value = ('Could not reach GitHub. Try again later.', null);
  } finally {
    client.close();
  }
}
