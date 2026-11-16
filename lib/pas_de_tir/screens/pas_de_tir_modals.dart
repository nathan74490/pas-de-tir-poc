import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/alp_tokens.dart';
import '../../widgets/alp_common.dart';
import '../pas_de_tir_config.dart';
import '../pas_de_tir_logic.dart';
import '../pas_de_tir_result.dart';

// ───────────────────────────── 02_Intro ─────────────────────────────

/// Règles + choix du mode. Retourne le mode choisi, ou null si fermée.
/// Avec [onlyMode] (mode démo), seul ce mode est affiché, sans choix.
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
    final cards = [
      if (_shows(PasDeTirMode.ar, widget.arAvailable))
        _ModeCard(
          selected: _mode == PasDeTirMode.ar,
          icon: const Icon(Icons.view_in_ar_rounded, color: Colors.white, size: 20),
          iconBg: AlpColors.orange,
          title: 'Réalité augmentée',
          subtitle: 'Les cibles apparaissent devant toi, vise avec ton téléphone',
          onTap: () => setState(() => _mode = PasDeTirMode.ar),
        ),
      if (_shows(PasDeTirMode.gyro, widget.gyroAvailable))
        _ModeCard(
          selected: _mode == PasDeTirMode.gyro,
          icon: const Icon(Icons.screen_rotation_alt_rounded, color: Colors.white, size: 20),
          iconBg: AlpColors.petrol,
          title: 'Gyroscope',
          subtitle: 'Vise en bougeant ton téléphone, sans caméra',
          onTap: () => setState(() => _mode = PasDeTirMode.gyro),
        ),
      if (_shows(PasDeTirMode.classic, true))
        _ModeCard(
          selected: _mode == PasDeTirMode.classic,
          icon: const TargetGlyph(size: 20, color: AlpColors.text),
          iconBg: const Color(0xFFEFEDE7),
          title: 'Classique',
          subtitle: "Pas de tir à l'écran, sans caméra",
          onTap: () => setState(() => _mode = PasDeTirMode.classic),
        ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModalTop(onClose: () => Navigator.pop(context)),
          const SizedBox(height: 14),
          const Text(
            'Pas de tir',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tu es arrivé au pas de tir. Reprends ton souffle, vise et touche un maximum de cibles.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AlpColors.textSecondary, fontSize: 15, height: 1.35),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AlpRadii.card),
            ),
            child: Column(
              children: [
                _RuleRow(
                  icon: const TargetGlyph(size: 18),
                  title: '${c.targetCount} cibles, ${c.targetCount} balles',
                  subtitle: 'Une balle par cible, comme au biathlon',
                ),
                const SizedBox(height: 10),
                _RuleRow(
                  icon: const DropBadge(size: 18),
                  title: '+${c.dropsPerTarget} gouttes par cible',
                  subtitle: 'Une cible ratée ne rapporte rien',
                ),
                const SizedBox(height: 10),
                _RuleRow(
                  icon: const Icon(Icons.timer_outlined, size: 18, color: AlpColors.petrol),
                  title: '${c.timeLimit.inSeconds} secondes',
                  subtitle: 'Le chrono démarre au premier tir',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            widget.onlyMode == null ? 'Choisis ton mode' : 'Ton mode',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 10),
          // Deux modes côte à côte (maquette) ; au-delà, trop étroit : on les empile.
          if (cards.length <= 2)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, card) in cards.indexed) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: card),
                  ],
                ],
              ),
            )
          else
            Column(
              children: [
                for (final (i, card) in cards.indexed) ...[if (i > 0) const SizedBox(height: 10), card],
              ],
            ),
          const SizedBox(height: 16),
          AlpPrimaryButton(label: 'Commencer', onPressed: () => Navigator.pop(context, _mode)),
        ],
      ),
    );
  }
}

