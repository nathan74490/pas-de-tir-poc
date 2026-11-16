import 'package:flutter/material.dart';

import '../theme/alp_tokens.dart';

/// Composants génériques. Dans l'app réelle, remplacer par les composants
/// partagés existants (boutons, modales crème, toasts…).

class AlpPrimaryButton extends StatelessWidget {
  const AlpPrimaryButton({super.key, required this.label, required this.onPressed, this.height = 48});

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AlpColors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AlpRadii.button)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class AlpSecondaryButton extends StatelessWidget {
  const AlpSecondaryButton({super.key, required this.label, required this.onPressed, this.height = 48});

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: AlpColors.neutralButton,
          foregroundColor: AlpColors.text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AlpRadii.button)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        child: FittedBox(child: Text(label, maxLines: 1)),
      ),
    );
  }
}

/// Bouton ✕ rond gris des modales crème.
class ModalCloseButton extends StatelessWidget {
  const ModalCloseButton({super.key, required this.onPressed, this.semanticLabel = 'Fermer'});

  final VoidCallback onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkResponse(
        onTap: onPressed,
        radius: 24,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(color: Color(0xFF79726C), shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, size: 17, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icône « cible » : anneaux concentriques.
class TargetGlyph extends StatelessWidget {
  const TargetGlyph({super.key, this.size = 24, this.color = AlpColors.petrol});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _TargetGlyphPainter(color));
  }
}

class _TargetGlyphPainter extends CustomPainter {
  _TargetGlyphPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final s = size.shortestSide;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.1;
    canvas.drawCircle(c, s * 0.42, stroke);
    canvas.drawCircle(c, s * 0.22, stroke);
    canvas.drawCircle(c, s * 0.08, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TargetGlyphPainter old) => old.color != color;
}

/// Pastille « goutte d'effort ».
class DropBadge extends StatelessWidget {
  const DropBadge({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: AlpColors.petrol, shape: BoxShape.circle),
      child: Icon(Icons.water_drop, size: size * 0.6, color: AlpColors.cyan),
    );
  }
}

/// Icône sur halo orange (en-tête des modales crème).
class HaloIcon extends StatelessWidget {
  const HaloIcon({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(color: AlpColors.orange.withValues(alpha: 0.13), shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(color: AlpColors.orange.withValues(alpha: 0.28), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(color: AlpColors.orange, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

/// Pastille ronde à liseré (icônes de jeux dans les listes).
class GameIconBadge extends StatelessWidget {
  const GameIconBadge({super.key, required this.child, this.size = 40});
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF6FA3B3), width: 2),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class PetrolDisc extends StatelessWidget {
  const PetrolDisc({super.key, required this.icon, this.size = 20});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: AlpColors.petrol, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.62, color: Colors.white),
    );
  }
}

/// Modale crème centrée sur fond assombri.
Future<T?> showCreamModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = false,
  Color barrierColor = const Color(0x8C000000),
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Fermer',
    barrierColor: barrierColor,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Material(
            color: AlpColors.modal,
            borderRadius: BorderRadius.circular(AlpRadii.modal),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: builder(ctx),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

/// Toast « pilule » blanc (Touché / Raté).
class PillToast extends StatelessWidget {
  const PillToast({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: child,
    );
  }
}
