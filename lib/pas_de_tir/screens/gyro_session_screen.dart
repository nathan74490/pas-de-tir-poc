import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../theme/alp_tokens.dart';
import '../../widgets/alp_common.dart';
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
/// Calibrage (la plaque se place dans la direction visée, à l'horizon) → tir → résultat.
class GyroSessionScreen extends StatefulWidget {
  const GyroSessionScreen({super.key, this.config = PasDeTirConfig.gyro});

  final PasDeTirConfig config;

  @override
  State<GyroSessionScreen> createState() => _GyroSessionScreenState();
}

class _GyroSessionScreenState extends State<GyroSessionScreen> with SingleTickerProviderStateMixin {
  /// Sensibilité : déplacement du décor (px logiques) par radian de rotation.
  /// À 800, passer d'une cible à la suivante demande environ 3°.
  static const _pixelsPerRadian = 800.0;

  /// Sans données capteur passé ce délai, on bascule en Classique.
  static const _sensorTimeout = Duration(seconds: 2);

  /// Photo du stade de biathlon servant de décor.
  static const _backdrop = AssetImage('assets/images/gyro_range.jpg');
  static const _backdropSize = Size(2212, 1659);

  /// Point de fuite de la photo (fraction de sa taille) : le pied des
  /// banderoles au bout du pas de tir. La plaque y est posée.
  static const _backdropHorizon = Offset(0.533, 0.50);

  /// Largeur de la plaque, en fraction de la largeur d'écran : plus petit =
  /// cible plus lointaine (et plus dure à toucher).
  static const _plateWidthFraction = 0.40;

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

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _rotations = Gyro.rotations().listen(
      (m) {
        _rotation = m;
        _reference ??= levelReference(m);
      },
      onError: (Object _) => _fallback(),
    );
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

  /// La plaque se replace droit devant, dans la direction où pointe le téléphone
  /// (à l'horizon, quelle que soit son inclinaison).
  void _recenter() {
    final r = _rotation;
    if (r != null) _reference = levelReference(r);
  }

  void _calibrate() {
    _recenter();
    HapticFeedback.selectionClick();
    setState(() => _calibrated = true);
  }

  /// Inclinaison du téléphone par rapport à l'horizontale (rad, < 0 = vers le sol).
  double get _tilt {
    final r = _rotation;
    return r == null ? 0 : aimAngles(levelReference(r), r).dy;
  }

