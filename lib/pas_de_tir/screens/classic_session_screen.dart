import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/alp_tokens.dart';
import '../../widgets/alp_common.dart';
import '../pas_de_tir_config.dart';
import '../pas_de_tir_result.dart';
import '../shooting_session.dart';
import '../widgets/scenes.dart';
import '../widgets/shooting_widgets.dart';
import 'pas_de_tir_modals.dart';

/// Variante Classique : 03 « Reprends ton souffle » puis 04–06 tir, puis 07 résultat.
/// Se ferme avec le [PasDeTirResult] de la série.
class ClassicSessionScreen extends StatefulWidget {
  const ClassicSessionScreen({super.key, this.config = PasDeTirConfig.standard, this.skipBreathing = false});

  final PasDeTirConfig config;
  final bool skipBreathing;

  @override
  State<ClassicSessionScreen> createState() => _ClassicSessionScreenState();
}

class _ClassicSessionScreenState extends State<ClassicSessionScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final ShootingSession _session = ShootingSession(mode: PasDeTirMode.classic, config: widget.config);
  late bool _breathing = !widget.skipBreathing;
  Duration _breathStart = Duration.zero;
  Duration _now = Duration.zero;
  bool _resultShown = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration t) {
    _now = t;
    if (_breathing) {
      setState(() {});
      return;
    }
    setState(() => _session.tick(t - _breathStart));
    if (_session.readyForResult && !_resultShown) {
      _resultShown = true;
      _showResult();
    }
  }

  Future<void> _showResult() async {
    final result = _session.buildResult();
    await showPasDeTirResult(context, result);
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _quit() async {
    if (_resultShown) return;
    // Avant le premier tir, on sort sans marquer le jeu comme joué.
    if (!_session.started) {
      Navigator.pop(context);
      return;
    }
    final quit = await confirmQuitShooting(context, drops: _session.drops);
    if (quit && mounted && !_resultShown) {
      _resultShown = true;
      Navigator.pop(context, _session.buildResult(abandoned: true));
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _quit();
      },
      child: _breathing ? _buildBreathing() : _buildShooting(),
    );
  }

  // ─────────────────────── 03_Classique_Consignes ───────────────────────

  Widget _buildBreathing() {
    final c = widget.config;
    final t = _now.inMicroseconds / 1e6;
    final remaining = c.countdownSeconds - t.floor();
    final ready = remaining <= 0;
    // Le cercle gonfle à l'inspiration et dégonfle à l'expiration, sur le cycle de respiration.
    final breath = 0.5 - 0.5 * math.cos(2 * math.pi * t / (c.breathCycle.inMicroseconds / 1e6));
    final inhaling = math.sin(2 * math.pi * t / (c.breathCycle.inMicroseconds / 1e6)) >= 0;

    return Scaffold(
      backgroundColor: AlpColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            ShootingHeader(
              badge: null,
              chrono: formatChrono(c.timeLimit),
              onClose: _quit,
              translucent: false,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(children: [
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(alignment: Alignment.center, children: [
                      Container(
                        width: 150 + 50 * breath,
                        height: 150 + 50 * breath,
                        decoration: const BoxDecoration(color: Color(0xFFDDEDEE), shape: BoxShape.circle),
                      ),
                      Container(
                        width: 120 + 30 * breath,
                        height: 120 + 30 * breath,
                        decoration: const BoxDecoration(color: Color(0xFFB4E4F0), shape: BoxShape.circle),
                      ),
                      Container(
                        width: 104,
                        height: 104,
                        decoration: const BoxDecoration(color: AlpColors.petrol, shape: BoxShape.circle),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(ready ? 'Go' : '$remaining',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, height: 1.1)),
                          Text(inhaling ? 'Inspire' : 'Expire',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 32),
                  const Text('Reprends ton souffle', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text(
                    "Le viseur bouge au rythme d'une respiration simulée. Tire en fin d'expiration, quand il se stabilise.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AlpColors.textSecondary, fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 22),
                  const _InstructionCard(
                    icon: Icon(Icons.smartphone_outlined, color: AlpColors.petrol),
                    text: TextSpan(text: 'Tiens ton téléphone à deux mains'),
                  ),
                  const _InstructionCard(
                    icon: TargetGlyph(size: 22),
                    text: TextSpan(children: [
                      TextSpan(text: 'Appuie sur '),
                      TextSpan(text: 'Tirer', style: TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: ' quand le viseur est sur la cible'),
                    ]),
                  ),
                  const _InstructionCard(
                    icon: Icon(Icons.air, color: AlpColors.petrol),
                    text: TextSpan(children: [
                      TextSpan(text: 'Suis la jauge '),
                      TextSpan(text: 'Respiration', style: TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: " et tire dans la zone bleue, en fin d'expiration"),
                    ]),
                  ),
                ]),
              ),
            ),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: AlpPrimaryButton(
                label: 'Je suis prêt',
                onPressed: ready
                    ? () => setState(() {
                          _breathing = false;
                          _breathStart = _now;
                        })
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── 04/05/06 Tir classique ───────────────────────

  Widget _buildShooting() {
    final s = _session;
    final c = widget.config;
    final topPadding = MediaQuery.paddingOf(context).top;
    final geom = PlateGeometry(MediaQuery.sizeOf(context).width - 80, targetCount: c.targetCount);
    // La visée et le test de touche se font dans le repère de la plaque.
    final target = geom.targetCenter(s.aimedTarget);
    final reticle = s.showingFeedback ? s.lastShotReticle! : target + s.sway;
    final reticleSize = geom.targetRadius * 4.6;
    final reticleColor = s.showingFeedback ? Colors.white : AlpColors.orange;
    final horizon = topPadding + 140;
    final plateOrigin = Offset(40, horizon + 4);

    void fire() => s.fire(
          reticle: geom.targetCenter(s.activeTarget) + s.sway,
          target: geom.targetCenter(s.activeTarget),
          targetRadius: geom.targetRadius,
        );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(child: CustomPaint(painter: MountainScenePainter(horizon: horizon))),
                Positioned(
                  left: plateOrigin.dx,
                  top: plateOrigin.dy,
                  child: TargetPlate(geometry: geom, shots: s.shots),
                ),
                Positioned(
                  left: plateOrigin.dx + reticle.dx - reticleSize / 2,
                  top: plateOrigin.dy + reticle.dy - reticleSize / 2,
                  child: Reticle(color: reticleColor, size: reticleSize),
                ),
                if (s.showingFeedback && s.lastOutcome != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: plateOrigin.dy + geom.height + 14,
                    child: Center(child: ShotToast(outcome: s.lastOutcome!, drops: c.dropsPerTarget)),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: topPadding,
                  child: ShootingHeader(
                    badge: 'Coup ${math.min(s.shots.length + 1, c.targetCount)}/${c.targetCount}',
                    chrono: formatChrono(s.elapsed),
                    onClose: _quit,
                  ),
                ),
              ],
            ),
          ),
          _ClassicBottomSheet(session: s, onFire: fire),
        ],
      ),
    );
  }
}

