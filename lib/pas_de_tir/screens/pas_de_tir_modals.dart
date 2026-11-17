import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/alp_tokens.dart';
import '../../widgets/alp_common.dart';
import '../pas_de_tir_config.dart';
import '../pas_de_tir_logic.dart';
import '../pas_de_tir_result.dart';
import '../widgets/shooting_widgets.dart';

const _titleStyle = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2, color: AlpColors.ink);
const _subtitleStyle = TextStyle(fontSize: 14, height: 20 / 14, color: AlpColors.slate);

// ───────────────────────────── 02_Intro ─────────────────────────────

/// Règles + choix du mode. Retourne le mode choisi, ou null si fermée.
/// Avec [onlyMode] (mode démo), seul ce mode est proposé, sans choix.
Future<PasDeTirMode?> showPasDeTirIntro(
  BuildContext context, {
  required bool arAvailable,
  bool gyroAvailable = false,
  PasDeTirMode? onlyMode,
  PasDeTirConfig config = PasDeTirConfig.standard,
}) {
  return showCreamModal<PasDeTirMode>(
    context,
    builder: (ctx) =>
        _IntroModal(arAvailable: arAvailable, gyroAvailable: gyroAvailable, onlyMode: onlyMode, config: config),
  );
}

class _IntroModal extends StatefulWidget {
  const _IntroModal({required this.arAvailable, required this.gyroAvailable, required this.config, this.onlyMode});
  final bool arAvailable;
  final bool gyroAvailable;
  final PasDeTirMode? onlyMode;
  final PasDeTirConfig config;

  @override
  State<_IntroModal> createState() => _IntroModalState();
}

class _IntroModalState extends State<_IntroModal> {
  late PasDeTirMode _mode =
      widget.onlyMode ??
      (widget.arAvailable
          ? PasDeTirMode.ar
          : widget.gyroAvailable
          ? PasDeTirMode.gyro
          : PasDeTirMode.classic);

  bool _shows(PasDeTirMode m, bool available) => widget.onlyMode == null ? available : widget.onlyMode == m;

  @override
  Widget build(BuildContext context) {
    final c = widget.config;
    final modes = [
      if (_shows(PasDeTirMode.ar, widget.arAvailable))
        (PasDeTirMode.ar, Icons.view_in_ar_rounded, 'Réalité augmentée', 'Les cibles apparaissent devant toi'),
      if (_shows(PasDeTirMode.gyro, widget.gyroAvailable))
        (PasDeTirMode.gyro, Icons.screen_rotation_alt_rounded, 'Gyroscope', 'Vise en bougeant ton téléphone'),
      if (_shows(PasDeTirMode.gyroCamera, widget.gyroAvailable))
        (
          PasDeTirMode.gyroCamera,
          Icons.photo_camera_outlined,
          'Gyroscope + caméra',
          'Les cibles sur l’image de ta caméra',
        ),
      if (_shows(PasDeTirMode.classic, true))
        (PasDeTirMode.classic, Icons.touch_app_outlined, 'Classique', "Pas de tir à l'écran, sans capteur"),
    ];
    // Le bouton reste visible en bas ; seul le contenu défile si l'écran est
    // petit ou la taille de texte grande.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(child: _introContent(c, modes)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: _CtaButton(label: 'Commencer', onPressed: () => Navigator.pop(context, _mode)),
        ),
      ],
    );
  }

  Widget _introContent(PasDeTirConfig c, List<(PasDeTirMode, IconData, String, String)> modes) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModalTop(
            onClose: () => Navigator.pop(context),
            icon: const _IntroBadge(),
            gap: 12,
          ),
          const SizedBox(height: 12),
          const Text('Pas de tir', textAlign: TextAlign.center, style: _titleStyle),
          const SizedBox(height: 8),
          const Text(
            'Vise et touche un maximum de cibles !',
            textAlign: TextAlign.center,
            style: _subtitleStyle,
          ),
          const SizedBox(height: 20),
          _InfoCard(
            icon: SvgPicture.asset(PdtAssets.ruleTarget, width: 24, height: 24),
            title: '${c.targetCount} cibles, ${c.targetCount} balles',
          ),
          const SizedBox(height: 8),
          _InfoCard(
            icon: const DropIcon(size: 22),
            title: '+${c.dropsPerTarget} Gouttes par cible',
          ),
          const SizedBox(height: 8),
          _InfoCard(
            icon: SvgPicture.asset(PdtAssets.ruleClock, width: 24, height: 24),
            title: '${c.timeLimit.inSeconds} secondes',
          ),
          // Choix du mode (propre au POC : la maquette ne montre que le mode retenu).
          if (modes.length > 1) ...[
            const SizedBox(height: 16),
            const Text(
              'Choisis ton mode',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 20 / 14),
            ),
            const SizedBox(height: 8),
            for (final (i, (mode, icon, title, subtitle)) in modes.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              _InfoCard(
                icon: Icon(icon, size: 24, color: AlpColors.petrol),
                title: title,
                subtitle: subtitle,
                selected: _mode == mode,
                onTap: () => setState(() => _mode = mode),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Icône du pas de tir sur double anneau orange (« GAMES in map »).
class _IntroBadge extends StatelessWidget {
  const _IntroBadge();

  @override
  Widget build(BuildContext context) {
    final ring = AlpColors.orange.withValues(alpha: 0.5);
    return Container(
      padding: const EdgeInsets.all(10.67),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 1.33)),
      child: Container(
        width: 50.67,
        height: 50.67,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: 5.33),
        ),
        child: SvgPicture.asset(PdtAssets.introIcon, width: 26.67, height: 26.67),
      ),
    );
  }
}

