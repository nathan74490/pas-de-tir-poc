import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/alp_tokens.dart';
import '../../widgets/alp_common.dart';
import '../pas_de_tir_config.dart';
import '../pas_de_tir_logic.dart';
import '../shooting_session.dart';

/// Géométrie de la plaque de 5 cibles, en coordonnées locales à la plaque.
class PlateGeometry {
  const PlateGeometry(this.width, {this.targetCount = 5});

  final double width;
  final int targetCount;

  double get height => width * 0.286;
  double get targetRadius => width * 0.068;
  double get _step => width * 0.188;

  Offset targetCenter(int i) => Offset(width * 0.122 + _step * i, height * 0.40);
  Offset numberCenter(int i) => Offset(width * 0.122 + _step * i, height * 0.80);
}

/// Plaque noire de cibles numérotées. Une cible touchée devient un disque
/// blanc, une cible ratée reste noire avec un impact orange.
class TargetPlate extends StatelessWidget {
  const TargetPlate({super.key, required this.geometry, required this.shots, this.legs = false});

  final PlateGeometry geometry;
  final List<ShotOutcome> shots;

  /// Pieds et ombre au sol (plaque virtuelle AR).
  final bool legs;

  @override
  Widget build(BuildContext context) {
    final legHeight = legs ? geometry.height * 0.75 : 0.0;
    return CustomPaint(
      size: Size(geometry.width, geometry.height + legHeight),
      painter: _PlatePainter(geometry, shots, legHeight),
    );
  }
}

class _PlatePainter extends CustomPainter {
  _PlatePainter(this.g, this.shots, this.legHeight);

