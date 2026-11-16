import 'arcore/arcore.dart';
import 'gyro/gyro.dart';

/// Réglages de démo du POC.
abstract final class PocSettings {
  /// Simule un appareil sans AR (modes Gyroscope et Classique uniquement).
  static bool forceNoAr = false;

  /// Simule un appareil sans gyroscope.
  static bool forceNoGyro = false;
}

/// Le mode Gyroscope est proposé si l'appareil a un vrai gyroscope.
Future<bool> isGyroSupported() async => !PocSettings.forceNoGyro && await Gyro.isAvailable();

/// L'AR est proposée si l'appareil est compatible ARCore (installé ou
/// installable). Aucune permission n'est demandée ici.
Future<bool> isArSupported() async {
  if (PocSettings.forceNoAr) return false;
  try {
    for (var i = 0; i < 15; i++) {
      final status = await ArCore.checkAvailability();
      if (status != 'checking') return status == 'installed' || status == 'supported_not_installed';
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  } catch (_) {}
  return false;
}

/// Permission caméra puis installation d'ARCore si nécessaire.
/// Faux → repli silencieux sur le mode Classique.
Future<bool> prepareAr() async {
  try {
    if (!await ArCore.requestCameraPermission()) return false;
    if (await ArCore.checkAvailability() == 'installed') return true;
    return await ArCore.ensureInstalled();
  } catch (_) {
    return false;
  }
}