/// Icône sur halo orange à deux anneaux (modale caméra).
class _HaloBadge extends StatelessWidget {
  const _HaloBadge({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AlpColors.orange.withValues(alpha: 0.1), shape: BoxShape.circle),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AlpColors.orange.withValues(alpha: 0.2), shape: BoxShape.circle),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: const BoxDecoration(color: AlpColors.orange, shape: BoxShape.circle),
          child: child,
        ),
      ),
    );
  }
}

/// Bouton ✕ gris des modales + icône centrée.
class _ModalTop extends StatelessWidget {
  const _ModalTop({required this.onClose, required this.icon, this.gap = 0});
  final VoidCallback onClose;
  final Widget icon;

  /// Espace entre la ligne du bouton ✕ et l'icône.
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            button: true,
            label: 'Fermer',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onClose,
              child: SvgPicture.asset(PdtAssets.modalClose, width: 32, height: 32),
            ),
          ),
        ),
        SizedBox(height: gap),
        Center(child: icon),
      ],
    );
  }
}

/// Carte blanche bordée (règles du jeu, choix du mode).
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, this.subtitle, this.selected, this.onTap});
  final Widget icon;
  final String title;
  final String? subtitle;

  /// null : carte non sélectionnable.
  final bool? selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = selected ?? false;
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AlpColors.orange : AlpColors.border,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                SizedBox.square(dimension: 24, child: Center(child: icon)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 20 / 14)),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: const TextStyle(fontSize: 12, height: 1.4, color: AlpColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                if (selected != null)
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? AlpColors.orange : Colors.transparent,
                      border: isSelected ? null : Border.all(color: const Color(0xFFCFCFCF), width: 1.5),
                    ),
                    child: isSelected ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton des modales : orange plein, ou texte seul ([filled] à false).
class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.label, required this.onPressed, this.filled = true});
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: filled ? AlpColors.orange : Colors.transparent,
          foregroundColor: filled ? Colors.white : AlpColors.text,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontFamily: AlpText.fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
      ),
    );
  }
}

// ───────────────────────────── 08_AR_Camera ─────────────────────────────

enum CameraChoice { allow, classic }

/// [forAr] à false : texte du mode Gyroscope + caméra.
Future<CameraChoice?> showCameraPermissionModal(BuildContext context, {bool forAr = true}) {
  return showCreamModal<CameraChoice>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModalTop(
            onClose: () => Navigator.pop(ctx),
            icon: _HaloBadge(child: SvgPicture.asset(PdtAssets.camera, width: 24, height: 24)),
          ),
          const SizedBox(height: 28),
          const Text('Active ta caméra', textAlign: TextAlign.center, style: _titleStyle),
          const SizedBox(height: 4),
          Text(
            forAr
                ? 'Le pas de tir en réalité augmentée utilise ta caméra pour placer des cibles virtuelles '
                      "autour de toi. Aucune image n'est enregistrée."
                : "Les cibles s'affichent sur l'image de ta caméra et tu vises en bougeant ton téléphone. "
                      "Aucune image n'est enregistrée.",
            textAlign: TextAlign.center,
            style: _subtitleStyle,
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: _CtaButton(
                  label: 'Mode classique',
                  filled: false,
                  onPressed: () => Navigator.pop(ctx, CameraChoice.classic),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CtaButton(label: 'Autoriser', onPressed: () => Navigator.pop(ctx, CameraChoice.allow)),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ───────────────────────────── Quitter ─────────────────────────────

Future<bool> confirmQuitShooting(BuildContext context, {required int drops}) async {
  final quit = await showCreamModal<bool>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Quitter le pas de tir ?', textAlign: TextAlign.center, style: _titleStyle),
          const SizedBox(height: 8),
          Text(
            drops > 0
                ? 'Tu conserves les $drops Gouttes déjà gagnées. Le pas de tir sera marqué comme joué.'
                : 'Le pas de tir sera marqué comme joué.',
            textAlign: TextAlign.center,
            style: _subtitleStyle,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _CtaButton(label: 'Continuer', filled: false, onPressed: () => Navigator.pop(ctx, false)),
              ),
              const SizedBox(width: 12),
              Expanded(child: _CtaButton(label: 'Quitter', onPressed: () => Navigator.pop(ctx, true))),
            ],
          ),
        ],
      ),
    ),
  );
  return quit ?? false;
}