  void _start() {
    setState(() {
      _session = ShootingSession(mode: PasDeTirMode.gyro, config: widget.config);
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
    precacheImage(_backdrop, context);
  }

  @override
  void dispose() {
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
    // Plaque assez petite pour paraître au fond du pas de tir de la photo.
    final geom = PlateGeometry(size.width * _plateWidthFraction, targetCount: c.targetCount);
    final plateTopLeft = Offset(-geom.width / 2, -geom.targetCenter(0).dy);
    final horizon = plateTopLeft.dy - 4;
    final anchor = Offset(size.width / 2, size.height * 0.42);

    // Photo à l'échelle : assez large pour ~4 écrans de balayage et assez
    // haute pour viser au-dessus et en dessous de l'horizon.
    final scale = math.max(size.width * 4 / _backdropSize.width, size.height * 1.6 / _backdropSize.height);
    final sceneSize = _backdropSize * scale;
    // Coin haut-gauche de la photo dans le monde : son point de fuite sur l'horizon.
    final sceneTopLeft = Offset(
      -sceneSize.width * _backdropHorizon.dx,
      horizon - sceneSize.height * _backdropHorizon.dy,
    );

    // Visée en px de monde, bornée pour que l'écran reste toujours dans la photo.
    final rotation = _rotation, reference = _reference;
    var aim = Offset.zero;
    if (rotation != null && reference != null) {
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _quit();
      },
      child: Scaffold(
        // Bleu du ciel de la photo, le temps qu'elle se charge.
        backgroundColor: const Color(0xFF2F5FA8),
        body: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
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
              child: TargetPlate(geometry: geom, shots: s?.shots ?? const []),
            ),
            if (s == null) ...[
              Positioned(
                left: anchor.dx - geom.targetRadius * 2.3,
                top: anchor.dy - geom.targetRadius * 2.3,
                child: Reticle(color: AlpColors.orange, size: geom.targetRadius * 4.6),
              ),
              Positioned(left: 0, right: 0, bottom: 0, child: _calibrationSheet(pad)),
            ] else
              ..._shootingOverlay(s, geom, anchor, plateOrigin, pad),
            Positioned(
              left: 0,
              right: 0,
              top: pad.top,
              child: ShootingHeader(
                badge: s == null ? 'Gyroscope' : 'Coup ${math.min(s.shots.length + 1, c.targetCount)}/${c.targetCount}',
                chrono: formatChrono(s == null ? c.timeLimit : s.elapsed),
                onClose: _quit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _shootingOverlay(
      ShootingSession s, PlateGeometry geom, Offset anchor, Offset plateOrigin, EdgeInsets pad) {
    final c = s.config;
    final reticleSize = geom.targetRadius * 4.6;
    final hitFeedback = s.showingFeedback && (s.lastOutcome?.isHit ?? false);
    // Réticule au centre de l'écran, avec un léger tremblement simulé.
    final reticle = hitFeedback ? anchor : anchor + s.sway;

    void fire() => s.fire(
          reticle: anchor + s.sway,
          target: plateOrigin + geom.targetCenter(s.activeTarget),
          // Légère tolérance : le réticule « recouvre » la cible.
          targetRadius: geom.targetRadius * 1.3,
        );

    return [
      Positioned(
        left: reticle.dx - reticleSize / 2,
        top: reticle.dy - reticleSize / 2,
        child: Reticle(
          color: hitFeedback ? AlpColors.cyan : AlpColors.orange,
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
      // Recentrer : corrige la dérive lente du gyroscope.
      Positioned(
        left: 0,
        right: 0,
        top: pad.top + 84,
        child: Center(
          child: Material(
            color: const Color(0x80404A50),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _recenter,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.center_focus_strong_outlined, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text('Recentrer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _calibrationSheet(EdgeInsets pad) {
    final tooLow = _tilt < -_maxCalibrationTilt;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + pad.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          GameIconBadge(size: 44, child: Icon(Icons.screen_rotation_alt_rounded, color: AlpColors.petrol)),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ton téléphone est ta carabine', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text('Tourne-toi et incline-le pour viser',
                  style: TextStyle(color: AlpColors.textSecondary, fontSize: 14)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        _CalibrationStep(
          number: 1,
          done: !tooLow,
          text: tooLow
              ? 'Lève ton téléphone : tiens-le à deux mains, droit devant toi, à hauteur des yeux'
              : 'Téléphone tenu droit devant toi',
        ),
        const SizedBox(height: 8),
        _CalibrationStep(
          number: 2,
          done: _calibrated,
          text: _calibrated
              ? 'Téléphone calibré : la plaque est devant toi'
              : 'Appuie sur « Calibrer » pour placer la plaque devant toi',
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: AlpSecondaryButton(
              label: _calibrated ? 'Recalibrer' : 'Calibrer',
              onPressed: _rotation == null || tooLow ? null : _calibrate,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AlpPrimaryButton(label: 'Je suis prêt', onPressed: _calibrated ? _start : null),
          ),
        ]),
      ]),
    );
  }
}

/// Étape du calibrage : pastille numérotée, cochée une fois l'étape validée.
class _CalibrationStep extends StatelessWidget {
  const _CalibrationStep({required this.number, required this.done, required this.text});
  final int number;
  final bool done;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AlpColors.cream, borderRadius: BorderRadius.circular(AlpRadii.button)),
      child: Row(children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: done ? AlpColors.petrol : AlpColors.orange),
          child: done
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
              : Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14.5))),
      ]),
    );
  }
}
