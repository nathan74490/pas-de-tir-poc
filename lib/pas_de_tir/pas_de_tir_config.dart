/// Paramètres de la gamification « Pas de tir ».
///
/// Toutes les valeurs de gameplay sont regroupées ici pour pouvoir être
/// ajustées (ou, plus tard, poussées par le WebAdmin) sans toucher à la logique.
class PasDeTirConfig {
  const PasDeTirConfig({
    this.breathCycle = const Duration(milliseconds: 4600),
    this.zoneStart = 0.38,
    this.zoneEnd = 0.62,
    this.targetCount = 5,
    this.dropsPerTarget = 10,
    this.timeLimit = const Duration(seconds: 60),
    this.maxSway = 46,
    this.minSway = 0,
    this.swayFrequencyX = 0.26,
    this.swayFrequencyY = 0.4,
    this.breathing = true,
  });

  /// Durée d'un cycle complet de respiration simulée (aller-retour du curseur).
  final Duration breathCycle;

  /// Début et fin de la « zone de tir », en fraction de la largeur de la jauge.
  final double zoneStart;
  final double zoneEnd;

  /// Nombre de cibles (et donc de balles).
  final int targetCount;

  /// Gouttes d'Effort gagnées par cible touchée.
  final int dropsPerTarget;

  /// Durée du chrono, qui démarre au premier tir.
  final Duration timeLimit;

  /// Amplitude maximale d'oscillation du réticule (px logiques), atteinte
  /// quand le curseur est au bord de la jauge.
  final double maxSway;

  /// Amplitude minimale (px logiques) : léger tremblement permanent, même
  /// au centre de la zone de tir.
  final double minSway;

  /// Fréquences (Hz) de l'oscillation du réticule : plus bas = plus lent.
  final double swayFrequencyX;
  final double swayFrequencyY;

  /// Respiration simulée : jauge affichée et tir valide seulement dans la
  /// zone de tir. Sans elle, seule la visée compte.
  final bool breathing;

  int get maxDrops => targetCount * dropsPerTarget;

  static const standard = PasDeTirConfig();

  /// En AR, seule la visée compte : pas de respiration. Comme au gyroscope,
  /// le réticule suit le téléphone avec un léger tremblement (3 à 7 px).
  static const ar = PasDeTirConfig(maxSway: 7, minSway: 3, breathing: false);

  /// Au gyroscope, seule la visée compte : pas de respiration. Le réticule
  /// suit le téléphone avec un léger tremblement (3 à 7 px) pour corser la visée.
  static const gyro = PasDeTirConfig(maxSway: 7, minSway: 3, breathing: false);
}