class _ClassicBottomSheet extends StatelessWidget {
  const _ClassicBottomSheet({required this.session, required this.onFire});
  final ShootingSession session;
  final VoidCallback onFire;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final c = s.config;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2))],
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Chargeur', style: TextStyle(color: AlpColors.textSecondary, fontSize: 14)),
                const SizedBox(height: 6),
                Magazine(total: c.targetCount, fired: s.shots.length),
              ]),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text('Cibles touchées', style: TextStyle(color: AlpColors.textSecondary, fontSize: 14)),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${s.hits}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  TextSpan(
                      text: '  /${c.targetCount}',
                      style: const TextStyle(fontSize: 16, color: AlpColors.textSecondary)),
                ])),
              ]),
            ],
          ),
          const SizedBox(height: 18),
          BreathGauge(cursor: s.cursor, config: c),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const DropBadge(size: 18),
                  const SizedBox(width: 8),
                  Text('+${s.drops} gouttes', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ]),
                const SizedBox(height: 4),
                const Text('Expire lentement puis tire entre deux respirations',
                    style: TextStyle(color: AlpColors.textSecondary, fontSize: 14)),
              ]),
            ),
            const SizedBox(width: 8),
            ShootButton(onPressed: s.canFire ? onFire : null),
          ]),
        ],
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.icon, required this.text});
  final Widget icon;
  final InlineSpan text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AlpRadii.card)),
      child: Row(children: [
        SizedBox(width: 28, child: Center(child: icon)),
        const SizedBox(width: 12),
        Expanded(child: Text.rich(text, style: const TextStyle(fontSize: 15))),
      ]),
    );
  }
}
