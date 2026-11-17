import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pas_de_tir_poc/pas_de_tir/gyro/gyro.dart';

/// Matrices de rotation (ligne par ligne) autour des axes du monde.
List<double> rotX(double a) => [1, 0, 0, 0, math.cos(a), -math.sin(a), 0, math.sin(a), math.cos(a)];
List<double> rotY(double a) => [math.cos(a), 0, math.sin(a), 0, 1, 0, -math.sin(a), 0, math.cos(a)];
List<double> rotZ(double a) => [math.cos(a), -math.sin(a), 0, math.sin(a), math.cos(a), 0, 0, 0, 1];

List<double> mul(List<double> a, List<double> b) => [
      for (var i = 0; i < 3; i++)
        for (var j = 0; j < 3; j++) a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j],
    ];

void main() {
  final identity = rotZ(0);

  group('Visée au gyroscope', () {
    test('même orientation : visée au centre', () {
      final a = aimAngles(identity, identity);
      expect(a.dx, closeTo(0, 1e-9));
      expect(a.dy, closeTo(0, 1e-9));
    });

    test('tourner vers la droite décale la visée à droite', () {
      // Rotation positive autour de Y (haut) = vers la gauche, vue de dessus.
      expect(aimAngles(identity, rotY(-0.2)).dx, closeTo(0.2, 1e-9));
      expect(aimAngles(identity, rotY(0.2)).dx, closeTo(-0.2, 1e-9));
      expect(aimAngles(identity, rotY(0.2)).dy, closeTo(0, 1e-9));
    });

    test('lever le téléphone fait monter la visée', () {
      final a = aimAngles(identity, rotX(0.15));
      expect(a.dy, closeTo(0.15, 1e-9));
      expect(a.dx, closeTo(0, 1e-9));
    });

    test('le roulis est sans effet', () {
      final a = aimAngles(identity, rotZ(0.5));
      expect(a.dx, closeTo(0, 1e-9));
      expect(a.dy, closeTo(0, 1e-9));
    });

    // Monde Android : Z vers le haut. Téléphone debout face au nord = rotX(π/2).
    final upright = rotX(math.pi / 2);

    test('calibrage : la plaque reste à l\'horizon même téléphone incliné vers le sol', () {
      for (final tilt in [0.0, -0.3, -0.8, 0.4]) {
        final phone = mul(upright, rotX(tilt));
        final a = aimAngles(levelReference(phone), phone);
        expect(a.dx, closeTo(0, 1e-9));
        expect(a.dy, closeTo(tilt, 1e-9));
      }
    });

    test('calibrage : reprend le cap du téléphone', () {
      final phone = mul(rotZ(1.2), mul(upright, rotX(-0.5)));
      final reference = levelReference(phone);
      expect(aimAngles(reference, mul(rotZ(1.2), upright)).dx, closeTo(0, 1e-9));
      expect(aimAngles(reference, mul(rotZ(1.0), upright)).dx, closeTo(0.2, 1e-9));
    });

    test('calibrage téléphone à plat : cap donné par le haut de l\'écran', () {
      final flat = rotZ(0.7);
      final a = aimAngles(levelReference(flat), mul(rotZ(0.7), upright));
      expect(a.dx, closeTo(0, 1e-9));
      expect(a.dy, closeTo(0, 1e-9));
    });

    test('calibrage à l\'inclinaison du joueur : visée au centre, cap conservé', () {
      for (final tilt in [0.0, -0.3, -0.5, 0.4]) {
        final phone = mul(rotZ(0.9), mul(upright, mul(rotX(tilt), rotZ(0.2))));
        final reference = aimReference(phone);
        final a = aimAngles(reference, phone);
        expect(a.dx, closeTo(0, 1e-9));
        expect(a.dy, closeTo(0, 1e-9));
        // Lever le téléphone de 0,1 rad fait monter la visée d'autant.
        final raised = mul(rotZ(0.9), mul(upright, rotX(tilt + 0.1)));
        expect(aimAngles(reference, raised).dy, closeTo(0.1, 1e-9));
        expect(aimAngles(reference, raised).dx, closeTo(0, 1e-9));
      }
    });

    test('calibrage à l\'inclinaison : tangage borné', () {
      final phone = mul(upright, rotX(-1.2));
      expect(aimAngles(aimReference(phone), phone).dy, closeTo(-0.5, 1e-9));
    });

    test('relatif à une référence quelconque (téléphone incliné et tourné)', () {
      final reference = mul(rotY(1.1), rotX(-0.4));
      final current = mul(reference, rotY(-0.1));
      final a = aimAngles(reference, current);
      expect(a.dx, closeTo(0.1, 1e-9));
      expect(a.dy, closeTo(0, 1e-9));
    });
  });
}
