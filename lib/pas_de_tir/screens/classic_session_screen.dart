import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../pas_de_tir_config.dart';
import '../pas_de_tir_result.dart';
import '../shooting_session.dart';
import '../widgets/shooting_widgets.dart';
import 'pas_de_tir_modals.dart';

/// Variante Classique : 03 « Contrôle ta respiration » puis 04–06 tir, puis 07 résultat.
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
  late bool _briefing = !widget.skipBreathing;
  Duration _shootStart = Duration.zero;
  Duration _now = Duration.zero;
  bool _resultShown = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration t) {
    _now = t;
    if (_briefing) return;
    setState(() => _session.tick(t - _shootStart));
    if (_session.readyForResult && !_resultShown) {
      _resultShown = true;
      _showResult();
    }
  }

  void _startShooting() => setState(() {
    _briefing = false;
    _shootStart = _now;
  });

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
      child: _briefing ? _buildBriefing() : _buildShooting(),
    );
  }

  // ─────────────────────── 03_Classique_Consignes ───────────────────────

  Widget _buildBriefing() {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned(left: 0, right: 0, top: size.height * 0.186, height: size.height * 0.2635, child: const MountainBackdrop()),
          Positioned.fill(
            child: Column(
              children: [
                SizedBox(height: pad.top + 16),
                RangeHeader(subtitle: 'Mode classique', onClose: _quit, light: false, back: true),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 21),
                    child: Column(
                      children: [
                        const Reticle(size: 140),
                        const SizedBox(height: 24),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Contrôle ta respiration',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 32 / 28),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            "Le viseur suit une respiration simulée.\nTire en fin d'expiration, quand il se stabilise.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 20 / 12,
                              color: Color(0x99000000),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _BriefingStep(image: PdtAssets.iconPhone, text: 'Tiens ton téléphone à deux mains'),
                              const SizedBox(height: 8),
                              _BriefingStep(
                                image: PdtAssets.iconTarget,
                                text: 'Appuie sur Tirer quand le viseur est sur la cible',
                              ),
                              const SizedBox(height: 8),
                              _BriefingStep(
                                image: PdtAssets.iconWind,
                                text: "Suis la jauge de respiration et tire dans la zone bleue, en fin d'expiration",
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                BottomActionSheet(
                  child: SheetButton(label: 'Je suis prêt', onPressed: _startShooting),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── 04/05/06 Tir classique ───────────────────────

  Widget _buildShooting() {
    final s = _session;
    final c = widget.config;
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final geom = PlateGeometry(size.width - 34, targetCount: c.targetCount);
    // Cibles centrées à 50 % - 29 px, comme sur la maquette.
    final plateOrigin = Offset(17, size.height / 2 - 29 - geom.height / 2);
    final targetsTop = plateOrigin.dy + geom.targetCenter(0).dy - geom.targetRadius;
    // La visée et le test de touche se font dans le repère de la plaque.
    final target = geom.targetCenter(s.aimedTarget);
    final reticle = s.showingFeedback ? s.lastShotReticle! : target + s.sway;
    final reticleSize = geom.reticleSize;
    final hitFeedback = s.showingFeedback && (s.lastOutcome?.isHit ?? false);
    final dockBottom = pad.bottom + 28;

    void fire() => s.fire(
      reticle: geom.targetCenter(s.activeTarget) + s.sway,
      target: geom.targetCenter(s.activeTarget),
      targetRadius: geom.targetRadius,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: size.height * 0.2998,
            height: size.height * 0.2867,
            child: const MountainBackdrop(),
          ),
          Positioned(
            left: plateOrigin.dx,
            top: plateOrigin.dy,
            child: TargetPlate(
              geometry: geom,
              shots: s.shots,
              impactOn: hitFeedback ? s.shots.length - 1 : null,
            ),
          ),
          Positioned(
            left: plateOrigin.dx + reticle.dx - reticleSize / 2,
            top: plateOrigin.dy + reticle.dy - reticleSize / 2,
            child: Reticle(size: reticleSize, pulse: hitFeedback ? s.feedbackProgress : null),
          ),
          if (s.showingFeedback && s.lastOutcome != null)
            Positioned(
              left: 0,
              right: 0,
              top: targetsTop - 69,
              child: Center(child: ShotToast(outcome: s.lastOutcome!, drops: c.dropsPerTarget)),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: pad.top + 16,
            child: RangeHeader(
              subtitle: 'Mode classique',
              chrono: formatChrono(s.elapsed),
              onClose: _quit,
              light: false,
            ),
          ),
          Positioned(left: 16, right: 16, top: pad.top + 90, child: RangeStatsBar(session: s, onScenery: false)),
          Positioned(left: 16, right: 16, top: pad.top + 148, child: MagazineAndHits(session: s)),
          // Jauge de respiration, juste au-dessus du bouton Tirer.
          Positioned(
            left: size.width * 55 / 390,
            right: size.width * 54 / 390,
            bottom: dockBottom + 112 + 21,
            child: BreathMeter(cursor: s.cursor, config: c),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: dockBottom,
            child: ShootDock(onFire: s.canFire ? fire : null),
          ),
        ],
      ),
    );
  }
}

/// Consigne illustrée (icône 3D) de l'écran « Contrôle ta respiration ».
class _BriefingStep extends StatelessWidget {
  const _BriefingStep({required this.image, required this.text});
  final String image;
  final String text;

  @override
  Widget build(BuildContext context) {
    return RangeStepCard(
      leading: SizedBox.square(dimension: 36, child: Image.asset(image, fit: BoxFit.contain)),
      text: text,
    );
  }
}
