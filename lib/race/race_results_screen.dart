import 'package:flutter/material.dart';

import '../pas_de_tir/pas_de_tir_flow.dart';
import '../pas_de_tir/pas_de_tir_logic.dart';
import '../theme/alp_tokens.dart';
import '../widgets/alp_common.dart';
import 'race_state.dart';

/// 16 — Résultats de l'épreuve.
class RaceResultsScreen extends StatelessWidget {
  const RaceResultsScreen({super.key, required this.race});
  final RaceState race;

  Future<void> _replay(BuildContext context) async {
    final result = await runPasDeTir(context, replay: true);
    if (result != null) race.recordPasDeTir(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: race,
          builder: (context, _) {
            final pdt = race.pasDeTir;
            final pdtDrops = pdt?.drops ?? 0;
            final games = RaceState.quizDrops + pdtDrops;
            return Column(children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  children: [
                    const Text('Félicitations !',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                    const Text('Tu as fini en 1h42',
                        textAlign: TextAlign.center, style: TextStyle(color: AlpColors.textSecondary, fontSize: 15)),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                      decoration: BoxDecoration(color: AlpColors.cream, borderRadius: BorderRadius.circular(AlpRadii.card)),
                      child: Column(children: [
                        _line(const DropBadge(size: 20), 'Gouttes récoltées', '+${RaceState.baseDrops}'),
                        const Divider(height: 1),
                        _line(const DropBadge(size: 20), 'Jeux', '+$games'),
                        if (pdt != null) ...[
                          const Divider(height: 1),
                          _line(const TargetGlyph(size: 18), 'dont Pas de tir (${pdt.hits}/${pdt.shots.length})',
                              '+$pdtDrops'),
                        ],
                        const SizedBox(height: 6),
                        Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration:
                              BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AlpRadii.button)),
                          child: Row(children: [
                            const Expanded(child: Text('Total gouttes récoltées', style: TextStyle(fontSize: 15))),
                            Text('+${RaceState.baseDrops + games}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
                            const SizedBox(width: 8),
                            const DropBadge(size: 22),
                          ]),
                        ),
                      ]),
                    ),
                    if (pdt != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AlpColors.fir, borderRadius: BorderRadius.circular(AlpRadii.card)),
                        child: Row(children: [
                          Container(
                            width: 44,
                            height: 52,
                            decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(22)),
                            child: const Center(child: TargetGlyph(size: 24, color: Colors.white)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('MEILLEUR TIREUR DU JOUR',
                                  style: AlpText.condensed.copyWith(color: Colors.white, fontSize: 20, height: 1.1)),
                              const SizedBox(height: 4),
                              // Rang factice : fourni par le back (classement du jour).
                              const Text('Tu es #3 sur 128 au pas de tir',
                                  style: TextStyle(color: Colors.white70, fontSize: 13)),
                            ]),
                          ),
                          Text('${pdt.precision} %',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 28)),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Row(children: [
                      Text('Jeux (4)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      Spacer(),
                      Text('Voir tout', style: TextStyle(color: AlpColors.textSecondary)),
                    ]),
                    const SizedBox(height: 10),
                    const _ResultGameRow(
                      icon: Icon(Icons.question_mark_rounded, color: AlpColors.petrol, size: 20),
                      title: 'Quiz',
                      subtitle: 'Jeu terminé',
                    ),
                    _ResultGameRow(
                      icon: const TargetGlyph(size: 20),
                      title: 'Pas de tir',
                      subtitle: pdt == null
                          ? 'Non joué'
                          : '${pdt.hits}/${pdt.shots.length} cibles · ${pdt.mode.longLabel}',
                      trailing: pdt == null ? null : _MiniRecap(shots: pdt.shots),
                      onTap: () => _replay(context),
                      semanticHint: 'Rejouer en mode classique',
                    ),
                    const _ResultGameRow(
                      icon: Icon(Icons.photo_camera, color: AlpColors.petrol, size: 18),
                      title: 'Défi Photo',
                      subtitle: 'Jeu terminé',
                    ),
                    const _ResultGameRow(
                      icon: Icon(Icons.shield, color: AlpColors.petrol, size: 18),
                      title: 'Association parfaite',
                      subtitle: 'Jeu terminé',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(
                    child: AlpSecondaryButton(
                      label: "Retour à l'accueil",
                      onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AlpPrimaryButton(
                      label: 'Partager sur le fil',
                      onPressed: () => ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Partage sur le fil (simulé)'))),
                    ),
                  ),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _line(Widget icon, String label, String value) => SizedBox(
        height: 48,
        child: Row(children: [
          SizedBox(width: 22, child: Center(child: icon)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15.5))),
          Text(value, style: const TextStyle(fontSize: 15.5)),
        ]),
      );
}

class _ResultGameRow extends StatelessWidget {
  const _ResultGameRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.semanticHint,
  });

  final Widget icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticHint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        hint: semanticHint,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AlpRadii.card),
            side: const BorderSide(color: AlpColors.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AlpRadii.card),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(children: [
                GameIconBadge(child: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 16)),
                    Text(subtitle, style: const TextStyle(color: AlpColors.textSecondary, fontSize: 13)),
                  ]),
                ),
                trailing ?? const Icon(Icons.check_rounded, color: AlpColors.petrol),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini-récap de 5 pastilles : creuse = touchée, pleine = ratée.
class _MiniRecap extends StatelessWidget {
  const _MiniRecap({required this.shots});
  final List<ShotOutcome> shots;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final s in shots)
        Container(
          width: 11,
          height: 11,
          margin: const EdgeInsets.only(left: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: s.isHit ? Colors.white : AlpColors.text,
            border: Border.all(color: AlpColors.text, width: 2),
          ),
        ),
    ]);
  }
}
