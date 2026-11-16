import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../pas_de_tir/pas_de_tir_flow.dart';
import '../pas_de_tir/pas_de_tir_result.dart';
import '../pas_de_tir/widgets/scenes.dart';
import '../theme/alp_tokens.dart';
import '../widgets/alp_common.dart';
import 'race_results_screen.dart';
import 'race_state.dart';

/// Carte en course : 01 approche du pas de tir, puis 15 retour en course.
///
/// En mode démo ([demoMode] renseigné), seul ce mode est joué et l'écran se
/// ferme à la fin du pas de tir en renvoyant le résultat (ou null si fermé).
class RaceMapScreen extends StatefulWidget {
  const RaceMapScreen({super.key, required this.race, this.startArrived = false, this.demoMode, this.pseudo});

  final RaceState race;

  /// Démarre directement après le POI (accès direct à l'écran 15).
  final bool startArrived;

  final PasDeTirMode? demoMode;

  /// Pseudo du joueur, affiché au-dessus de son marqueur.
  final String? pseudo;

  bool get isDemo => demoMode != null;

  @override
  State<RaceMapScreen> createState() => _RaceMapScreenState();
}

class _RaceMapScreenState extends State<RaceMapScreen> with TickerProviderStateMixin {
  static const _poiDistance = 40.0;

  /// Avancement de l'utilisateur sur la trace : départ, POI, et après le POI.
  static const _startProgress = 0.33, _poiProgress = 0.43, _afterPoiProgress = 0.52;

  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();
  late final AnimationController _approach = AnimationController(vsync: this, duration: const Duration(seconds: 2));
  late final AnimationController _leave = AnimationController(vsync: this, duration: const Duration(seconds: 2));
  final _clock = Stopwatch()..start();
  Timer? _clockTimer;
  bool _gameOpen = false;
  String? _toast;

