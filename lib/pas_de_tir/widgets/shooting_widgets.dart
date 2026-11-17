import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/alp_tokens.dart';
import '../pas_de_tir_config.dart';
import '../pas_de_tir_logic.dart';
import '../shooting_session.dart';

/// Assets exportés de la maquette Figma « Shooting range (biathlon) ».
abstract final class PdtAssets {
  static const _dir = 'assets/images/pas_de_tir';
  static const target = '$_dir/target.png';
  static const targetHit = '$_dir/target_hit.svg';
  static const targetMissDisc = '$_dir/target_miss_disc.svg';
  static const targetMissX = '$_dir/target_miss_x.svg';
  static const targetMissDot = '$_dir/target_miss_dot.svg';
  static const reticle = '$_dir/reticle.svg';
  static const shootIcon = '$_dir/shoot_icon.svg';
  static const recenter = '$_dir/recenter.svg';
  static const closeButton = '$_dir/close_button.svg';
  static const backButton = '$_dir/back_button.svg';
  static const timer = '$_dir/timer.svg';
  static const drop = '$_dir/drop.svg';
  static const gpsFixSmall = '$_dir/gps_fix_small.svg';
  static const bullet = '$_dir/bullet.svg';
  static const bulletSpent = '$_dir/bullet_spent.svg';
  static const toastHit = '$_dir/toast_hit.svg';
  static const toastMiss = '$_dir/toast_miss.svg';
  static const breathDot = '$_dir/breath_dot.svg';
  static const scanFrame = '$_dir/scan_frame.svg';
  static const cornersOut = '$_dir/corners_out.svg';
  static const checkCircle = '$_dir/check_circle.svg';
  static const mountains = '$_dir/mountains.png';
  static const recapHit = '$_dir/recap_hit.svg';
  static const recapMissDisc = '$_dir/recap_miss_disc.svg';
  static const recapMissX = '$_dir/recap_miss_x.svg';
  static const modalClose = '$_dir/modal_close.svg';
  static const introIcon = '$_dir/intro_icon.svg';
  static const ruleTarget = '$_dir/rule_target.svg';
  static const ruleClock = '$_dir/rule_clock.svg';
  static const camera = '$_dir/camera.svg';
  static const iconPhone = '$_dir/icon_phone.png';
  static const iconTarget = '$_dir/icon_target.png';
  static const iconWind = '$_dir/icon_wind.png';
}

/// Pastille « goutte d'effort » de la maquette (icône carrée rognée en rond).
class DropIcon extends StatelessWidget {
  const DropIcon({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) =>
      ClipOval(child: SvgPicture.asset(PdtAssets.drop, width: size, height: size));
}

// ───────────────────────────── Cibles ─────────────────────────────

/// Géométrie de la rangée de cibles, en coordonnées locales. Référence
/// maquette pour 5 cibles : 356 × 84, cibles de 60 espacées de 8, marge 12.
class PlateGeometry {
  const PlateGeometry(this.width, {this.targetCount = 5});

  final double width;
  final int targetCount;

  double get _refWidth => 24.0 + 68.0 * targetCount - 8;
  double get _s => width / _refWidth;

  double get height => 84 * _s;
  double get targetSize => 60 * _s;
  double get targetRadius => targetSize / 2;

  Offset targetCenter(int i) => Offset((12 + 30 + 68 * i) * _s, 42 * _s);

  /// Taille du viseur (140 pour des cibles de 60 sur la maquette).
  double get reticleSize => targetSize * 140 / 60;
}

/// Rangée de cibles. Une cible touchée devient un disque cyan coché, une
/// cible ratée un disque gris barré avec l'impact orange.
class TargetPlate extends StatelessWidget {
  const TargetPlate({super.key, required this.geometry, required this.shots, this.impactOn});

  final PlateGeometry geometry;
  final List<ShotOutcome> shots;

  /// Cible touchée à l'instant (retour de tir) : affichée assombrie sous le
  /// viseur avant de passer en « touchée ».
  final int? impactOn;

  @override
  Widget build(BuildContext context) {
    final g = geometry;
    return SizedBox(
      width: g.width,
      height: g.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < g.targetCount; i++)
            Positioned(
              left: g.targetCenter(i).dx - g.targetRadius,
              top: g.targetCenter(i).dy - g.targetRadius,
              child: TargetFace(
                size: g.targetSize,
                state: i == impactOn
                    ? TargetState.impact
                    : i < shots.length
                    ? (shots[i].isHit ? TargetState.hit : TargetState.miss)
                    : TargetState.pending,
              ),
            ),
        ],
      ),
    );
  }
}

enum TargetState { pending, impact, hit, miss }