// ─────────────────────────── 07 / 14 Résultat ───────────────────────────

Future<void> showPasDeTirResult(BuildContext context, PasDeTirResult result) {
  return showCreamModal<void>(
    context,
    barrierColor: const Color(0x99000000),
    builder: (ctx) => PasDeTirResultCard(result: result, onContinue: () => Navigator.pop(ctx)),
  );
}

/// Titre du résultat selon le score (la maquette ne montre que « Belle série ! »).
String resultTitle(int hits, int total) {
  if (hits == total) return 'Sans faute !';
  if (hits * 2 > total) return 'Belle série !';
  if (hits > 0) return 'Bien essayé !';
  return 'Pas cette fois !';
}

class PasDeTirResultCard extends StatelessWidget {
  const PasDeTirResultCard({super.key, required this.result, required this.onContinue});
  final PasDeTirResult result;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final rows = <Widget>[
      _StatRow(
        label: 'Cibles touchées (${r.hits})',
        value: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text('+${r.drops}', style: _StatRow.valueStyle), const SizedBox(width: 4), const DropIcon(size: 16)],
        ),
      ),
      _StatRow(label: 'Précision', value: Text('${r.precision} %', style: _StatRow.valueStyle)),
      _StatRow(label: 'Temps', value: Text('${r.duration.inSeconds} s', style: _StatRow.valueStyle)),
      if (r.capturePath != null)
        _StatRow(
          label: 'Capture AR enregistrée',
          value: GestureDetector(
            onTap: () => _showCapture(context, r.capturePath!),
            child: const Text(
              'Voir',
              style: TextStyle(color: AlpColors.orange, fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(resultTitle(r.hits, r.shots.length), textAlign: TextAlign.center, style: _titleStyle),
          const SizedBox(height: 8),
          Text(
            '${r.hits}/${r.shots.length} cible${r.hits > 1 ? 's' : ''} touchée${r.hits > 1 ? 's' : ''}',
            textAlign: TextAlign.center,
            style: _subtitleStyle,
          ),
          const SizedBox(height: 24),
          ShotRecap(shots: r.shots, size: 53),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(
              color: Colors.white,
              child: Column(
                children: [
                  for (final (i, row) in rows.indexed) ...[
                    if (i > 0) const Divider(height: 0.5, thickness: 0.5, color: AlpColors.border),
                    row,
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _CtaButton(label: "Continuer l'épreuve", onPressed: onContinue),
        ],
      ),
    );
  }

  void _showCapture(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AlpRadii.modal)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.file(File(path), fit: BoxFit.cover),
            Padding(
              padding: const EdgeInsets.all(12),
              child: AlpPrimaryButton(label: 'Fermer', onPressed: () => Navigator.pop(ctx)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Récap des cibles : pastille pétrole cochée = touchée, orange barrée = ratée.
class ShotRecap extends StatelessWidget {
  const ShotRecap({super.key, required this.shots, this.size = 53});
  final List<ShotOutcome> shots;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: shots.map((s) => s.isHit ? 'touchée' : 'ratée').join(', '),
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, s) in shots.indexed) ...[
              if (i > 0) SizedBox(width: size * 12 / 53),
              SizedBox.square(
                dimension: size,
                child: s.isHit
                    ? SvgPicture.asset(PdtAssets.recapHit, width: size, height: size)
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          SvgPicture.asset(PdtAssets.recapMissDisc, width: size, height: size),
                          SvgPicture.asset(PdtAssets.recapMissX, width: size * 0.291, height: size * 0.291),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final Widget value;

  static const valueStyle = TextStyle(fontWeight: FontWeight.w600, fontSize: 14, height: 1, color: AlpColors.text);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AlpColors.textSecondary),
              ),
            ),
            value,
          ],
        ),
      ),
    );
  }
}