  RaceState get race => widget.race;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    if (race.pasDeTir != null || widget.startArrived) {
      _approach.value = 1;
      _leave.value = 1;
    } else {
      // Simulation de l'approche ; à l'arrivée, ouverture automatique (géofence).
      _approach.forward();
      _approach.addStatusListener((s) {
        if (s == AnimationStatus.completed) _openGame();
      });
    }
  }

  Future<void> _openGame() async {
    if (_gameOpen || race.pasDeTir != null) return;
    _gameOpen = true;
    _approach.value = 1;
    final result = await runPasDeTir(context, demoMode: widget.demoMode);
    _gameOpen = false;
    if (!mounted) return;
    if (widget.isDemo) {
      if (result != null) race.recordPasDeTir(result);
      Navigator.pop(context, result);
      return;
    }
    if (result == null) return;
    race.recordPasDeTir(result);
    _leave.forward(from: 0);
    _showToast('Pas de tir terminé · +${result.drops} gouttes');
  }

  void _showToast(String text) {
    setState(() => _toast = text);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _approach.dispose();
    _leave.dispose();
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = race.pasDeTir != null;
    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_pulse, _approach, _leave, race]),
        builder: (context, _) {
          final progress =
              ui.lerpDouble(_startProgress, _poiProgress, Curves.easeInOut.transform(_approach.value))! +
              (_afterPoiProgress - _poiProgress) * _leave.value;
          final distance = (_poiDistance * (1 - _approach.value)).round();
          return LayoutBuilder(
            builder: (context, cons) {
              final size = cons.biggest;
              final trace = RaceMapPainter.tracePath(size).computeMetrics().first;
              final userPos = trace.getTangentForOffset(trace.length * progress)!.position;
              final poi = RaceMapPainter.poiPosition(size);
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: RaceMapPainter(userProgress: progress)),
                  ),
                  _UserMarker(position: userPos),
                  if (widget.pseudo != null) _PseudoLabel(position: userPos, text: widget.pseudo!),
                  _PoiMarker(position: poi, pulse: _pulse.value, done: done, onTap: _openGame),
                  if (!done)
                    Positioned(
                      left: poi.dx + 30,
                      top: poi.dy - 18,
                      child: _MapLabel(text: distance > 0 ? 'Pas de tir · $distance m' : 'Pas de tir'),
                    ),
                  Positioned(left: 16, right: 16, top: MediaQuery.paddingOf(context).top + 8, child: _statsCard()),
                  if (_toast != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: MediaQuery.paddingOf(context).top + 84,
                      child: Center(child: _DarkToast(text: _toast!)),
                    ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.paddingOf(context).bottom + 12,
                    child: _gamesSheet(),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _statsCard() {
    final elapsed = const Duration(minutes: 42, seconds: 12) + _clock.elapsed;
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(elapsed.inHours)}:${two(elapsed.inMinutes % 60)}:${two(elapsed.inSeconds % 60)}';
    final km = 4.1 + _approach.value * 0.12 + _leave.value * 0.08;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AlpRadii.card),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10)],
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Retour',
            child: InkWell(
              onTap: () => Navigator.maybePop(context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AlpColors.border),
                ),
                child: const Icon(Icons.chevron_left_rounded),
              ),
            ),
          ),
          Expanded(
            child: _Stat(value: km.toStringAsFixed(1), unit: 'km', label: 'Distance'),
          ),
          Expanded(
            child: _Stat(value: time, label: 'Temps'),
          ),
          Expanded(
            child: _Stat(value: '${350 + (_leave.value * 2).round()}', unit: 'm', label: 'Dénivelé'),
          ),
          if (widget.isDemo)
            const SizedBox(width: 44)
          else
            Semantics(
              button: true,
              label: "Terminer l'épreuve",
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RaceResultsScreen(race: race))),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AlpColors.fir, width: 2),
                  ),
                  child: const Icon(Icons.hiking, color: AlpColors.fir, size: 22),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _gamesSheet() {
    final done = race.pasDeTir;
    final segments = 4;
    final filled = (race.drops / RaceState.dropGoal * segments).floor();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 16)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F4F0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFECEAE4)),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < segments; i++)
                        Expanded(
                          child: Container(
                            height: 7,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: i < filled ? AlpColors.cyan : const Color(0xFFECEAE4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const DropBadge(size: 16),
              const SizedBox(width: 6),
              Text(
                '${race.drops}/${RaceState.dropGoal}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const Divider(height: 24),
          if (done == null) ...[
            const Center(
              child: Text('Jeu à proximité', style: TextStyle(color: AlpColors.textSecondary, fontSize: 16)),
            ),
            const SizedBox(height: 10),
            _GameRow(
              icon: const TargetGlyph(size: 20),
              title: 'Pas de tir',
              subtitle: "5 cibles · jusqu'à +50 gouttes",
              trailing: const _DropsTrailing(value: 50),
              highlighted: true,
              onTap: _openGame,
            ),
            const SizedBox(height: 10),
            const Center(
              child: Text(
                "Le jeu s'ouvre automatiquement à ton arrivée",
                style: TextStyle(color: AlpColors.textSecondary, fontSize: 13),
              ),
            ),
          ] else ...[
            const _GameRow(
              icon: Icon(Icons.question_mark_rounded, color: AlpColors.petrol, size: 20),
              title: 'Quiz',
              trailing: Icon(Icons.check_rounded, color: AlpColors.petrol),
            ),
            const SizedBox(height: 8),
            _GameRow(
              icon: const TargetGlyph(size: 20),
              title: 'Pas de tir',
              subtitle: '${done.hits}/${done.shots.length} cibles · +${done.drops} gouttes',
              trailing: const Icon(Icons.check_rounded, color: AlpColors.petrol),
            ),
            const SizedBox(height: 8),
            const _GameRow(
              icon: Icon(Icons.photo_camera, color: AlpColors.petrol, size: 18),
              title: 'Défi Photo',
              trailing: _DropsTrailing(value: 10),
              highlighted: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.unit});
  final String value;
  final String label;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(color: AlpColors.textSecondary, fontSize: 11),
                  ),
              ],
            ),
          ),
          Text(label, style: const TextStyle(color: AlpColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.highlighted = false,
    this.onTap,
  });

  final Widget icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? const Color(0xFFF5F4F0) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AlpRadii.card),
        side: highlighted ? BorderSide.none : const BorderSide(color: AlpColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AlpRadii.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              GameIconBadge(child: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: subtitle != null && highlighted ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: const TextStyle(color: AlpColors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _DropsTrailing extends StatelessWidget {
  const _DropsTrailing({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('+$value', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(width: 4),
        const DropBadge(size: 16),
      ],
    );
  }
}

class _PoiMarker extends StatelessWidget {
  const _PoiMarker({required this.position, required this.pulse, required this.done, required this.onTap});
  final Offset position;
  final double pulse;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = 80.0;
    return Positioned(
      left: position.dx - size / 2,
      top: position.dy - size / 2,
      child: Semantics(
        button: true,
        label: done ? 'Pas de tir validé' : 'Pas de tir',
        child: GestureDetector(
          onTap: done ? null : onTap,
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!done)
                  Container(
                    width: 40 + 40 * pulse,
                    height: 40 + 40 * pulse,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AlpColors.petrol.withValues(alpha: 0.35 * (1 - pulse)),
                    ),
                  ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AlpColors.petrol.withValues(alpha: 0.25)),
                ),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AlpColors.petrol,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                      : const Center(child: TargetGlyph(size: 20, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pseudo du joueur (mode démo), au-dessus de son marqueur.
class _PseudoLabel extends StatelessWidget {
  const _PseudoLabel({required this.position, required this.text});
  final Offset position;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 100,
      top: position.dy - 17 - 36,
      width: 200,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AlpColors.orange,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)],
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class _UserMarker extends StatelessWidget {
  const _UserMarker({required this.position});
  final Offset position;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 17,
      top: position.dy - 17,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AlpColors.orange,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)],
        ),
        child: Transform.rotate(
          angle: -math.pi / 12,
          child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _MapLabel extends StatelessWidget {
  const _MapLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
    );
  }
}

class _DarkToast extends StatelessWidget {
  const _DarkToast({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xE6262A2C), borderRadius: BorderRadius.circular(AlpRadii.button)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DropBadge(size: 16),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 14.5)),
        ],
      ),
    );
  }
}