class TargetFace extends StatelessWidget {
  const TargetFace({super.key, required this.size, required this.state});
  final double size;
  final TargetState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: switch (state) {
        TargetState.pending || TargetState.impact => _image(darken: state == TargetState.impact),
        TargetState.hit => SvgPicture.asset(PdtAssets.targetHit, width: size, height: size),
        TargetState.miss => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            SvgPicture.asset(PdtAssets.targetMissDisc, width: size, height: size),
            SvgPicture.asset(PdtAssets.targetMissX, width: size * 0.291, height: size * 0.291),
            Positioned(
              bottom: -size * 0.073,
              child: SvgPicture.asset(PdtAssets.targetMissDot, width: size * 0.24, height: size * 0.24),
            ),
          ],
        ),
      },
    );
  }

  /// L'image de la maquette inclut une ombre : elle est agrandie à 110 % et
  /// décalée, comme dans Figma.
  Widget _image({required bool darken}) => ClipRect(
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -size * 0.0484,
          top: -size * 0.0419,
          width: size * 1.1032,
          height: size * 1.1032,
          child: Image.asset(PdtAssets.target, filterQuality: FilterQuality.medium),
        ),
        if (darken)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF3A1A0A).withValues(alpha: 0.55)),
            ),
          ),
      ],
    ),
  );
}

/// Viseur (Phosphor GpsFix). [pulse] : progression 0→1 de l'anneau qui
/// s'élargit au moment d'un tir touché.
class Reticle extends StatelessWidget {
  const Reticle({super.key, this.color = AlpColors.orange, this.size = 140, this.pulse});

  final Color color;
  final double size;
  final double? pulse;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SvgPicture.asset(
              PdtAssets.reticle,
              width: size,
              height: size,
              colorFilter: color == AlpColors.orange ? null : ColorFilter.mode(color, BlendMode.srcIn),
            ),
            if (pulse != null)
              Positioned.fill(child: CustomPaint(painter: _PulsePainter(color, pulse!))),
          ],
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.color, this.t);
  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width * 0.31 * (1 + 0.5 * t),
      Paint()
        ..color = color.withValues(alpha: (1 - t) * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t || old.color != color;
}

// ───────────────────────────── En-tête ─────────────────────────────

/// Bouton carré blanc 44 × 44 (fermer ou retour) de la maquette.
class RangeIconButton extends StatelessWidget {
  const RangeIconButton({super.key, required this.onPressed, this.back = false});
  final VoidCallback onPressed;
  final bool back;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: back ? 'Retour' : 'Quitter le pas de tir',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: SvgPicture.asset(back ? PdtAssets.backButton : PdtAssets.closeButton, width: 44, height: 44),
      ),
    );
  }
}

/// Header des écrans de tir : bouton ✕ (ou retour), « Pas de tir » + mode, chrono.
class RangeHeader extends StatelessWidget {
  const RangeHeader({
    super.key,
    required this.subtitle,
    required this.onClose,
    this.chrono,
    this.light = true,
    this.back = false,
  });

  final String subtitle;
  final String? chrono;
  final VoidCallback onClose;

  /// Texte blanc (sur caméra ou photo) ou noir (fond clair).
  final bool light;
  final bool back;

  static const _side = 84.0;

  @override
  Widget build(BuildContext context) {
    final fg = light ? Colors.white : AlpColors.text;
    // Sur décor clair (neige, ciel blanc), le texte blanc reste lisible grâce à une ombre douce.
    final shadows = light ? const [Shadow(color: Color(0x99000000), blurRadius: 8)] : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: _side,
            child: Align(
              alignment: Alignment.centerLeft,
              child: RangeIconButton(onPressed: onClose, back: back),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Pas de tir',
                    style: TextStyle(
                      color: fg,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      shadows: shadows,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 14, height: 1.2, shadows: shadows),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _side,
            child: Align(
              alignment: Alignment.centerRight,
              child: chrono == null ? null : ChronoPill(text: chrono!),
            ),
          ),
        ],
      ),
    );
  }
}

