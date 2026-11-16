import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'pas_de_tir_config.dart';

/// Logique pure du pas de tir : aucune dépendance à Flutter widgets,
/// aucun état. Tout est testable unitairement.

/// Issue d'un tir.
enum ShotOutcome {
  hit,

  /// Curseur hors de la zone de tir (tir pendant l'inspiration).
  missBreath,

  /// Curseur dans la zone, mais réticule hors de la cible.
  missAim,

  /// Balle non tirée avant la fin du chrono (ou abandon).
  notFired;

  bool get isHit => this == ShotOutcome.hit;
}

/// État de la jauge de respiration, pour son libellé.
enum BreathPhase { exhale, shootingZone, inhale }

/// Position du curseur de respiration (0 = bord gauche, 1 = bord droit)
/// à l'instant [elapsed], selon une sinusoïde de période [PasDeTirConfig.breathCycle].
/// Le curseur démarre au bord gauche (inspiration).
double breathCursorAt(Duration elapsed, [PasDeTirConfig c = PasDeTirConfig.standard]) {
  final phase = elapsed.inMicroseconds / c.breathCycle.inMicroseconds;
  return 0.5 - 0.5 * math.cos(2 * math.pi * phase);
}

/// Le curseur est-il dans la zone de tir ?
bool isInShootingZone(double cursor, [PasDeTirConfig c = PasDeTirConfig.standard]) =>
    cursor >= c.zoneStart && cursor <= c.zoneEnd;

/// Libellé d'état de la jauge : « Zone de tir » dans la zone, « Inspiration »
/// sur les bords, « Expire… » entre les deux.
BreathPhase breathPhaseOf(double cursor, [PasDeTirConfig c = PasDeTirConfig.standard]) {
  if (isInShootingZone(cursor, c)) return BreathPhase.shootingZone;
  final zoneHalf = (c.zoneEnd - c.zoneStart) / 2;
  // Bords : le quart extérieur de la partie hors zone de chaque côté.
  final edge = zoneHalf + (0.5 - zoneHalf) * 0.5;
  return (cursor - 0.5).abs() >= edge ? BreathPhase.inhale : BreathPhase.exhale;
}

/// Amplitude d'oscillation du réticule, proportionnelle à la distance entre
/// le curseur et le centre de la zone de tir ([minSway] au centre, [maxSway] au bord).
double swayAmplitude(double cursor, [PasDeTirConfig c = PasDeTirConfig.standard]) {
  final center = (c.zoneStart + c.zoneEnd) / 2;
  final maxDistance = math.max(center, 1 - center);
  final d = ((cursor - center).abs() / maxDistance).clamp(0.0, 1.0);
  return c.minSway + (c.maxSway - c.minSway) * d;
}

/// Décalage du réticule dû à la respiration à l'instant [elapsed]
/// (courbe de Lissajous lente, pour un mouvement organique).
Offset swayOffset(Duration elapsed, double cursor, [PasDeTirConfig c = PasDeTirConfig.standard]) {
  final t = elapsed.inMicroseconds / 1e6;
  final a = swayAmplitude(cursor, c);
  return Offset(
    a * math.sin(2 * math.pi * c.swayFrequencyX * t),
    a * 0.7 * math.sin(2 * math.pi * c.swayFrequencyY * t + 1.3),
  );
}

/// Règle de réussite : touché si le curseur est dans la zone de tir **et**
/// si le centre du réticule recouvre la cible active. Sans respiration
/// ([PasDeTirConfig.breathing] à faux), seule la visée compte.
ShotOutcome evaluateShot({
  required double cursor,
  required Offset reticle,
  required Offset target,
  required double targetRadius,
  PasDeTirConfig config = PasDeTirConfig.standard,
}) {
  if (config.breathing && !isInShootingZone(cursor, config)) return ShotOutcome.missBreath;
  if ((reticle - target).distance > targetRadius) return ShotOutcome.missAim;
  return ShotOutcome.hit;
}

int hitCount(List<ShotOutcome> shots) => shots.where((s) => s.isHit).length;

/// Gouttes gagnées : [PasDeTirConfig.dropsPerTarget] par cible touchée, 0 sinon.
int computeDrops(List<ShotOutcome> shots, [PasDeTirConfig c = PasDeTirConfig.standard]) =>
    hitCount(shots) * c.dropsPerTarget;

/// Précision en pourcentage entier, sur le nombre total de cibles.
int computePrecision(List<ShotOutcome> shots, [PasDeTirConfig c = PasDeTirConfig.standard]) =>
    (hitCount(shots) * 100 / c.targetCount).round();

/// Complète la série avec des cibles ratées (chrono écoulé ou abandon).
List<ShotOutcome> completeWithMisses(List<ShotOutcome> shots,
    [PasDeTirConfig c = PasDeTirConfig.standard]) {
  return [
    ...shots,
    for (var i = shots.length; i < c.targetCount; i++) ShotOutcome.notFired,
  ];
}