  final PlateGeometry g;
  final List<ShotOutcome> shots;
  final double legHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (legHeight > 0) {
      final legPaint = Paint()..color = const Color(0xFF4A4A4A);
      final shadow = Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(g.width / 2, g.height + legHeight), width: g.width * 0.9, height: 14),
        shadow,
      );
      for (final x in [g.width * 0.08, g.width * 0.9]) {
        canvas.drawRect(Rect.fromLTWH(x, g.height - 4, 7, legHeight), legPaint);
      }
    }

    final plate = RRect.fromRectAndRadius(Offset.zero & Size(g.width, g.height), const Radius.circular(10));
    canvas.drawRRect(
      plate.shift(const Offset(0, 6)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(plate, Paint()..color = const Color(0xFF151515));

    final r = g.targetRadius;
    for (var i = 0; i < g.targetCount; i++) {
      final c = g.targetCenter(i);
      final outcome = i < shots.length ? shots[i] : null;
      if (outcome == ShotOutcome.hit) {
        canvas.drawCircle(c, r, Paint()..color = const Color(0xFFDCDCDC));
        canvas.drawCircle(c.translate(0, -r * 0.08), r * 0.9, Paint()..color = Colors.white);
      } else {
        canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0B0B0B));
        canvas.drawCircle(
          c,
          r - r * 0.09,
          Paint()
            ..color = const Color(0xFFF0EEE8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.18,
        );
        if (outcome != null && outcome != ShotOutcome.notFired) {
          final impact = c + Offset.fromDirection(-0.6, r * 0.85);
          canvas.drawCircle(impact, r * 0.3, Paint()..color = AlpColors.orange.withValues(alpha: 0.35));
          canvas.drawCircle(impact, r * 0.18, Paint()..color = AlpColors.orange);
        }
      }
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(color: const Color(0xFFBDBDBD), fontSize: g.width * 0.036, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, g.numberCenter(i) - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_PlatePainter old) => true;
}

/// Réticule de visée : cercle, mire pointillée, croix et point central.
class Reticle extends StatelessWidget {
  const Reticle({super.key, required this.color, this.size = 100, this.pulse});

  final Color color;
  final double size;

  /// Progression 0→1 de l'anneau qui pulse (touché en AR), ou null.
  final double? pulse;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(size: Size.square(size), painter: _ReticlePainter(color, pulse)),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  _ReticlePainter(this.color, this.pulse);
  final Color color;
  final double? pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.48;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5;
    canvas.drawCircle(c, r, shadow);
    canvas.drawCircle(c, r, p);

    if (pulse != null) {
      canvas.drawCircle(
        c,
        r * (1.0 + 0.3 * pulse!),
        Paint()
          ..color = color.withValues(alpha: (1 - pulse!) * 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    // Mire pointillée.
    final inner = r * 0.54;
    const dashes = 18;
    for (var i = 0; i < dashes; i++) {
      final a0 = i * 2 * math.pi / dashes;
      canvas.drawArc(Rect.fromCircle(center: c, radius: inner), a0, math.pi / dashes,
          false, p..strokeWidth = 1.8);
    }
    p.strokeWidth = 2.6;

    // Croix : traits qui débordent du cercle.
    final inS = r * 0.62, outS = r * 1.1;
    for (final d in [const Offset(1, 0), const Offset(-1, 0), const Offset(0, 1), const Offset(0, -1)]) {
      canvas.drawLine(c + d * inS, c + d * outS, p);
    }
    canvas.drawCircle(c, 3.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ReticlePainter old) => old.color != color || old.pulse != pulse;
}

/// Jauge « Respiration · simulée ».
class BreathGauge extends StatelessWidget {
  const BreathGauge({super.key, required this.cursor, this.dark = false, this.config = PasDeTirConfig.standard});

  final double cursor;
  final bool dark;
  final PasDeTirConfig config;

  @override
  Widget build(BuildContext context) {
    final phase = breathPhaseOf(cursor, config);
    final (label, color) = switch (phase) {
      BreathPhase.shootingZone => ('Zone de tir', dark ? AlpColors.cyan : AlpColors.petrol),
      BreathPhase.inhale => ('Inspiration', AlpColors.orange),
      BreathPhase.exhale => ('Expire…', dark ? AlpColors.cyan : AlpColors.petrol),
    };
    final fg = dark ? Colors.white : AlpColors.text;
    final secondary = dark ? Colors.white70 : AlpColors.textSecondary;

    return Semantics(
      label: 'Respiration simulée : $label',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.air, size: 18, color: fg),
              const SizedBox(width: 8),
              Text('Respiration', style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 15)),
              if (!dark) Text('  · simulée', style: TextStyle(color: secondary, fontSize: 14)),
              const Spacer(),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 24,
            child: LayoutBuilder(builder: (context, cons) {
              final w = cons.maxWidth;
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: dark ? Colors.white24 : const Color(0xFFECEAE4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Positioned(
                    left: w * config.zoneStart,
                    width: w * (config.zoneEnd - config.zoneStart),
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(color: AlpColors.cyan, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  Positioned(
                    left: (w * cursor - 11).clamp(-2, w - 20),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AlpColors.orange, width: 3.5),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 6),
          DefaultTextStyle(
            style: TextStyle(color: secondary, fontSize: 12),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Inspire'), Text('Tire ici'), Text('Inspire')],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chargeur : balles tirées grisées.
class Magazine extends StatelessWidget {
  const Magazine({super.key, required this.total, required this.fired, this.dark = false, this.scale = 1});

  final int total;
  final int fired;
  final bool dark;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargeur : ${total - fired} balles restantes',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            Padding(
              padding: EdgeInsets.only(right: 6 * scale),
              child: _Bullet(spent: i < fired, dark: dark, scale: scale),
            ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.spent, required this.dark, required this.scale});
  final bool spent;
  final bool dark;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final body = spent
        ? (dark ? Colors.white24 : const Color(0xFFD6D2CB))
        : const Color(0xFFE8B54A);
    final tip = spent ? (dark ? Colors.white30 : const Color(0xFFC9C5BE)) : const Color(0xFFB8862B);
    return Column(
      children: [
        Container(
          width: 12 * scale,
          height: 8 * scale,
          decoration: BoxDecoration(color: tip, borderRadius: BorderRadius.vertical(top: Radius.circular(6 * scale))),
        ),
        Container(
          width: 12 * scale,
          height: 23 * scale,
          decoration: BoxDecoration(color: body, borderRadius: BorderRadius.vertical(bottom: Radius.circular(2 * scale))),
        ),
      ],
    );
  }
}

/// Gros bouton rond « Tirer » (92 px, toujours parfaitement rond).
class ShootButton extends StatelessWidget {
  const ShootButton({super.key, required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Tirer',
      excludeSemantics: true,
      child: Container(
        width: 108,
        height: 108,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AlpColors.orange.withValues(alpha: 0.12),
          border: Border.all(color: AlpColors.orange.withValues(alpha: 0.25), width: 1.5),
        ),
        alignment: Alignment.center,
        child: SizedBox.square(
          dimension: 92,
          child: Material(
            color: onPressed == null ? AlpColors.orange.withValues(alpha: 0.6) : AlpColors.orange,
            shape: const CircleBorder(),
            elevation: 6,
            shadowColor: AlpColors.orange,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TargetGlyph(size: 26, color: Colors.white),
                  SizedBox(height: 4),
                  Text('Tirer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// HUD flottant des modes où l'on vise en bougeant le téléphone (AR,
/// Gyroscope) : chargeur, cibles touchées, jauge de respiration (si active) et bouton Tirer,
/// en surimpression d'un décor plein écran. À placer dans un [Stack].
List<Widget> floatingShootingHud(ShootingSession s, EdgeInsets pad, {required VoidCallback onFire}) {
  final c = s.config;
  const pill = Color(0x80404A50);
  return [
    Positioned(
      left: 16,
      top: pad.top + 74,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        decoration: BoxDecoration(color: pill, borderRadius: BorderRadius.circular(AlpRadii.card)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Chargeur', style: TextStyle(color: Colors.white, fontSize: 13)),
          const SizedBox(height: 4),
          Magazine(total: c.targetCount, fired: s.shots.length, dark: true, scale: 0.9),
        ]),
      ),
    ),
    Positioned(
      right: 16,
      top: pad.top + 74,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        decoration: BoxDecoration(color: pill, borderRadius: BorderRadius.circular(AlpRadii.card)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Text('Touchées', style: TextStyle(color: Colors.white, fontSize: 13)),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: '${s.hits}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            TextSpan(text: '/${c.targetCount}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ])),
        ]),
      ),
    ),
    Positioned(
      left: 16,
      right: 16,
      bottom: pad.bottom + 16,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
        decoration: BoxDecoration(color: const Color(0x99262A2C), borderRadius: BorderRadius.circular(22)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (c.breathing) ...[
                BreathGauge(cursor: s.cursor, dark: true, config: c),
                const SizedBox(height: 8),
              ],
              Row(children: [
                const DropBadge(size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('+${s.drops} gouttes · bouge ton téléphone pour viser',
                      style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                ),
              ]),
            ]),
          ),
          ShootButton(onPressed: s.canFire ? onFire : null),
        ]),
      ),
    ),
  ];
}

/// Header du tir : ✕, « PAS DE TIR », badge, chrono.
class ShootingHeader extends StatelessWidget {
  const ShootingHeader({
    super.key,
    required this.badge,
    required this.chrono,
    required this.onClose,
    this.translucent = true,
  });

  final String? badge;
  final String chrono;
  final VoidCallback onClose;

  /// Pastilles translucides sur décor (vs blanches sur fond crème).
  final bool translucent;

  @override
  Widget build(BuildContext context) {
    final pillColor = translucent ? const Color(0x80404A50) : Colors.white;
    final fg = translucent ? Colors.white : AlpColors.text;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: 'Quitter le pas de tir',
            excludeSemantics: true,
            child: Material(
              color: pillColor,
              borderRadius: BorderRadius.circular(AlpRadii.button),
              child: InkWell(
                borderRadius: BorderRadius.circular(AlpRadii.button),
                onTap: onClose,
                child: SizedBox(width: 44, height: 44, child: Icon(Icons.close_rounded, color: fg)),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text('PAS DE TIR',
                    style: AlpText.condensed.copyWith(
                      color: fg,
                      fontSize: 24,
                      shadows: translucent ? const [Shadow(color: Color(0x55000000), blurRadius: 6)] : null,
                    )),
                if (badge != null)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0x99404A50), borderRadius: BorderRadius.circular(20)),
                    child: Text(badge!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
              ],
            ),
          ),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: pillColor, borderRadius: BorderRadius.circular(AlpRadii.button)),
            child: Row(
              children: [
                Icon(Icons.timer_outlined, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(chrono,
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.w800, fontSize: 16, fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Toast de résultat d'un tir.
class ShotToast extends StatelessWidget {
  const ShotToast({super.key, required this.outcome, required this.drops});
  final ShotOutcome outcome;
  final int drops;

  @override
  Widget build(BuildContext context) {
    if (outcome.isHit) {
      return PillToast(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const PetrolDisc(icon: Icons.check_rounded, size: 22),
          const SizedBox(width: 10),
          const Text('Touché !', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(width: 10),
          Text('+$drops', style: const TextStyle(color: AlpColors.petrol, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(width: 4),
          const DropBadge(size: 16),
        ]),
      );
    }
    final reason = outcome == ShotOutcome.missAim ? 'Hors de la cible' : "Tiré pendant l'inspiration";
    return PillToast(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(color: AlpColors.orange, shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
        ),
        const SizedBox(width: 10),
        const Text('Raté', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(width: 8),
        Text(reason, style: const TextStyle(color: AlpColors.textSecondary, fontSize: 14)),
      ]),
    );
  }
}

String formatChrono(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
