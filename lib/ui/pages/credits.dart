import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../platform/licence.dart';
import '../../platform/log.dart';
import '../../platform/update.dart';
import '../app.dart';
import '../theme.dart';
import '../widgets.dart';

/// Just enough Markdown for LICENSE.md and THIRD_PARTY_NOTICES.md: headings, table rows, quotes,
/// lists; links show their text.
List<Widget> markdown(String md) {
  // Links keep their text, HTML tags go, and * (bold, italics) goes except inside `code`.
  String plain(String s) => [
    for (final (i, part)
        in s.replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!).replaceAll(RegExp('<[^>]+>'), '').split('`').indexed)
      i.isOdd ? part : part.replaceAll('*', ''),
  ].join().trim();
  return [
    for (final raw in md.replaceAll('\r\n', '\n').split('\n'))
      if (raw.trim() case final l when l.isNotEmpty && !RegExp(r'^(\|[-: |]+|-{3,})$').hasMatch(l))
        Padding(
          padding: EdgeInsets.only(top: l.startsWith('#') ? S.x4 : 0, bottom: S.x2),
          child: l.startsWith('#')
              ? Text(plain(l.replaceFirst(RegExp(r'^#+'), '')), style: l.startsWith('###') ? T.label : T.heading)
              : l.startsWith('|')
              ? Text(l.split('|').map(plain).where((c) => c.isNotEmpty).join('   ·   '), style: T.small.copyWith(color: C.text))
              : Text(plain(l.replaceFirst(RegExp(r'^(> ?|- )'), l.startsWith('- ') ? '•  ' : '')), style: T.small),
        ),
  ];
}

Future<void> _showDoc(BuildContext context, String title, String file, [List<Widget> actions = const []]) async {
  final text = await asset(file) ?? creditLine;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 720,
        height: 520,
        child: SelectionArea(child: ListView(children: markdown(text))),
      ),
      actions: [
        ...actions,
        PillButton('Close', primary: true, onTap: () => Navigator.pop(ctx)),
      ],
    ),
  );
}

/// The Credits screen: who made Lumen, the third-party notices, the licence and every package licence.
Future<void> showCredits(BuildContext context) => _showDoc(context, 'Credits', 'THIRD_PARTY_NOTICES.md', [
  PillButton('Read the licence', onTap: () => _showDoc(context, 'UT Community Licence 2.0', 'LICENSE.md')),
  PillButton(
    'All package licences',
    onTap: () => showLicensePage(
      context: context,
      applicationName: 'Lumen',
      applicationVersion: shortVersion,
      applicationIcon: const Padding(padding: EdgeInsets.all(S.x3), child: AppMark(size: 48)),
      applicationLegalese: creditLine,
    ),
  ),
]);

/// Settings card: where the data is, the log, and the opt-in update check.
class DataAndUpdates extends StatelessWidget {
  const DataAndUpdates({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText('Your library, playlists, play counts and the log are kept in ${lib.dataDir}', style: T.small),
        const SizedBox(height: S.x3),
        Row(
          children: [
            PillButton('Open data folder', icon: LucideIcons.folderOpen, onTap: () => openPath(lib.dataDir)),
            const SizedBox(width: S.x3),
            PillButton('Open log', icon: LucideIcons.fileText, onTap: () => openPath(p.join(lib.dataDir, 'lumen.log'))),
          ],
        ),
        const SizedBox(height: S.x4),
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Check for updates at start-up', style: T.label),
                  SizedBox(height: 2),
                  Text(
                    'Off unless you turn it on. Lumen then asks GitHub whether a newer version is out; nothing else is sent and nothing is downloaded.',
                    style: T.small,
                  ),
                ],
              ),
            ),
            const SizedBox(width: S.x4),
            StatefulBuilder(
              builder: (context, setState) => Switch(
                value: lib.setting('updateCheck') == '1',
                onChanged: (v) => setState(() => lib.setSetting('updateCheck', v ? '1' : '0')),
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x3),
        Row(
          children: [
            PillButton('Check now', icon: LucideIcons.refreshCw, onTap: checkForUpdate),
            const SizedBox(width: S.x4),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: updateStatus,
                builder: (_, s, _) => Row(
                  children: [
                    Flexible(child: Text(s?.$1 ?? '', style: T.caption)),
                    if (s?.$2 != null) ...[
                      const SizedBox(width: S.x3),
                      PillButton('Open the release page', icon: LucideIcons.externalLink, onTap: () => openPath(s!.$2!)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shown instead of the app when it cannot start: the licence check failed, or start-up threw.
class StartupScreen extends StatefulWidget {
  const StartupScreen.refused(List<String> this.problems, {super.key}) : error = null, data = null, onFresh = null;
  const StartupScreen.failed(String this.error, String this.data, Future<void> Function() this.onFresh, {super.key}) : problems = null;
  final List<String>? problems;
  final String? error, data;
  final Future<void> Function()? onFresh;
  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  String? _note;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final (title, body) = w.problems != null
        ? (
            'Lumen cannot start',
            'Its licence credits have been removed or changed:\n\n${w.problems!.map((x) => '  -  $x').join('\n')}\n\n'
                'Reinstall Lumen or restore the original files from\n$repository\n\n$creditLine',
          )
        : (
            'Lumen could not start',
            '${w.error!.split('\n').first}\n\nData folder: ${w.data}\nDetails are in ${logPath ?? 'the log (not available)'}.\n\n'
                'Start fresh sets the library aside (library.db is renamed to library.db.broken-…, nothing is deleted) '
                'and starts with an empty library. Your music files are not touched.',
          );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        backgroundColor: C.bg,
        body: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Padding(
                padding: const EdgeInsets.all(S.x8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppMark(size: 40),
                    const SizedBox(height: S.x5),
                    Text(title, style: T.title),
                    const SizedBox(height: S.x3),
                    SelectableText(body, style: T.small),
                    if (_note != null) ...[const SizedBox(height: S.x3), Text(_note!, style: T.small.copyWith(color: C.accent))],
                    const SizedBox(height: S.x6),
                    Wrap(
                      spacing: S.x3,
                      runSpacing: S.x3,
                      children: [
                        if (w.data != null) ...[
                          PillButton('Open data folder', icon: LucideIcons.folderOpen, onTap: () => openPath(_existing(w.data!))),
                          PillButton(
                            'Start fresh',
                            icon: LucideIcons.rotateCcw,
                            primary: true,
                            onTap: () async {
                              try {
                                await w.onFresh!();
                              } catch (e) {
                                log('Start fresh failed: $e');
                                setState(() => _note = 'Could not set the library aside: $e');
                              }
                            },
                          ),
                        ],
                        PillButton('Close', onTap: () => exit(w.problems != null ? 3 : 1)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The folder, or the nearest parent that exists.
  static String _existing(String dir) {
    var d = Directory(dir);
    while (!d.existsSync() && d.parent.path != d.path) {
      d = d.parent;
    }
    return d.path;
  }
}
