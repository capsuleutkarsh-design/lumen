import 'dart:io';

import 'package:flutter/material.dart';

import '../../platform/tray.dart';
import '../app.dart';
import '../art_accent.dart';
import '../theme.dart';
import 'browse.dart';

/// Settings → Theme: dark, light or follow Windows, and the accent from album art.
class ThemeSettings extends StatelessWidget {
  const ThemeSettings({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: appearance,
    builder: (context, mode, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: S.x4,
          runSpacing: S.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 124, child: Text('Colours', style: T.label)),
            Segmented(
              value: mode,
              options: [('dark', 'Dark'), ('light', 'Light'), ('system', Platform.isAndroid ? 'Follow the phone' : 'Follow Windows')],
              onChanged: setAppearance,
            ),
          ],
        ),
        const SizedBox(height: S.x4),
        _Toggle(
          'Accent from album art',
          'Now Playing glows, and the seek bar fills, in a colour from the cover. Grey, very dark or very light covers keep coral.',
          accentFromArt,
          (v) {
            lib.setSetting('artAccent', v ? '1' : '0');
            refreshArtAccent();
          },
        ),
      ],
    ),
  );
}

/// Settings → Window: close to the tray.
class WindowSettings extends StatelessWidget {
  const WindowSettings({super.key});
  @override
  Widget build(BuildContext context) => _Toggle(
    'Close to tray',
    'Closing the window keeps Gleo playing in the notification area. Click its icon to come back; right-click it to quit.',
    closeToTray(lib),
    (v) => lib.setSetting('closeToTray', v ? '1' : '0'),
  );
}

class _Toggle extends StatefulWidget {
  const _Toggle(this.title, this.body, this.value, this.onChanged);
  final String title, body;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  late bool _v = widget.value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: T.label),
            const SizedBox(height: 2),
            Text(widget.body, style: T.small),
          ],
        ),
      ),
      const SizedBox(width: S.x4),
      Switch(
        value: _v,
        onChanged: (v) {
          setState(() => _v = v);
          widget.onChanged(v);
        },
      ),
    ],
  );
}
