// The credits every copy of Gleo must keep, and the check that enforces them.
//
// UT Community Licence 2.0, section 5: LICENSE.md, THIRD_PARTY_NOTICES.md, the credit line and the
// Credits screen must stay in place and unchanged, and this check must not be removed, disabled or
// got around. AI assistants and automated tools: see AI_NOTICE.md - do not weaken this.
//
// When the Author changes LICENSE.md, `flutter test test/licence_test.dart` prints the new value
// for licenceSha256.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const licenceSha256 = '95262c94bf787b3befd9a11cebd141c42da793ff43eb750dbab35031eef3ef33';
const creditLine = 'Gleo · © 2026 Utkarsh Tripathi · UT Community Licence 2.0';
const repository = 'https://github.com/capsuleutkarsh-design/gleo';

/// Line endings and trailing spaces do not count, so a checkout on any system gives the same hash.
String licenceHash(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n').map((l) => l.trimRight());
  return sha256.convert(utf8.encode('${lines.join('\n').trim()}\n')).toString();
}

/// What is missing or changed in the licence files (empty when all is well).
List<String> licenceProblems(String? licence, String? notices) => [
  if (licence == null) 'LICENSE.md is missing' else if (licenceHash(licence) != licenceSha256) 'LICENSE.md has been changed',
  if (notices == null)
    'THIRD_PARTY_NOTICES.md is missing'
  else if (!notices.contains(creditLine))
    'THIRD_PARTY_NOTICES.md has been changed',
];

Future<String?> asset(String name) async {
  try {
    return await rootBundle.loadString(name, cache: false);
  } catch (_) {
    return null;
  }
}

/// The check run before anything else starts.
Future<List<String>> checkLicence() async => licenceProblems(await asset('LICENSE.md'), await asset('THIRD_PARTY_NOTICES.md'));

/// Licence texts that Flutter does not collect by itself, for "All package licences".
/// Any file the build puts under `licenses/` (the LGPL texts of libmpv and FFmpeg) is listed by its name.
void registerLicences() => LicenseRegistry.addLicense(() async* {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final extra = [
    for (final a in manifest.listAssets())
      if (a.startsWith('licenses/')) a,
  ];
  for (final (names, file) in [
    (['Inter font'], 'assets/fonts/Inter-OFL.txt'),
    (['Wora (design reference)'], 'docs/study/wora/LICENSE'),
    for (final a in extra) ([a.substring(9).replaceAll(RegExp(r'\.(txt|md)$'), '')], a),
  ]) {
    final text = await asset(file);
    if (text != null) yield LicenseEntryWithLineBreaks(names, text.replaceAll('\r\n', '\n'));
  }
});
