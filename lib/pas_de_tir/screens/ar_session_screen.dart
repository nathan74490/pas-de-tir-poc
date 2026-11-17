import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/alp_tokens.dart';
import '../arcore/arcore.dart';
import '../arcore/homography.dart';
import '../pas_de_tir_config.dart';
import '../pas_de_tir_result.dart';
import '../shooting_session.dart';
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
    final f = _frame;
    final s = _session;
    final corners = f?.corners;
    final homography = corners == null ? null : Homography.rectToQuad(Size(_plate.width, _plate.height), corners);
    final hitFeedback = s != null && s.showingFeedback && (s.lastOutcome?.isHit ?? false);
    final center = Offset(size.width / 2, size.height / 2);

    // Message du toast central (scan / placement), ou de perte de suivi.
    final String? centerHint = f != null && _trackingLostLongEnough
        ? _trackingHint(f.failure)
        : switch (_phase) {
            ArPhase.scanning => 'Bouge lentement ton téléphone…',
            ArPhase.placing when homography == null => 'Lève ton téléphone vers l’horizon',
            _ => null,
          };
    final showFrame = _phase == ArPhase.scanning || (_phase == ArPhase.placing && homography == null);

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
            const Positioned.fill(child: TopScrim()),
            if (_phase != ArPhase.shooting && f != null)
              Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: _PointCloudPainter(f.points))),
              ),
            if (showFrame)
              Positioned(
                left: center.dx - 70,
                top: center.dy - 70,
                child: IgnorePointer(child: SvgPicture.asset(PdtAssets.scanFrame, width: 140, height: 140)),
              ),
            if (homography != null && _phase != ArPhase.scanning)
              Positioned(
                left: 0,
                top: 0,
                child: IgnorePointer(
                  child: Transform(
                    transform: homography.toMatrix4(),
                    child: TargetPlate(
                      geometry: _plate,
                      shots: s?.shots ?? const [],
                      impactOn: hitFeedback ? s.shots.length - 1 : null,
                    ),
                  ),
                ),
              ),
            if (_phase == ArPhase.placing && homography != null && f!.feet != null && !_trackingLostLongEnough)
              Positioned(
                left: 0,
                right: 0,
                top: math.min((f.feet![0].dy + f.feet![1].dy) / 2 + 8, size.height - 260),
                child: const Center(child: DarkToast(text: 'Distance virtuelle 50 m')),
              ),
            if (s != null && _phase == ArPhase.shooting) ..._shootingOverlay(s, homography, size, pad),
            if (centerHint != null)
              Positioned(
                left: 24,
                right: 24,
                top: center.dy - 23.5,
                child: IgnorePointer(
                  child: Center(child: DarkToast(text: centerHint, fontSize: 12)),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: pad.top + 16,
              child: RangeHeader(
                subtitle: 'Réalité augmentée',
                chrono: formatChrono(s?.elapsed ?? Duration.zero),
                onClose: _quit,
              ),
            ),
            if (_phase == ArPhase.scanning) Positioned(left: 0, right: 0, bottom: 0, child: _scanCard(pad)),
            if (_phase == ArPhase.placing)
              Positioned(left: 0, right: 0, bottom: 0, child: _placeCard(pad, homography != null)),
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

  List<Widget> _shootingOverlay(ShootingSession s, Homography? h, Size size, EdgeInsets pad) {
    final c = s.config;
    final anchor = Offset(size.width / 2, size.height * 0.45);

    Offset targetOnScreen(int i) => h?.map(_plate.targetCenter(i)) ?? const Offset(-1e6, -1e6);
    double radiusOnScreen(int i) {
      if (h == null) return 0;
      final center = _plate.targetCenter(i);
      return (h.map(center + Offset(_plate.targetRadius, 0)) - h.map(center)).distance;
    }

    // Viseur proportionné à la cible visée telle qu'elle apparaît à l'écran,
    // dans le rapport de la maquette (viseur 140 pour une cible de 60).
    final targetDiameter = 2 * radiusOnScreen(s.aimedTarget);
    final reticleSize = targetDiameter > 0
        ? (targetDiameter * 140 / 60).clamp(40.0, size.width * 0.8)
        : size.width * 140 / 390;

    final hitFeedback = s.showingFeedback && (s.lastOutcome?.isHit ?? false);
    // Viseur fixe au centre de l'écran ; la visée se fait en bougeant le téléphone.
    final reticle = hitFeedback ? targetOnScreen(s.aimedTarget) : anchor + s.sway;
    // Toast de tir au-dessus de la rangée de cibles.
    final toastTop = h == null ? anchor.dy - reticleSize : h.map(Offset(_plate.width / 2, 0)).dy - 52;

    void fire() {
      final i = s.activeTarget;
      s.fire(
        reticle: anchor + s.sway,
        target: targetOnScreen(i),
        // Tolérance : le viseur « recouvre » la cible (min. 14 px à l'écran).
        targetRadius: math.max(radiusOnScreen(i) * 1.3, 14),
      );
    }

    return [
      Positioned(
        left: reticle.dx - reticleSize / 2,
        top: reticle.dy - reticleSize / 2,
        child: Reticle(size: reticleSize, pulse: hitFeedback ? s.feedbackProgress : null),
      ),
      if (s.showingFeedback && s.lastOutcome != null)
        Positioned(
          left: 0,
          right: 0,
          top: toastTop.clamp(pad.top + 210, size.height - 300),
          child: Center(child: ShotToast(outcome: s.lastOutcome!, drops: c.dropsPerTarget)),
        ),
      if (!s.started)
        Positioned(
          left: 24,
          right: 24,
          top: size.height / 2 + 180,
          child: const IgnorePointer(child: Center(child: DarkToast(text: 'Bouge ton téléphone pour viser.'))),
        ),
      Positioned(left: 16, right: 16, top: pad.top + 82, child: RangeStatsBar(session: s)),
      Positioned(left: 16, right: 16, top: pad.top + 148, child: MagazineAndHits(session: s)),
      Positioned(
        left: 0,
        right: 0,
        bottom: pad.bottom + 28,
        child: ShootDock(onFire: s.canFire ? fire : null),
      ),
    ];
  }

  /// Carte blanche du bas (scan et placement).
  Widget _card(EdgeInsets pad, List<Widget> children) => Padding(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 20 + pad.bottom),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );

  Widget _cardTitle(String icon, String title, String subtitle) => Row(
    children: [
      Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF66A0B0), width: 3),
        ),
        child: SvgPicture.asset(icon, width: 24, height: 24),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 20 / 14)),
            Text(subtitle, style: const TextStyle(color: AlpColors.textSecondary, fontSize: 12, height: 1.4)),
          ],
        ),
      ),
    ],
  );

  // ─────────────────────────── 09_AR_Calibrage ───────────────────────────

  Widget _scanCard(EdgeInsets pad) {
    final pct = (_scanProgress * 100).round();
    const label = TextStyle(fontWeight: FontWeight.w600, fontSize: 12, height: 20 / 12);
    return _card(pad, [
      _cardTitle(
        PdtAssets.cornersOut,
        'Scanne le sol',
        'Balaye lentement le terrain devant toi, téléphone à hauteur de poitrine, bras tendus.',
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          const Expanded(child: Text('Préparation de ta cible', style: label)),
          Text('$pct %', style: label),
        ],
      ),
      const SizedBox(height: 4),
      RangeProgress(value: _scanProgress),
    ]);
  }

  // ─────────────────────────── 10_AR_Placement ───────────────────────────

  Widget _placeCard(EdgeInsets pad, bool plateVisible) {
    return _card(pad, [
      _cardTitle(
        PdtAssets.checkCircle,
        'Surface détectée',
        plateVisible
            ? 'Les cibles sont à la même distance pour tous. Tourne-toi vers une zone dégagée, puis valide.'
            : 'Lève ton téléphone vers l’horizon pour faire apparaître les cibles.',
      ),
      const SizedBox(height: 12),
      SheetButton(
        label: 'Placer les cibles',
        onPressed: plateVisible && !_awaitingAnchor
            ? () {
                setState(() => _awaitingAnchor = true);
                ArCore.confirmPlacement();
              }
            : null,
      ),
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
