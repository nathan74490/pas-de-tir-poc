import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/alp_tokens.dart';
import '../../widgets/alp_common.dart';
import '../arcore/arcore.dart';
import '../arcore/homography.dart';
import '../pas_de_tir_config.dart';
import '../pas_de_tir_result.dart';
import '../shooting_session.dart';
import '../widgets/scenes.dart';
import '../widgets/shooting_widgets.dart';
import 'pas_de_tir_modals.dart';

enum ArPhase { scanning, placing, shooting }

/// Variante AR (ARCore) : 09 scan du sol → 10 placement → 11–13 tir → 14 résultat.
///
/// ARCore (natif) suit le téléphone en 6DoF, détecte les plans horizontaux et
/// ancre la plaque au sol ; Flutter dessine la plaque en perspective à partir
/// de ses coins projetés à l'écran.
class ArSessionScreen extends StatefulWidget {
  const ArSessionScreen({super.key, this.config = PasDeTirConfig.ar});

  final PasDeTirConfig config;

  @override
  State<ArSessionScreen> createState() => _ArSessionScreenState();
}

class _ArSessionScreenState extends State<ArSessionScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Surface de sol à détecter pour terminer le scan (m²).
  static const _scanTargetArea = 0.6;

  /// Taille logique dans laquelle la plaque est dessinée avant la perspective.
  static const _plate = PlateGeometry(240);

  late final Ticker _ticker;
  StreamSubscription<ArFrame>? _frames;
  ArFrame? _frame;
  ArPhase _phase = ArPhase.scanning;
  double _scanProgress = 0;
  bool _awaitingAnchor = false;
  Duration _now = Duration.zero;
  Duration _phaseStart = Duration.zero;
  ShootingSession? _session;
  bool _finishing = false;

  /// Début de la perte de suivi en cours (le message n'apparaît qu'après 1 s).
  DateTime? _notTrackingSince;

  /// Clé de la vue native : changée pour recréer la session ARCore au retour
  /// de veille (le contexte GL de la caméra est perdu).
  Key _viewKey = UniqueKey();
  bool _wasPaused = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _wasPaused = true;
    if (state == AppLifecycleState.resumed && _wasPaused && !_finishing) {
      // Nouvelle session ARCore : on rescanne et on replace la plaque ;
      // une série en cours reprend là où elle en était.
      setState(() {
        _wasPaused = false;
        _viewKey = UniqueKey();
        _frame = null;
        _phase = ArPhase.scanning;
        _scanProgress = 0;
        _awaitingAnchor = false;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _frames ??= ArCore.frames(MediaQuery.devicePixelRatioOf(context)).listen(
      _onFrame,
      onError: (Object _) {
        if (mounted && !_finishing) Navigator.pop(context, const ClassicFallbackSignal());
      },
    );
  }

  void _onFrame(ArFrame f) {
    _frame = f;
    _notTrackingSince = f.tracking ? null : (_notTrackingSince ?? DateTime.now());
    switch (_phase) {
      case ArPhase.scanning:
        _scanProgress = math.max(_scanProgress, (f.planeArea / _scanTargetArea).clamp(0.0, 1.0));
        if (_scanProgress >= 1) {
          _phase = ArPhase.placing;
          ArCore.setMode(ArMode.placing);
        }
      case ArPhase.placing:
        if (_awaitingAnchor && f.mode == ArMode.anchored) {
          _awaitingAnchor = false;
          _startShooting();
        }
      case ArPhase.shooting:
        break;
    }
  }

  void _onTick(Duration t) {
    _now = t;
    final s = _session;
    if (s != null) {
      s.tick(t - _phaseStart);
      if (s.readyForResult && !_finishing) _finish();
    }
    setState(() {});
  }

  void _startShooting() {
    if (_session == null) {
      _session = ShootingSession(mode: PasDeTirMode.ar, config: widget.config);
      _phaseStart = _now;
    }
    _phase = ArPhase.shooting;
  }

  Future<void> _finish() async {
    _finishing = true;
    String? capture;
    try {
      capture = await ArCore.capture();
    } catch (_) {}
    if (!mounted) return;
    final result = _session!.buildResult(capturePath: capture);
    await showPasDeTirResult(context, result);
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _quit() async {
    if (_finishing) return;
    final s = _session;
    if (s == null || !s.started) {
      Navigator.pop(context);
      return;
    }
    final quit = await confirmQuitShooting(context, drops: s.drops);
    if (quit && mounted && !_finishing) {
      _finishing = true;
      Navigator.pop(context, s.buildResult(abandoned: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frames?.cancel();
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final c = widget.config;
    final f = _frame;
    final s = _session;
    final corners = f?.corners;
    final homography =
        corners == null ? null : Homography.rectToQuad(Size(_plate.width, _plate.height), corners);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _quit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(child: ArCoreCameraView(key: _viewKey)),
            if (_phase != ArPhase.shooting && f != null)
              Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: _PointCloudPainter(f.points))),
              ),
            if (_phase == ArPhase.scanning)
              Positioned(
                left: size.width / 2 - 50,
                top: size.height * 0.62 - 50,
                child: CustomPaint(size: const Size(100, 100), painter: ScanFramePainter()),
              ),
            if (homography != null && _phase != ArPhase.scanning) ...[
              Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: _LegsPainter(homography, f!.feet, _plate))),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: IgnorePointer(
                  child: Transform(
                    transform: homography.toMatrix4(),
                    child: TargetPlate(geometry: _plate, shots: s?.shots ?? const []),
                  ),
                ),
              ),
            ],
            if (_phase == ArPhase.placing && homography != null && f!.feet != null)
              Positioned(
                left: 0,
                right: 0,
                top: math.min((f.feet![0].dy + f.feet![1].dy) / 2 + 14, size.height - 240),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                        color: AlpColors.petrol.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(20)),
                    child: const Text('Distance virtuelle · 50 m',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            // Glisser pour ajuster la position de la plaque sur le sol.
            if (_phase == ArPhase.placing)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanDown: (d) => ArCore.setPlacementPoint(d.localPosition * dpr),
                  onPanUpdate: (d) => ArCore.setPlacementPoint(d.localPosition * dpr),
                ),
              ),
            if (s != null && _phase == ArPhase.shooting) ..._shootingOverlay(s, homography, size),
            Positioned(
              left: 0,
              right: 0,
              top: pad.top,
              child: ShootingHeader(
                badge: s == null
                    ? 'Réalité augmentée'
                    : 'Coup ${math.min(s.shots.length + 1, c.targetCount)}/${c.targetCount}',
                chrono: s == null ? formatChrono(c.timeLimit) : formatChrono(s.elapsed),
                onClose: _quit,
              ),
            ),
            if (f != null && _trackingLostLongEnough)
              Positioned(
                left: 24,
                right: 24,
                top: pad.top + 140,
                child: Center(
                  child: PillToast(
                    child: Text(_trackingHint(f.failure),
                        textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            if (_phase == ArPhase.scanning) Positioned(left: 0, right: 0, bottom: 0, child: _scanSheet(pad)),
            if (_phase == ArPhase.placing)
              Positioned(left: 0, right: 0, bottom: 0, child: _placeSheet(pad, homography != null)),
          ],
        ),
      ),
    );
  }

  bool get _trackingLostLongEnough {
    final since = _notTrackingSince;
    return since != null && DateTime.now().difference(since) > const Duration(seconds: 1);
  }

  String _trackingHint(String failure) => switch (failure) {
        'INSUFFICIENT_LIGHT' => 'Pas assez de lumière',
        'EXCESSIVE_MOTION' => 'Bouge plus lentement',
        'INSUFFICIENT_FEATURES' => 'Vise une zone plus texturée',
        'CAMERA_UNAVAILABLE' => 'Caméra indisponible',
        _ => 'Bouge lentement ton téléphone…',
      };

  List<Widget> _shootingOverlay(ShootingSession s, Homography? h, Size size) {
    final c = s.config;
    final pad = MediaQuery.paddingOf(context);
    // Même taille que le viseur du mode Gyroscope (~12,5 % de la largeur d'écran).
    final reticleSize = size.width * 0.125;
    final anchor = Offset(size.width / 2, size.height * 0.45);

    Offset targetOnScreen(int i) => h?.map(_plate.targetCenter(i)) ?? const Offset(-1e6, -1e6);
    double radiusOnScreen(int i) {
      if (h == null) return 0;
      final center = _plate.targetCenter(i);
      return (h.map(center + Offset(_plate.targetRadius, 0)) - h.map(center)).distance;
    }

    final hitFeedback = s.showingFeedback && (s.lastOutcome?.isHit ?? false);
    // Réticule fixe au centre de l'écran ; la visée se fait en bougeant le téléphone.
    final reticle = hitFeedback ? targetOnScreen(s.aimedTarget) : anchor + s.sway;

    void fire() {
      final i = s.activeTarget;
      s.fire(
        reticle: anchor + s.sway,
        target: targetOnScreen(i),
        // Tolérance : le réticule « recouvre » la cible (min. 14 px à l'écran).
        targetRadius: math.max(radiusOnScreen(i) * 1.5, 14),
      );
    }

    return [
      Positioned(
        left: reticle.dx - reticleSize / 2,
        top: reticle.dy - reticleSize / 2,
        child: Reticle(
          color: hitFeedback ? AlpColors.cyan : Colors.white,
          size: reticleSize,
          pulse: hitFeedback ? s.feedbackProgress : null,
        ),
      ),
      if (s.showingFeedback && s.lastOutcome != null)
        Positioned(
          left: 0,
          right: 0,
          top: anchor.dy + reticleSize * 0.75,
          child: Center(child: ShotToast(outcome: s.lastOutcome!, drops: c.dropsPerTarget)),
        ),
      ...floatingShootingHud(s, pad, onFire: fire),
    ];
  }

  Widget _sheet(EdgeInsets pad, List<Widget> children) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + pad.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  // ─────────────────────────── 09_AR_Calibrage ───────────────────────────

  Widget _scanSheet(EdgeInsets pad) {
    final pct = (_scanProgress * 100).round();
    return _sheet(pad, [
      const Row(children: [
        GameIconBadge(size: 44, child: TargetGlyph(size: 22)),
        SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Scanne le sol', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text('Balaye lentement le terrain devant toi',
                style: TextStyle(color: AlpColors.textSecondary, fontSize: 14)),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        const Text('Détection de surface', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const Spacer(),
        Text('$pct %', style: const TextStyle(color: AlpColors.petrol, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: _scanProgress,
          minHeight: 8,
          color: AlpColors.cyan,
          backgroundColor: const Color(0xFFECEAE4),
        ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AlpColors.cream, borderRadius: BorderRadius.circular(AlpRadii.button)),
        child: const Row(children: [
          Icon(Icons.smartphone_outlined, color: AlpColors.textSecondary, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text('Garde ton téléphone à hauteur de poitrine, bras tendus',
                style: TextStyle(color: AlpColors.textSecondary, fontSize: 14)),
          ),
        ]),
      ),
    ]);
  }

  // ─────────────────────────── 10_AR_Placement ───────────────────────────

  Widget _placeSheet(EdgeInsets pad, bool plateVisible) {
    return _sheet(pad, [
      Row(children: [
        const PetrolDisc(icon: Icons.check_rounded, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Surface détectée', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text(
              plateVisible
                  ? "Fais glisser la plaque pour l'ajuster, puis valide"
                  : 'Vise le sol détecté pour y poser la plaque',
              style: const TextStyle(color: AlpColors.textSecondary, fontSize: 14),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          flex: 2,
          child: AlpSecondaryButton(label: 'Replacer', onPressed: () => ArCore.setPlacementPoint(null)),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: AlpPrimaryButton(
            label: 'Placer les cibles',
            onPressed: plateVisible && !_awaitingAnchor
                ? () {
                    setState(() => _awaitingAnchor = true);
                    ArCore.confirmPlacement();
                  }
                : null,
          ),
        ),
      ]),
    ]);
  }
}

/// Points caractéristiques détectés par ARCore.
class _PointCloudPainter extends CustomPainter {
  _PointCloudPainter(this.points);
  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (final p in points) {
      canvas.drawCircle(p, 2.6, paint);
    }
  }

  @override
  bool shouldRepaint(_PointCloudPainter old) => !identical(old.points, points);
}

/// Pieds de la plaque et ombre au sol, en perspective.
class _LegsPainter extends CustomPainter {
  _LegsPainter(this.h, this.feet, this.plate);
  final Homography h;
  final List<Offset>? feet;
  final PlateGeometry plate;

  @override
  void paint(Canvas canvas, Size size) {
    final f = feet;
    if (f == null) return;
    final width = (h.map(Offset(plate.width, 0)) - h.map(Offset.zero)).distance;
    final shadowCenter = Offset.lerp(f[0], f[1], 0.5)!;
    canvas.drawOval(
      Rect.fromCenter(center: shadowCenter, width: (f[1] - f[0]).distance * 1.15, height: width * 0.07),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    final leg = Paint()
      ..color = const Color(0xFF4A4A4A)
      ..strokeWidth = math.max(2, width * 0.028);
    canvas.drawLine(h.map(Offset(plate.width * 0.08, plate.height)), f[0], leg);
    canvas.drawLine(h.map(Offset(plate.width * 0.90, plate.height)), f[1], leg);
  }

  @override
  bool shouldRepaint(_LegsPainter old) => true;
}