class ChronoPill extends StatelessWidget {
  const ChronoPill({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AlpColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(PdtAssets.timer, width: 16, height: 16),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: AlpColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Stats ─────────────────────────────

/// Pastille blanche arrondie des stats.
class _Chip extends StatelessWidget {
  const _Chip({required this.child, this.padding = const EdgeInsets.all(6)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AlpColors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: child,
    );
  }
}

/// Ligne « +N Gouttes » / « tirs n/5 ». Sur décor, elle est posée sur une
/// barre translucide ([onScenery]) ; sur fond clair, les pastilles sont seules.
class RangeStatsBar extends StatelessWidget {
  const RangeStatsBar({super.key, required this.session, this.onScenery = true});
  final ShootingSession session;
  final bool onScenery;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _Chip(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DropIcon(size: 24),
              const SizedBox(width: 4),
              Text(
                '+${s.drops} Gouttes',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 20 / 14),
              ),
            ],
          ),
        ),
        Semantics(
          label: '${s.shots.length} tirs sur ${s.config.targetCount}',
          excludeSemantics: true,
          child: _Chip(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(PdtAssets.gpsFixSmall, width: 16, height: 16),
                const SizedBox(width: 4),
                Text(
                  '${s.shots.length}/${s.config.targetCount}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    if (!onScenery) return row;
    return Container(
      height: 54,
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(color: AlpColors.darkBar, borderRadius: BorderRadius.circular(999)),
      child: row,
    );
  }
}

/// Cartes « Balles ×N » (chargeur) et « Touchées n/5 ».
class MagazineAndHits extends StatelessWidget {
  const MagazineAndHits({super.key, required this.session});
  final ShootingSession session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final total = s.config.targetCount;
    final fired = s.shots.length;
    final card = BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AlpColors.border),
      borderRadius: BorderRadius.circular(12),
    );
    const label = TextStyle(color: AlpColors.textSecondary, fontSize: 12, height: 1.2);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: 'Chargeur : ${total - fired} balles restantes',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Balles ×${total - fired}', style: label),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Balles tirées d'abord (estompées), comme sur la maquette.
                      for (var i = 0; i < total; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        SizedBox(
                          width: 12.5,
                          height: 20.8,
                          child: Center(
                            child: Transform.rotate(
                              angle: 20 * math.pi / 180,
                              child: SvgPicture.asset(
                                i < fired ? PdtAssets.bulletSpent : PdtAssets.bullet,
                                width: 6,
                                height: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Semantics(
            label: '${s.hits} cibles touchées sur $total',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Touchées', style: label),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${s.hits}', style: const TextStyle(fontSize: 20)),
                        TextSpan(text: '/$total', style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w600, height: 1.2, color: AlpColors.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Toasts ─────────────────────────────

/// Retour d'un tir, au-dessus des cibles : « ✓ +10 Gouttes » ou « ✕ Tir manqué ».
class ShotToast extends StatelessWidget {
  const ShotToast({super.key, required this.outcome, required this.drops});
  final ShotOutcome outcome;
  final int drops;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 20 / 14, color: AlpColors.text);
    return _Chip(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: outcome.isHit
            ? [
                SvgPicture.asset(PdtAssets.toastHit, width: 20, height: 20),
                const SizedBox(width: 4),
                Text('+$drops Gouttes', style: style),
                const SizedBox(width: 4),
                const DropIcon(size: 20),
              ]
            : [
                SizedBox.square(
                  dimension: 20,
                  child: Center(child: SvgPicture.asset(PdtAssets.toastMiss, width: 14.5, height: 14.5)),
                ),
                const SizedBox(width: 4),
                const Text('Tir manqué', style: style),
                if (outcome == ShotOutcome.missBreath) ...[
                  const SizedBox(width: 4),
                  const Text(
                    '· inspiration',
                    style: TextStyle(fontSize: 13, color: AlpColors.textSecondary, height: 20 / 13),
                  ),
                ],
                const SizedBox(width: 2),
              ],
      ),
    );
  }
}

/// Toast sombre d'aide (« Bouge lentement ton téléphone… »).
class DarkToast extends StatelessWidget {
  const DarkToast({super.key, required this.text, this.fontSize = 14});
  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 47),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AlpColors.darkToast,
        border: Border.all(color: AlpColors.textSecondary),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: fontSize, height: 1.2),
      ),
    );
  }
}

// ───────────────────────────── Commandes ─────────────────────────────

/// Gros bouton rond « Tirer » (halo orange à deux anneaux, 112 px).
class ShootButton extends StatelessWidget {
  const ShootButton({super.key, required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Tirer',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedOpacity(
          opacity: onPressed == null ? 0.6 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AlpColors.orange.withValues(alpha: 0.3), shape: BoxShape.circle),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AlpColors.orange.withValues(alpha: 0.4), shape: BoxShape.circle),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(color: AlpColors.orange, shape: BoxShape.circle),
                child: SvgPicture.asset(PdtAssets.shootIcon, width: 32, height: 32),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton rond blanc « Recentrer » (mode Gyroscope).
class RecenterButton extends StatelessWidget {
  const RecenterButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Recentrer la plaque',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x4D000000), blurRadius: 2, offset: Offset(4, 4))],
          ),
          child: SvgPicture.asset(PdtAssets.recenter, width: 28, height: 28),
        ),
      ),
    );
  }
}

