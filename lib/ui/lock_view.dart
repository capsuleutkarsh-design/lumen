import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../platform/android.dart';
import 'app.dart';
import 'disc.dart';
import 'player_bar.dart';
import 'theme.dart';
import 'widgets.dart';

/// Over the phone's lock screen (Android): the spinning disc, the song, a seek bar and the transport.
/// It shows when the phone locked with Gleo in front while music played (MainActivity.kt). "Open Gleo"
/// asks Android to unlock (PIN, fingerprint) and then the full app is back.
class LockView extends StatefulWidget {
  const LockView({super.key});
  @override
  State<LockView> createState() => _LockViewState();
}

class _LockViewState extends State<LockView> {
  @override
  void initState() {
    super.initState();
    // Menus and dialogs from the app stay hidden on the lock screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([engine, lib, discStyle]),
    builder: (context, _) {
      final t = engine.current;
      final art = t == null ? null : lib.artFor(t.albumKey, t.cover);
      return Listener(
        onPointerDown: (_) => pokeLockView(),
        child: Material(
          color: C.bg,
          child: Stack(
            children: [
              CoverGlow(art, opacity: 0.7, blur: 120),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(radius: 1.2, colors: [C.veil(0.35), C.veil(0.85)]),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(S.x6, S.x8, S.x6, S.x4),
                  child: Column(
                    children: [
                      Expanded(
                        child: art == null
                            ? const SizedBox.expand()
                            : LayoutBuilder(
                                builder: (context, c) {
                                  final wide = DiscView.widthFor(1, discStyle.value);
                                  final size = min(c.maxHeight, c.maxWidth / wide);
                                  return Center(
                                    child: DiscView(
                                      art: art,
                                      id: t!.id,
                                      playing: engine.playing,
                                      size: size,
                                      style: discStyle.value,
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: S.x6),
                      Text(
                        t?.title ?? '',
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: T.title,
                      ),
                      const SizedBox(height: S.x1),
                      Text(
                        t?.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.body.copyWith(color: C.dim),
                      ),
                      if (sleepOn)
                        const Padding(
                          padding: EdgeInsets.only(top: S.x2),
                          child: SleepLine(),
                        ),
                      const SizedBox(height: S.x4),
                      const SeekBar(big: true),
                      const SizedBox(height: S.x2),
                      const FittedBox(fit: BoxFit.scaleDown, child: Transport(big: true)),
                      const SizedBox(height: S.x6),
                      PillButton(
                        'Open Gleo',
                        key: const ValueKey('unlock'),
                        icon: LucideIcons.lockOpen,
                        glass: true,
                        onTap: unlockPhone,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
