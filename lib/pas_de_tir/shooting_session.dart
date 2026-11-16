import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'pas_de_tir_config.dart';
import 'pas_de_tir_logic.dart';
import 'pas_de_tir_result.dart';

/// État d'une série de tir. L'écran appelle [tick] à chaque frame avec le
/// temps écoulé depuis son ouverture ; le chrono ne démarre qu'au premier tir.
class ShootingSession extends ChangeNotifier {
  ShootingSession({required this.mode, this.config = PasDeTirConfig.standard});

  final PasDeTirMode mode;
  final PasDeTirConfig config;

  static const feedbackDuration = Duration(milliseconds: 1100);
  static const fireCooldown = Duration(milliseconds: 650);

  final List<ShotOutcome> shots = [];
  Duration _clock = Duration.zero;
  Duration? _firstShotAt;
  Duration? _lastShotAt;
  Duration? _finishedAt;
  Offset? lastShotReticle;
  bool finished = false;
  bool timedOut = false;

  Duration get clock => _clock;
  double get cursor => breathCursorAt(_clock, config);
  Offset get sway => swayOffset(_clock, cursor, config);

  /// Temps écoulé depuis le premier tir (borné au chrono).
  Duration get elapsed {
    if (_firstShotAt == null) return Duration.zero;
    final e = (_finishedAt ?? _clock) - _firstShotAt!;
    return e > config.timeLimit ? config.timeLimit : e;
  }

  bool get started => _firstShotAt != null;
  int get hits => hitCount(shots);
  int get drops => computeDrops(shots, config);
  int get activeTarget => shots.length.clamp(0, config.targetCount - 1);

  ShotOutcome? get lastOutcome => shots.isEmpty ? null : shots.last;

  bool get showingFeedback =>
      _lastShotAt != null && _clock - _lastShotAt! < feedbackDuration && !timedOut;

  /// 0→1 pendant l'affichage du retour de tir.
  double get feedbackProgress => _lastShotAt == null
      ? 1
      : ((_clock - _lastShotAt!).inMicroseconds / feedbackDuration.inMicroseconds).clamp(0.0, 1.0);

  bool get canFire =>
      !finished && shots.length < config.targetCount && (_lastShotAt == null || _clock - _lastShotAt! >= fireCooldown);

  /// Cible en cours de visée (celle du retour de tir pendant le feedback).
  int get aimedTarget => showingFeedback ? shots.length - 1 : activeTarget;

  void tick(Duration clock) {
    _clock = clock;
    if (started && !finished && _clock - _firstShotAt! >= config.timeLimit) {
      timedOut = true;
      _finish();
    }
    notifyListeners();
  }

  /// Tire sur la cible active. [reticle] et [target] sont exprimés dans le
  /// même repère.
  ShotOutcome? fire({required Offset reticle, required Offset target, required double targetRadius}) {
    if (!canFire) return null;
    _firstShotAt ??= _clock;
    final outcome = evaluateShot(
      cursor: cursor,
      reticle: reticle,
      target: target,
      targetRadius: targetRadius,
      config: config,
    );
    shots.add(outcome);
    _lastShotAt = _clock;
    lastShotReticle = outcome.isHit ? target : reticle;
    if (outcome.isHit) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    if (shots.length == config.targetCount) _finish();
    notifyListeners();
    return outcome;
  }

  void _finish() {
    finished = true;
    _finishedAt = _clock;
  }

  /// Fin de série atteinte et retour du dernier tir affiché.
  bool get readyForResult => finished && !showingFeedback;

  PasDeTirResult buildResult({bool abandoned = false, String? capturePath}) => PasDeTirResult(
        shots: completeWithMisses(shots, config),
        duration: elapsed,
        mode: mode,
        abandoned: abandoned,
        capturePath: capturePath,
        config: config,
      );
}
