import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleo/platform/licence.dart';

void main() {
  final licence = File('LICENSE.md').readAsStringSync();
  final notices = File('THIRD_PARTY_NOTICES.md').readAsStringSync();

  test('the licence files pass the start-up check', () {
    // After the Author changes LICENSE.md on purpose, this prints the value for licenceSha256.
    expect(licenceHash(licence), licenceSha256, reason: 'LICENSE.md changed. New hash: ${licenceHash(licence)}');
    expect(licenceProblems(licence, notices), isEmpty);
    expect(licenceProblems(licence.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n'), notices), isEmpty, reason: 'CRLF checkout');
  });

  test('a tampered or missing licence, or notices without the credit line, stop the app', () {
    expect(licenceProblems(licence.replaceFirst('Sell', 'Sel'), notices), ['LICENSE.md has been changed']);
    expect(licenceProblems(null, notices), ['LICENSE.md is missing']);
    expect(licenceProblems(licence, notices.replaceAll(creditLine, 'Gleo')), ['THIRD_PARTY_NOTICES.md has been changed']);
    expect(licenceProblems(licence, null), ['THIRD_PARTY_NOTICES.md is missing']);
  });
}