class _ModalTop extends StatelessWidget {
  const _ModalTop({required this.onClose, this.icon});
  final VoidCallback onClose;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: HaloIcon(child: icon ?? const TargetGlyph(size: 22, color: Colors.white)),
        ),
        Align(
          alignment: Alignment.topLeft,
          child: ModalCloseButton(onPressed: onClose),
        ),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.icon, required this.title, required this.subtitle});
  final Widget icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: icon,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(subtitle, style: const TextStyle(color: AlpColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final Widget icon;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AlpRadii.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AlpRadii.card),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AlpRadii.card),
              border: Border.all(color: selected ? AlpColors.orange : Colors.transparent, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(9)),
                      alignment: Alignment.center,
                      child: icon,
                    ),
                    const Spacer(),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? AlpColors.orange : Colors.transparent,
                        border: selected ? null : Border.all(color: const Color(0xFFCFCFCF), width: 1.5),
                      ),
                      child: selected ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, height: 1.15)),
                const SizedBox(height: 6),
                Text(subtitle, style: const TextStyle(color: AlpColors.textSecondary, fontSize: 12.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── 08_AR_Camera ─────────────────────────────

enum CameraChoice { allow, classic }

Future<CameraChoice?> showCameraPermissionModal(BuildContext context) {
  return showCreamModal<CameraChoice>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModalTop(
            onClose: () => Navigator.pop(ctx),
            icon: const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 14),
          const Text(
            'Active ta caméra',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            "Le pas de tir en réalité augmentée utilise la caméra pour placer les cibles devant toi. Aucune image n'est enregistrée.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AlpColors.textSecondary, fontSize: 14.5, height: 1.35),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: AlpSecondaryButton(
                  label: 'Mode classique',
                  onPressed: () => Navigator.pop(ctx, CameraChoice.classic),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AlpPrimaryButton(label: 'Autoriser', onPressed: () => Navigator.pop(ctx, CameraChoice.allow)),
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
  final quit = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AlpColors.modal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AlpRadii.modal)),
      title: const Text('Quitter le pas de tir ?'),
      content: Text(
        drops > 0
            ? 'Tu conserves les $drops gouttes déjà gagnées. Le pas de tir sera marqué comme joué.'
            : 'Le pas de tir sera marqué comme joué.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuer à tirer')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AlpColors.orange),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Quitter'),
        ),
      ],
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

class PasDeTirResultCard extends StatelessWidget {
  const PasDeTirResultCard({super.key, required this.result, required this.onContinue});
  final PasDeTirResult result;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final r = result;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModalTop(onClose: onContinue),
          const SizedBox(height: 14),
          // Libellé unique fourni par la maquette — à décliner selon le score (point produit).
          const Text(
            'Belle série !',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          Text(
            '${r.hits} cible${r.hits > 1 ? 's' : ''} touchée${r.hits > 1 ? 's' : ''} sur ${r.shots.length}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AlpColors.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 14),
          ShotRecap(shots: r.shots, size: 44),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatTile(label: 'Précision', value: '${r.precision} %'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(label: 'Temps', value: '${r.duration.inSeconds} s'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatTile(label: 'Mode', value: r.mode.shortLabel),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AlpRadii.card)),
            child: Column(
              children: [
                _DropLine(
                  leading: const DropBadge(size: 16),
                  label: 'Cibles touchées (${r.hits} × ${r.config.dropsPerTarget})',
                  value: '+${r.drops}',
                ),
                if (r.misses > 0) ...[
                  const Divider(height: 1),
                  _DropLine(
                    leading: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(color: Color(0xFFDAD5CE), shape: BoxShape.circle),
                    ),
                    label: 'Cible${r.misses > 1 ? 's' : ''} ratée${r.misses > 1 ? 's' : ''} (${r.misses})',
                    value: '+0',
                    muted: true,
                  ),
                ],
                if (r.capturePath != null) ...[
                  const Divider(height: 1),
                  _DropLine(
                    leading: const Icon(Icons.photo_camera_outlined, size: 18, color: AlpColors.petrol),
                    label: 'Capture AR enregistrée',
                    trailing: TextButton(
                      onPressed: () => _showCapture(context, r.capturePath!),
                      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                      child: const Text(
                        'Voir',
                        style: TextStyle(color: AlpColors.orange, fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AlpPrimaryButton(label: "Continuer l'épreuve", onPressed: onContinue),
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

/// Récap des 5 cibles : disque blanc cerclé de noir = touchée, noir + ✕ = ratée.
class ShotRecap extends StatelessWidget {
  const ShotRecap({super.key, required this.shots, this.size = 44});
  final List<ShotOutcome> shots;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: shots.map((s) => s.isHit ? 'touchée' : 'ratée').join(', '),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final s in shots)
            Container(
              margin: EdgeInsets.symmetric(horizontal: size * 0.1),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: s.isHit ? Colors.white : const Color(0xFF151515),
                border: Border.all(color: const Color(0xFF151515), width: size * 0.13),
              ),
              child: s.isHit ? null : Icon(Icons.close_rounded, color: AlpColors.orange, size: size * 0.45),
            ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AlpRadii.card)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: AlpColors.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 2),
          FittedBox(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ),
        ],
      ),
    );
  }
}

class _DropLine extends StatelessWidget {
  const _DropLine({required this.leading, required this.label, this.value, this.trailing, this.muted = false});
  final Widget leading;
  final String label;
  final String? value;
  final Widget? trailing;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 15, color: muted ? AlpColors.textSecondary : AlpColors.text)),
          ),
          if (value != null)
            Text(
              value!,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: muted ? AlpColors.textSecondary : AlpColors.text,
              ),
            ),
          ?trailing,
        ],
      ),
    );
  }
}
