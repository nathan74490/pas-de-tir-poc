import 'dart:math' as math;
import 'package:flutter/services.dart';

/// Pont vers les capteurs d'orientation natifs (android/.../gyro).
abstract final class Gyro {
  static const _methods = MethodChannel('alpvengers/gyro');
  static const _rotation = EventChannel('alpvengers/gyro/rotation');

  /// Gyroscope physique + capteur de rotation présents.
  static Future<bool> isAvailable() async {
    try {
      return await _methods.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Matrices de rotation appareil → monde (3×3, ligne par ligne), ~50 Hz.
  static Stream<List<double>> rotations() =>
      _rotation.receiveBroadcastStream().map((e) => (e as List).cast<double>());
}

/// Orientation de référence « droit devant, à l'horizontale » dans la
/// direction où pointe le téléphone [current] : seul le cap est repris, le
/// tangage est calé sur la gravité. La plaque reste ainsi à hauteur d'yeux même
/// si le téléphone est tenu à plat au moment du calibrage.
List<double> levelReference(List<double> current) {
  // Monde : Z vers le haut. Cap = axe de visée (−Z appareil) projeté au sol ;
  // téléphone à plat, on prend plutôt le haut de l'écran (+Y appareil).
  var fx = -current[2], fy = -current[5];
  if (math.sqrt(fx * fx + fy * fy) < 0.2) {
    fx = current[1];
    fy = current[4];
  }
  final n = math.sqrt(fx * fx + fy * fy);
  if (n < 1e-6) return current;
  fx /= n;
  fy /= n;
  // Colonnes : droite = avant × haut, haut = Z monde, arrière = −avant.
  return [fy, 0, -fx, -fx, 0, -fy, 0, 1, 0];
}

/// Angles de visée (lacet, tangage) en radians de l'axe de la caméra arrière
/// (−Z appareil) dans l'orientation [current], par rapport à l'orientation
/// [reference] : `dx` > 0 = tourné vers la droite, `dy` > 0 = levé vers le haut.
/// Le roulis (téléphone penché sur le côté) n'a pas d'effet.
Offset aimAngles(List<double> reference, List<double> current) {
  // Colonne j de la matrice (ligne par ligne) = axe j de l'appareil dans le monde.
  double dot(List<double> a, int i, List<double> b, int j) => a[i] * b[j] + a[3 + i] * b[3 + j] + a[6 + i] * b[6 + j];
  // Axe de visée courant (−Z) projeté sur les axes de référence droite (X), haut (Y), avant (−Z).
  final right = -dot(current, 2, reference, 0);
  final up = -dot(current, 2, reference, 1);
  final forward = dot(current, 2, reference, 2);
  return Offset(
    math.atan2(right, forward),
    math.atan2(up, math.sqrt(right * right + forward * forward)),
  );
}
