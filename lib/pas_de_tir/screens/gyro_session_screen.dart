import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../gyro/gyro.dart';
import '../pas_de_tir_config.dart';
import '../pas_de_tir_result.dart';
import '../shooting_session.dart';
import '../widgets/shooting_widgets.dart';
import 'pas_de_tir_modals.dart';

/// Variante Gyroscope, pour les appareils sans ARCore : le téléphone sert de
/// carabine. Sa rotation (gyroscope) fait défiler un décor panoramique où se
/// trouve la plaque ; le réticule reste fixe au centre et ne suit que le téléphone.
///
/// Avec [useCamera], le décor est l'image de la caméra arrière : la plaque est
/// ancrée par le gyroscope dans la direction visée au calibrage et se déplace à
/// l'écran comme un objet réel (sans ARCore, donc sans détection du sol).
///
/// Calibrage (la plaque se place dans la direction visée, à l'horizon) → tir → résultat.
class GyroSessionScreen extends StatefulWidget {
  const GyroSessionScreen({super.key, this.config = PasDeTirConfig.gyro, this.useCamera = false});

  final PasDeTirConfig config;
  final bool useCamera;

  @override
  State<GyroSessionScreen> createState() => _GyroSessionScreenState();
}

class _GyroSessionScreenState extends State<GyroSessionScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Sensibilité : déplacement du décor (px logiques) par radian de rotation.
  /// À 800, passer d'une cible à la suivante demande environ 3°.
  static const _pixelsPerRadian = 800.0;

  /// Champ de vision de la caméra arrière sur son grand côté (vertical en
  /// portrait). Sert à faire bouger la plaque à la même vitesse que l'image
  /// caméra. ~68° pour un capteur principal 26 mm équivalent (Galaxy A54) ;
  /// à ajuster si la plaque « glisse » par rapport au décor réel.
  static const _cameraLongSideFov = 68 * math.pi / 180;

  /// Sans données capteur passé ce délai, on bascule en Classique.
  static const _sensorTimeout = Duration(seconds: 2);

  /// Photo du stade de biathlon servant de décor.
  static const _backdrop = AssetImage('assets/images/gyro_range.jpg');
  static const _backdropSize = Size(2212, 1659);

  /// Point de fuite de la photo (fraction de sa taille) : le pied des
  /// banderoles au bout du pas de tir. La plaque y est posée.
  static const _backdropHorizon = Offset(0.533, 0.50);

  /// Largeur de la rangée de cibles, en fraction de la largeur d'écran
  /// (maquette : 356 px sur 390). Plus petit = cibles plus lointaines (et plus
  /// dures à toucher).
  static const _plateWidthFraction = 356 / 390;

  /// Au-delà de cette inclinaison vers le sol (rad, ~35°), on demande de lever
  /// le téléphone avant de pouvoir calibrer.
  static const _maxCalibrationTilt = 0.6;

  late final Ticker _ticker;
  late final StreamSubscription<List<double>> _rotations;
  List<double>? _rotation;
  List<double>? _reference;
  bool _calibrated = false;
  ShootingSession? _session;
  Duration _now = Duration.zero;
  Duration _shootStart = Duration.zero;
  bool _finishing = false;

  /// Caméra arrière (mode [GyroSessionScreen.useCamera]).
  CameraController? _camera;
  bool _cameraStarting = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    if (widget.useCamera) {
      WidgetsBinding.instance.addObserver(this);
      _startCamera();
    }
    _rotations = Gyro.rotations().listen(
      (m) {
        _rotation = m;
        _reference ??= aimReference(m);
      },
      onError: (Object _) => _fallback(),
    );
  }

  Future<void> _startCamera() async {
    if (_cameraStarting || _camera != null) return;
    _cameraStarting = true;
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (_) {
      // Caméra refusée ou indisponible : repli en Classique, comme pour le gyroscope.
      _fallback();
    } finally {
      _cameraStarting = false;
    }
  }

  Future<void> _stopCamera() async {
    final controller = _camera;
    if (controller == null) return;
    setState(() => _camera = null);
    await controller.dispose();
  }

  /// La caméra est libérée en arrière-plan et relancée au retour.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed && !_finishing) {
      _startCamera();
    }
  }

  void _onTick(Duration t) {
    _now = t;
    if (_rotation == null && t > _sensorTimeout) return _fallback();
    final s = _session;
    if (s != null) {
      s.tick(t - _shootStart);
      if (s.readyForResult && !_finishing) _finish();
    }
    setState(() {});
  }

  void _fallback() {
    if (_finishing || !mounted) return;
    _finishing = true;
    Navigator.pop(context, const ClassicFallbackSignal());
  }

  /// La plaque se replace droit devant, dans la direction où pointe le téléphone,
  /// à son inclinaison actuelle : le joueur vise sans avoir à lever le téléphone.
  void _recenter() {
    final r = _rotation;
    if (r != null) _reference = aimReference(r);
  }

  void _calibrate() {
    _recenter();
    HapticFeedback.selectionClick();
    setState(() => _calibrated = true);
  }

  /// Focale de l'aperçu caméra affiché en plein écran (px logiques par
  /// unité de tangente). L'aperçu couvre l'écran : son grand côté (vertical en
  /// portrait) peut dépasser la hauteur d'écran.
  double _cameraFocal(Size screen, CameraController? camera) {
    final preview = camera?.value.previewSize;
    final ratio = preview == null ? 4 / 3 : preview.longestSide / preview.shortestSide;
    final displayedLong = math.max(screen.height, screen.width * ratio);
    return displayedLong / 2 / math.tan(_cameraLongSideFov / 2);
  }

  /// Inclinaison du téléphone par rapport à l'horizontale (rad, < 0 = vers le sol).
  double get _tilt {
    final r = _rotation;
    return r == null ? 0 : aimAngles(levelReference(r), r).dy;
  }

  void _start() {
    setState(() {
      _session = ShootingSession(
        mode: widget.useCamera ? PasDeTirMode.gyroCamera : PasDeTirMode.gyro,
        config: widget.config,
      );
      _shootStart = _now;
    });
  }

  Future<void> _finish() async {
    _finishing = true;
    final result = _session!.buildResult();
    await showPasDeTirResult(context, result);
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _quit() async {
    if (_finishing) return;
    final s = _session;
    if (s == null || !s.started) {
      _finishing = true;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.useCamera) precacheImage(_backdrop, context);
  }

  @override
  void dispose() {
    if (widget.useCamera) WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _ticker.dispose();
    _rotations.cancel();
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final c = widget.config;
    final s = _session;

    // Monde : origine = point visé au calibrage, où est centrée la rangée de cibles.
    final geom = PlateGeometry(size.width * _plateWidthFraction, targetCount: c.targetCount);
    final plateTopLeft = Offset(-geom.width / 2, -geom.targetCenter(0).dy);
    // Centre des cibles sur le point de fuite de la photo : elles se tiennent au
    // fond de la piste, au pied des banderoles.
    final horizon = plateTopLeft.dy + geom.targetCenter(0).dy;
    // Viseur au milieu de l'écran, comme sur la maquette (cibles à 50 % - 29 px).
    final anchor = Offset(size.width / 2, size.height / 2 - 29);

    // Photo à l'échelle : assez large pour ~4 écrans de balayage et assez
    // haute pour viser au-dessus et en dessous de l'horizon.
    final scale = math.max(size.width * 4 / _backdropSize.width, size.height * 1.6 / _backdropSize.height);
    final sceneSize = _backdropSize * scale;
    // Coin haut-gauche de la photo dans le monde : son point de fuite sur l'horizon.
    final sceneTopLeft = Offset(
      -sceneSize.width * _backdropHorizon.dx,
      horizon - sceneSize.height * _backdropHorizon.dy,
    );

    final rotation = _rotation, reference = _reference;
    var aim = Offset.zero;
    final camera = _camera;
    final cameraReady = camera != null && camera.value.isInitialized;
    if (widget.useCamera) {
      // Décor réel : la plaque doit tourner à la même vitesse que l'image
      // caméra, soit la focale de l'aperçu affiché (en px logiques).
      if (rotation != null && reference != null) {
        final a = aimAngles(reference, rotation);
        final focal = _cameraFocal(size, camera);
        // Au-delà de ~80°, la plaque est de toute façon hors champ.
        double project(double angle) => focal * math.tan(angle.clamp(-1.4, 1.4));
        aim = Offset(project(a.dx), -project(a.dy));
      }
    } else if (rotation != null && reference != null) {
      // Visée en px de monde, bornée pour que l'écran reste toujours dans la photo.
      final a = aimAngles(reference, rotation);
      final minX = sceneTopLeft.dx + anchor.dx;
      final maxX = sceneTopLeft.dx + sceneSize.width - (size.width - anchor.dx);
      final minY = sceneTopLeft.dy + anchor.dy;
      final maxY = sceneTopLeft.dy + sceneSize.height - (size.height - anchor.dy);
      aim = Offset(
        (a.dx * _pixelsPerRadian).clamp(minX, maxX),
        (-a.dy * _pixelsPerRadian).clamp(minY, math.max(minY, maxY)),
      );
    }

    Offset toScreen(Offset world) => anchor + world - aim;
    final sceneOrigin = toScreen(sceneTopLeft);
    final plateOrigin = toScreen(plateTopLeft);
    final hitFeedback = s != null && s.showingFeedback && (s.lastOutcome?.isHit ?? false);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _quit();
      },
      child: Scaffold(
        // Bleu du ciel de la photo le temps qu'elle se charge ; noir sous la caméra.
        backgroundColor: widget.useCamera ? Colors.black : const Color(0xFF2F5FA8),
        body: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (widget.useCamera)
              Positioned.fill(child: cameraReady ? _CameraBackdrop(camera) : const SizedBox())
            else
              Positioned(
                left: sceneOrigin.dx,
                top: sceneOrigin.dy,
                width: sceneSize.width,
                height: sceneSize.height,
                child: const RepaintBoundary(
                  child: Image(image: _backdrop, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                ),
              ),
            Positioned(
              left: plateOrigin.dx,
              top: plateOrigin.dy,
              child: TargetPlate(
                geometry: geom,
                shots: s?.shots ?? const [],
                impactOn: hitFeedback ? s.shots.length - 1 : null,
              ),
            ),
            // Lisibilité du header : décor clair (neige) ou image caméra, comme en AR.
            Positioned.fill(child: TopScrim(soft: !widget.useCamera)),
            if (s == null) ...[
              Positioned(
                left: anchor.dx - geom.reticleSize / 2,
                top: anchor.dy - geom.reticleSize / 2,
                child: Reticle(size: geom.reticleSize),
              ),
              Positioned(left: 0, right: 0, bottom: 0, child: _calibrationPanel()),
            ] else
              ..._shootingOverlay(s, geom, anchor, plateOrigin, pad),
            Positioned(
              left: 0,
              right: 0,
              top: pad.top + 16,
              child: RangeHeader(
                subtitle: widget.useCamera ? 'Gyroscope + caméra' : 'Mode gyroscope',
                chrono: formatChrono(s?.elapsed ?? Duration.zero),
                onClose: _quit,
                back: s == null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _shootingOverlay(
    ShootingSession s,
    PlateGeometry geom,
    Offset anchor,
    Offset plateOrigin,
    EdgeInsets pad,
  ) {
    final c = s.config;
    final reticleSize = geom.reticleSize;
    final hitFeedback = s.showingFeedback && (s.lastOutcome?.isHit ?? false);
    // Viseur au centre de l'écran, avec un léger tremblement simulé.
    final reticle = hitFeedback ? anchor : anchor + s.sway;
    final targetsTop = plateOrigin.dy + geom.targetCenter(0).dy - geom.targetRadius;

    void fire() => s.fire(
      reticle: anchor + s.sway,
      target: plateOrigin + geom.targetCenter(s.activeTarget),
      // Légère tolérance : le viseur « recouvre » la cible.
      targetRadius: geom.targetRadius * 1.3,
    );

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
          top: targetsTop - 69,
          child: Center(child: ShotToast(outcome: s.lastOutcome!, drops: c.dropsPerTarget)),
        ),
      Positioned(left: 16, right: 16, top: pad.top + 82, child: RangeStatsBar(session: s)),
      Positioned(left: 16, right: 16, top: pad.top + 148, child: MagazineAndHits(session: s)),
      Positioned(
        left: 0,
        right: 0,
        bottom: pad.bottom + 28,
        child: ShootDock(
          onFire: s.canFire ? fire : null,
          // Recentrer : corrige la dérive lente du gyroscope.
          trailing: RecenterButton(onPressed: _recenter),
        ),
      ),
    ];
  }

  Widget _calibrationPanel() {
    final tooLow = _tilt < -_maxCalibrationTilt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const RangeStepCard(
                leading: StepNumber(1),
                text: 'Ton téléphone est ta carabine : tourne-toi et incline-le pour viser',
                done: true,
              ),
              const SizedBox(height: 8),
              RangeStepCard(
                leading: const StepNumber(2),
                text: tooLow
                    ? 'Lève ton téléphone : tiens-le droit devant toi, à hauteur des yeux'
                    : 'Tiens ton téléphone droit devant toi',
                done: _rotation != null && !tooLow,
              ),
              const SizedBox(height: 8),
              RangeStepCard(
                leading: const StepNumber(3),
                text: _calibrated
                    ? 'Téléphone calibré : la plaque est devant toi'
                    : 'Appuie sur « Calibrer » pour placer la plaque devant toi',
                done: _calibrated,
              ),
            ],
          ),
        ),
        BottomActionSheet(
          child: Row(
            children: [
              Expanded(
                child: SheetButton(
                  label: _calibrated ? 'Recalibrer' : 'Calibrer',
                  primary: false,
                  onPressed: _rotation == null || tooLow ? null : _calibrate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SheetButton(label: 'Je suis prêt', onPressed: _calibrated ? _start : null),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Aperçu de la caméra arrière, recadré pour couvrir tout l'écran (portrait).
class _CameraBackdrop extends StatelessWidget {
  const _CameraBackdrop(this.camera);
  final CameraController camera;

  @override
  Widget build(BuildContext context) {
    final preview = camera.value.previewSize!;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: preview.shortestSide,
          height: preview.longestSide,
          child: CameraPreview(camera),
        ),
      ),
    );
  }
}
