import 'package:flutter/material.dart';

import '../pas_de_tir/pas_de_tir_result.dart';
import '../race/race_map_screen.dart';
import '../race/race_state.dart';
import '../theme/alp_tokens.dart';
import '../widgets/alp_common.dart';
import 'leaderboard_client.dart';

/// Écran d'accueil du mode démo, en boucle : pseudo → approche du POI →
/// pas de tir dans le mode paramétré → retour ici pour le joueur suivant.
///
/// Le retour système est bloqué pour qu'un joueur ne quitte pas la démo par
/// erreur ; un appui long sur le titre permet d'en sortir.
///
/// Avec [leaderboardAddress], chaque score est envoyé à l'écran de classement.
class DemoPlayerScreen extends StatefulWidget {
  const DemoPlayerScreen({super.key, required this.mode, this.leaderboardAddress = ''});

  final PasDeTirMode mode;
  final String leaderboardAddress;

  @override
  State<DemoPlayerScreen> createState() => _DemoPlayerScreenState();
}

class _DemoPlayerScreenState extends State<DemoPlayerScreen> {
  static const _maxPseudoLength = 20;

  final _pseudo = TextEditingController();
  final _focus = FocusNode();

  /// Dernières parties de la session de démo, la plus récente en premier.
  final _recent = <(String, PasDeTirResult)>[];

  LeaderboardClient? _leaderboard;

  @override
  void initState() {
    super.initState();
    _pseudo.addListener(() => setState(() {}));
    if (widget.leaderboardAddress.trim().isNotEmpty) {
      _leaderboard = LeaderboardClient(widget.leaderboardAddress)..addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _leaderboard?.dispose();
    _pseudo.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _cleanPseudo => _pseudo.text.trim();

  Future<void> _start() async {
    final pseudo = _cleanPseudo;
    if (pseudo.isEmpty) return;
    _focus.unfocus();
    final result = await Navigator.push<PasDeTirResult?>(
      context,
      MaterialPageRoute(
        builder: (_) => RaceMapScreen(race: RaceState(), demoMode: widget.mode, pseudo: pseudo),
      ),
    );
    if (!mounted) return;
    if (result != null) _leaderboard?.submit(pseudo, result);
    setState(() {
      if (result != null) {
        _recent.insert(0, (pseudo, result));
        if (_recent.length > 5) _recent.removeLast();
      }
      _pseudo.clear();
    });
  }

  Future<void> _confirmExit() async {
    final exit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter le mode démo ?'),
        content: const Text('Tu reviendras à l\'écran de paramétrage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitter')),
        ],
      ),
    );
    if (exit == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AlpColors.cream,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: HaloIcon(child: TargetGlyph(size: 26, color: Colors.white)),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onLongPress: _confirmExit,
                      child: Text(
                        'PAS DE TIR',
                        textAlign: TextAlign.center,
                        style: AlpText.condensed.copyWith(fontSize: 40),
                      ),
                    ),
                    Text(
                      'Mode ${widget.mode.longLabel.toLowerCase()}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AlpColors.textSecondary, fontSize: 16),
                    ),
                    const SizedBox(height: 32),
                    const Text('Ton pseudo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _pseudo,
                      focusNode: _focus,
                      maxLength: _maxPseudoLength,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _start(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Ex. : Martin',
                        filled: true,
                        fillColor: Colors.white,
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AlpRadii.button),
                          borderSide: const BorderSide(color: AlpColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AlpRadii.button),
                          borderSide: const BorderSide(color: AlpColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AlpRadii.button),
                          borderSide: const BorderSide(color: AlpColors.orange, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AlpPrimaryButton(label: 'Continuer', height: 54, onPressed: _cleanPseudo.isEmpty ? null : _start),
                    if (_leaderboard != null) ...[
                      const SizedBox(height: 14),
                      _LeaderboardStatus(client: _leaderboard!),
                    ],
                    if (_recent.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      const Text('Derniers joueurs', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 8),
                      for (final (pseudo, r) in _recent) _RecentRow(pseudo: pseudo, result: r),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// État de la liaison avec l'écran de classement.
class _LeaderboardStatus extends StatelessWidget {
  const _LeaderboardStatus({required this.client});
  final LeaderboardClient client;

  @override
  Widget build(BuildContext context) {
    final pending = client.pendingCount;
    final (color, text) = switch (client.connected) {
      null => (AlpColors.textSecondary, 'Connexion au classement…'),
      true when pending == 0 => (AlpColors.petrol, 'Classement connecté'),
      true => (AlpColors.petrol, 'Envoi au classement…'),
      false when pending == 0 => (AlpColors.orange, 'Classement injoignable'),
      false => (AlpColors.orange, 'Classement injoignable · $pending score${pending > 1 ? 's' : ''} en attente'),
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.leaderboard_rounded, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.pseudo, required this.result});
  final String pseudo;
  final PasDeTirResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AlpRadii.button)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              pseudo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text('${result.hits}/${result.shots.length} cibles', style: const TextStyle(color: AlpColors.textSecondary)),
          const SizedBox(width: 12),
          Text('+${result.drops}', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 4),
          const DropBadge(size: 14),
        ],
      ),
    );
  }
}
