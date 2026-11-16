import 'package:flutter_test/flutter_test.dart';
import 'package:pas_de_tir_poc/pas_de_tir/pas_de_tir_config.dart';
import 'package:pas_de_tir_poc/pas_de_tir/pas_de_tir_logic.dart';
import 'package:pas_de_tir_poc/pas_de_tir/pas_de_tir_result.dart';

void main() {
  const c = PasDeTirConfig.standard;
  const target = Offset(100, 50);
  const radius = 20.0;

  group('Règle de réussite', () {
    test('touché : curseur dans la zone et réticule sur la cible', () {
      expect(
        evaluateShot(cursor: 0.5, reticle: target, target: target, targetRadius: radius),
        ShotOutcome.hit,
      );
      expect(
        evaluateShot(cursor: 0.4, reticle: target + const Offset(19, 0), target: target, targetRadius: radius),
        ShotOutcome.hit,
      );
    });

    test('bornes de la zone de tir incluses', () {
      for (final cursor in [c.zoneStart, c.zoneEnd]) {
        expect(evaluateShot(cursor: cursor, reticle: target, target: target, targetRadius: radius),
            ShotOutcome.hit);
      }
    });

    test("raté : curseur hors zone (inspiration), même sur la cible", () {
      for (final cursor in [0.0, 0.2, 0.37, 0.63, 1.0]) {
        expect(evaluateShot(cursor: cursor, reticle: target, target: target, targetRadius: radius),
            ShotOutcome.missBreath);
      }
    });

    test('sans respiration : seule la visée compte', () {
      const noBreath = PasDeTirConfig(breathing: false);
      for (final cursor in [0.0, 0.5, 1.0]) {
        expect(evaluateShot(cursor: cursor, reticle: target, target: target, targetRadius: radius, config: noBreath),
            ShotOutcome.hit);
      }
      expect(
        evaluateShot(
            cursor: 0.0, reticle: target + const Offset(30, 0), target: target, targetRadius: radius, config: noBreath),
        ShotOutcome.missAim,
      );
    });

    test('raté : curseur dans la zone mais réticule hors cible', () {
      expect(
        evaluateShot(cursor: 0.5, reticle: target + const Offset(15, 15), target: target, targetRadius: radius),
        ShotOutcome.missAim,
      );
    });
  });

  group('Calcul des gouttes', () {
    test('+10 par cible touchée, 0 par cible ratée', () {
      expect(computeDrops(const []), 0);
      expect(computeDrops(List.filled(5, ShotOutcome.hit)), 50);
      expect(
        computeDrops(const [
          ShotOutcome.hit,
          ShotOutcome.hit,
          ShotOutcome.missBreath,
          ShotOutcome.hit,
          ShotOutcome.hit,
        ]),
        40,
      );
      expect(computeDrops(List.filled(5, ShotOutcome.missAim)), 0);
    });

    test('maximum de 50 gouttes avec la config standard', () {
      expect(c.maxDrops, 50);
    });

    test('config personnalisée', () {
      const custom = PasDeTirConfig(dropsPerTarget: 15, targetCount: 3);
      expect(computeDrops(const [ShotOutcome.hit, ShotOutcome.missBreath, ShotOutcome.hit], custom), 30);
    });

    test('chrono écoulé : les balles restantes comptent comme ratées', () {
      final shots = completeWithMisses(const [ShotOutcome.hit, ShotOutcome.hit]);
      expect(shots.length, 5);
      expect(hitCount(shots), 2);
      expect(computeDrops(shots), 20);
      expect(computePrecision(shots), 40);
    });

    test('résultat remonté au back', () {
      final r = PasDeTirResult(
        shots: const [ShotOutcome.hit, ShotOutcome.hit, ShotOutcome.hit, ShotOutcome.missBreath, ShotOutcome.hit],
        duration: const Duration(seconds: 42),
        mode: PasDeTirMode.classic,
      );
      expect(r.toJson(), {
        'type': 'pas_de_tir',
        'hits': 4,
        'sequence': [true, true, true, false, true],
        'duration_ms': 42000,
        'mode': 'classic',
        'precision': 80,
        'drops': 40,
        'abandoned': false,
      });
    });
  });

  group('Respiration simulée', () {
    test('le curseur fait un aller-retour par cycle de 4,6 s', () {
      expect(breathCursorAt(Duration.zero), closeTo(0, 1e-9));
      expect(breathCursorAt(const Duration(milliseconds: 2300)), closeTo(1, 1e-9));
      expect(breathCursorAt(const Duration(milliseconds: 4600)), closeTo(0, 1e-9));
      expect(breathCursorAt(const Duration(milliseconds: 1150)), closeTo(0.5, 1e-9));
    });

    test("libellés d'état de la jauge", () {
      expect(breathPhaseOf(0.5), BreathPhase.shootingZone);
      expect(breathPhaseOf(0.05), BreathPhase.inhale);
      expect(breathPhaseOf(0.95), BreathPhase.inhale);
      expect(breathPhaseOf(0.3), BreathPhase.exhale);
    });

    test("le viseur est stable au centre et bouge beaucoup sur les bords", () {
      expect(swayAmplitude(0.5), 0);
      expect(swayAmplitude(0.0), closeTo(c.maxSway, 1e-9));
      expect(swayAmplitude(0.6), lessThan(swayAmplitude(0.9)));
    });
  });
}
