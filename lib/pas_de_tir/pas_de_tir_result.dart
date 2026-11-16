import 'pas_de_tir_config.dart';
import 'pas_de_tir_logic.dart';

enum PasDeTirMode {
  ar('ar', 'AR', 'Réalité augmentée'),
  gyro('gyro', 'Gyro', 'Gyroscope'),
  classic('classic', 'Classique', 'Classique');

  const PasDeTirMode(this.apiValue, this.shortLabel, this.longLabel);
  final String apiValue;
  final String shortLabel;
  final String longLabel;
}

/// Renvoyé par un écran AR ou Gyroscope quand le capteur échoue (session
/// ARCore impossible, gyroscope muet) : l'appelant bascule en mode Classique.
class ClassicFallbackSignal {
  const ClassicFallbackSignal();
}

/// Résultat d'une session, tel qu'il serait remonté au back
/// (crédit des gouttes + classement « Meilleur tireur du jour »).
class PasDeTirResult {
  PasDeTirResult({
    required this.shots,
    required this.duration,
    required this.mode,
    this.abandoned = false,
    this.capturePath,
    this.config = PasDeTirConfig.standard,
  });

  /// Ordre des tirs touchés/ratés, toujours de longueur [PasDeTirConfig.targetCount].
  final List<ShotOutcome> shots;
  final Duration duration;
  final PasDeTirMode mode;
  final bool abandoned;

  /// Capture AR prise en fin de série (souvenir partageable), si disponible.
  final String? capturePath;
  final PasDeTirConfig config;

  int get hits => hitCount(shots);
  int get misses => shots.length - hits;
  int get drops => computeDrops(shots, config);
  int get precision => computePrecision(shots, config);

  Map<String, dynamic> toJson() => {
        'type': 'pas_de_tir',
        'hits': hits,
        'sequence': shots.map((s) => s.isHit).toList(),
        'duration_ms': duration.inMilliseconds,
        'mode': mode.apiValue,
        'precision': precision,
        'drops': drops,
        'abandoned': abandoned,
      };
}
