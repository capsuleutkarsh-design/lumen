import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Widget _card(String title, String? subtitle, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: S.x4),
    child: Panel(
      padding: const EdgeInsets.all(S.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: T.heading),
          if (subtitle != null) ...[const SizedBox(height: S.x1), Text(subtitle, style: T.small)],
          const SizedBox(height: S.x4),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([lib, engine]),
    builder: (context, _) {
      final folders = lib.folders;
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          const PageHeader('Settings'),
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _card('Library folders', 'The player reads these folders and watches them for changes. Your files are never changed.', [
                    if (folders.isEmpty) Text('No folders yet.', style: T.small.copyWith(color: C.faint)),
                    for (final f in folders)
                      Container(
                        margin: const EdgeInsets.only(bottom: S.x2),
                        padding: const EdgeInsets.fromLTRB(S.x3, S.x1, S.x1, S.x1),
                        decoration: BoxDecoration(
                          color: C.raised2,
                          borderRadius: BorderRadius.circular(R.small + 2),
                          border: Border.all(color: C.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.folder, size: 16, color: C.dim),
                            const SizedBox(width: S.x3),
                            Expanded(
                              child: Text(f, style: T.label, overflow: TextOverflow.ellipsis),
                            ),
                            IconBtn(
                              LucideIcons.x,
                              size: 14,
                              box: 32,
                              tooltip: 'Remove folder',
                              onTap: () async {
                                if (await confirm(
                                  context,
                                  'Remove this folder?',
                                  '$f\n\nIts songs leave the library (the files stay on disk). Play counts for them are forgotten.',
                                  action: 'Remove',
                                )) {
                                  lib.folders = [...folders]..remove(f);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: S.x2),
                    Row(
                      children: [
                        PillButton(
                          'Add folder',
                          icon: LucideIcons.folderPlus,
                          primary: true,
                          onTap: () async {
                            final dir = await getDirectoryPath(confirmButtonText: 'Use this folder');
                            if (dir != null && !folders.contains(dir)) lib.folders = [...folders, dir];
                          },
                        ),
                        const SizedBox(width: S.x3),
                        PillButton('Rescan now', icon: LucideIcons.refreshCw, onTap: folders.isEmpty ? null : lib.rescan),
                        const SizedBox(width: S.x4),
                        Expanded(
                          child: ValueListenableBuilder(
                            valueListenable: lib.scan,
                            builder: (_, s, _) => Text(
                              s != null
                                  ? (s.$2 == 0 ? 'Checking for changes…' : 'Reading ${s.$1} of ${s.$2} new or changed files…')
                                  : '${plural(lib.tracks.length, 'song')} · ${plural(lib.albums.length, 'album')}${lib.lastScan == null ? '' : ' · last scan: ${lib.lastScan}'}',
                              style: T.caption,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ]),
                  _card('Sound output', null, [
                    Row(
                      children: [
                        const SizedBox(width: 140, child: Text('Output device', style: T.label)),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: S.x3),
                            decoration: BoxDecoration(
                              color: C.raised2,
                              borderRadius: BorderRadius.circular(R.small + 2),
                              border: Border.all(color: C.border),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: engine.devices.any((d) => d.name == engine.device) ? engine.device : null,
                                hint: Text(engine.device == 'auto' ? 'System default' : engine.device, style: T.label),
                                isExpanded: true,
                                dropdownColor: C.raised2,
                                borderRadius: BorderRadius.circular(R.small + 2),
                                style: T.label,
                                icon: const Icon(LucideIcons.chevronDown, size: 16, color: C.dim),
                                items: [
                                  for (final d in engine.devices)
                                    DropdownMenuItem(
                                      value: d.name,
                                      child: Text(d.name == 'auto' ? 'System default' : d.description, overflow: TextOverflow.ellipsis),
                                    ),
                                ],
                                onChanged: (v) => v == null ? null : engine.setDevice(v),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: S.x4),
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Exclusive mode (bit-perfect)', style: T.label),
                              SizedBox(height: 2),
                              Text(
                                'The player takes the device for itself and sends the file\'s samples unchanged, at its own sample rate. '
                                'Other apps go quiet while it plays. Keep the volume at 100% for bit-perfect output.',
                                style: T.small,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: S.x4),
                        Switch(value: engine.exclusive, onChanged: engine.setExclusive),
                      ],
                    ),
                    if (engine.outputFormat.isNotEmpty) ...[
                      const SizedBox(height: S.x3),
                      Text('Now sending: ${engine.outputFormat}', style: T.caption),
                    ],
                  ]),
                  _card('Keyboard', null, [
                    for (final (k, v) in const [
                      ('Space', 'Play / pause'),
                      ('Ctrl + ← / →', 'Previous / next song'),
                      ('← / →', 'Back / forward 5 seconds'),
                      ('Ctrl + K', 'Search'),
                      ('Ctrl + L', 'Lyrics'),
                      ('Esc', 'Back'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: S.x2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 140,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: C.raised2,
                                    borderRadius: BorderRadius.circular(R.small - 2),
                                    border: Border.all(color: C.borderStrong),
                                  ),
                                  child: Text(
                                    k,
                                    style: T.caption.copyWith(color: C.text, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                            ),
                            Text(v, style: T.small),
                          ],
                        ),
                      ),
                  ]),
                  _card('About', null, [
                    Row(
                      children: [
                        const AppMark(size: 40),
                        const SizedBox(width: S.x4),
                        Expanded(
                          child: Text(
                            'Music Player 1.0 · plays through libmpv (media_kit). Design inspired by Wora (MIT). '
                            'Font: Inter (SIL Open Font License). Icons: Lucide (ISC). No AI, no internet: suggestions come only from what you play here.',
                            style: T.small,
                          ),
                        ),
                      ],
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