/// Dock du bas : bouton Tirer centré, action secondaire éventuelle à droite.
class ShootDock extends StatelessWidget {
  const ShootDock({super.key, required this.onFire, this.trailing});
  final VoidCallback? onFire;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          const Expanded(child: SizedBox()),
          ShootButton(onPressed: onFire),
          Expanded(child: Align(alignment: Alignment.centerRight, child: trailing)),
        ],
      ),
    );
  }
}

/// Jauge de respiration du mode Classique : piste crème, zone de tir bleue,
/// curseur pétrole.
class BreathMeter extends StatelessWidget {
  const BreathMeter({super.key, required this.cursor, this.config = PasDeTirConfig.standard});

  final double cursor;
  final PasDeTirConfig config;

  @override
  Widget build(BuildContext context) {
    final phase = breathPhaseOf(cursor, config);
    final label = switch (phase) {
      BreathPhase.shootingZone => 'zone de tir',
      BreathPhase.inhale => 'inspiration',
      BreathPhase.exhale => 'expiration',
    };
    return Semantics(
      label: 'Respiration simulée : $label',
      excludeSemantics: true,
      child: SizedBox(
        height: 24,
        child: LayoutBuilder(
          builder: (context, cons) {
            final w = cons.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(color: AlpColors.cream, borderRadius: BorderRadius.circular(999)),
                ),
                Positioned(
                  left: w * config.zoneStart,
                  width: w * (config.zoneEnd - config.zoneStart),
                  child: Container(
                    height: 13,
                    decoration: BoxDecoration(color: AlpColors.dropLight, borderRadius: BorderRadius.circular(40)),
                  ),
                ),
                Positioned(
                  left: (w * cursor - 12).clamp(-4.0, w - 20),
                  child: SvgPicture.asset(PdtAssets.breathDot, width: 24, height: 24),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Barre de progression de la maquette (piste crème, remplissage bleu clair).
class RangeProgress extends StatelessWidget {
  const RangeProgress({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: AlpColors.cream, borderRadius: BorderRadius.circular(999)),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(color: AlpColors.dropLight, borderRadius: BorderRadius.circular(40)),
          ),
        ),
      ),
    );
  }
}

/// Décor de montagnes estompé du mode Classique (fondu vers le blanc en bas).
class MountainBackdrop extends StatelessWidget {
  const MountainBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(PdtAssets.mountains, fit: BoxFit.cover, alignment: Alignment.bottomCenter),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00FFFFFF), Colors.white],
                stops: [0, 0.775],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dégradé noir en haut d'écran, pour lire le header sur la caméra.
class TopScrim extends StatelessWidget {
  /// [soft] : version plus discrète, pour le décor photo du Gyroscope.
  const TopScrim({super.key, this.soft = false});
  final bool soft;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [soft ? const Color(0x80000000) : const Color(0xE6000000), const Color(0x00000000)],
            stops: soft ? const [0.0, 0.2] : const [0.018, 0.294],
          ),
        ),
      ),
    );
  }
}

/// Étape numérotée (calibrage gyroscope) ou illustrée (consignes classiques),
/// sur fond crème, cochée une fois validée.
class RangeStepCard extends StatelessWidget {
  const RangeStepCard({super.key, required this.leading, required this.text, this.done = false});
  final Widget leading;
  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AlpColors.cream, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.4, color: AlpColors.text),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedOpacity(
            opacity: done ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(color: AlpColors.orange, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille numérotée pétrole des étapes de calibrage.
class StepNumber extends StatelessWidget {
  const StepNumber(this.number, {super.key});
  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AlpColors.petrol, shape: BoxShape.circle),
      child: Text(
        '$number',
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700, height: 1),
      ),
    );
  }
}

/// Bouton plein 56 px de la feuille du bas (« Je suis prêt », « Calibrer »).
class SheetButton extends StatelessWidget {
  const SheetButton({super.key, required this.label, required this.onPressed, this.primary = true});
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? AlpColors.orange : AlpColors.cream;
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: bg,
          disabledBackgroundColor: bg.withValues(alpha: 0.5),
          foregroundColor: primary ? Colors.white : AlpColors.text,
          disabledForegroundColor: (primary ? Colors.white : AlpColors.text).withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontFamily: AlpText.fontFamily, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
      ),
    );
  }
}

/// Feuille blanche du bas, ombrée, contenant les boutons d'action.
class BottomActionSheet extends StatelessWidget {
  const BottomActionSheet({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 50, offset: Offset(0, 25))],
      ),
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
      child: child,
    );
  }
}

String formatChrono(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
