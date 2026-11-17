import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Pont vers la session ARCore native (android/.../arcore).
abstract final class ArCore {
  static const _methods = MethodChannel('alpvengers/arcore');
  static const _frames = EventChannel('alpvengers/arcore/frames');
  static const viewType = 'alpvengers/arcore_view';

  /// 'installed', 'supported_not_installed', 'unsupported' ou 'checking'.
  static Future<String> checkAvailability() async =>
      await _methods.invokeMethod<String>('checkAvailability') ?? 'unsupported';

  /// Installe/met à jour « Services Google Play pour la RA » si besoin.
  static Future<bool> ensureInstalled() async => await _methods.invokeMethod<bool>('ensureInstalled') ?? false;

  static Future<bool> requestCameraPermission() async =>
      await _methods.invokeMethod<bool>('requestCameraPermission') ?? false;

  static Future<void> setMode(ArMode mode) => _methods.invokeMethod('setMode', {'mode': mode.name});

  /// Ancre la plaque là où elle est prévisualisée (distance fixe, droit devant).
  static Future<void> confirmPlacement() => _methods.invokeMethod('confirmPlacement');

  /// Capture de l'image caméra courante ; renvoie le chemin du JPEG.
  static Future<String?> capture() => _methods.invokeMethod<String>('capture');

  /// Données par frame ; les coordonnées sont converties en pixels logiques.
  static Stream<ArFrame> frames(double devicePixelRatio) =>
      _frames.receiveBroadcastStream().map((e) => ArFrame.fromMap(e as Map, devicePixelRatio));
}

enum ArMode { scanning, placing, anchored }

class ArFrame {
  const ArFrame({
    required this.tracking,
    required this.failure,
    required this.mode,
    required this.planeArea,
    required this.points,
    this.corners,
    this.feet,
  });

  final bool tracking;

  /// Raison ARCore de la perte de suivi (NONE, INSUFFICIENT_LIGHT, EXCESSIVE_MOTION…).
  final String failure;
  final ArMode mode;

  /// Surface cumulée des plans horizontaux détectés (m²).
  final double planeArea;

  /// Nuage de points de détection projeté à l'écran.
  final List<Offset> points;

  /// Coins de la plaque (haut-gauche, haut-droite, bas-droite, bas-gauche).
  final List<Offset>? corners;

  /// Pieds gauche et droit de la plaque, au sol.
  final List<Offset>? feet;

  static List<Offset> _offsets(Object? raw, double dpr) {
    if (raw == null) return const [];
    final list = raw is Float64List ? raw : Float64List.fromList((raw as List).cast<double>());
    return [for (var i = 0; i + 1 < list.length; i += 2) Offset(list[i] / dpr, list[i + 1] / dpr)];
  }

  factory ArFrame.fromMap(Map map, double dpr) {
    final corners = _offsets(map['corners'], dpr);
    final feet = _offsets(map['feet'], dpr);
    return ArFrame(
      tracking: map['tracking'] == true,
      failure: map['failure'] as String? ?? 'NONE',
      mode: ArMode.values.firstWhere((m) => m.name == map['mode'], orElse: () => ArMode.scanning),
      planeArea: (map['planeArea'] as num?)?.toDouble() ?? 0,
      points: _offsets(map['points'], dpr),
      corners: corners.length == 4 ? corners : null,
      feet: feet.length == 2 ? feet : null,
    );
  }
}

/// Vue caméra ARCore native.
///
/// AndroidView (texture layer / virtual display) et non l'hybrid composition :
/// celle-ci fait tourner l'UI Flutter sur le thread principal Android, ce qui
/// retarde les capteurs (IMU) d'ARCore et fait décrocher le suivi.
class ArCoreCameraView extends StatelessWidget {
  const ArCoreCameraView({super.key});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) return const ColoredBox(color: Color(0xFF000000));
    return const AndroidView(
      viewType: ArCore.viewType,
      creationParamsCodec: StandardMessageCodec(),
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    );
  }
}
