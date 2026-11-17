import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demo/demo_player_screen.dart';
import 'demo/leaderboard_client.dart';
import 'pas_de_tir/ar_support.dart';
import 'pas_de_tir/pas_de_tir_logic.dart';
import 'pas_de_tir/pas_de_tir_result.dart';
import 'pas_de_tir/screens/ar_session_screen.dart';
import 'pas_de_tir/screens/classic_session_screen.dart';
import 'pas_de_tir/screens/gyro_session_screen.dart';
import 'pas_de_tir/screens/pas_de_tir_modals.dart';
import 'race/race_map_screen.dart';
import 'race/race_results_screen.dart';
import 'race/race_state.dart';
import 'theme/alp_tokens.dart';
import 'widgets/alp_common.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const PasDeTirPocApp());
}

class PasDeTirPocApp extends StatelessWidget {
  const PasDeTirPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pas de tir · POC',
      debugShowCheckedModeBanner: false,
      theme: buildAlpTheme(),
      home: const PocHomeScreen(),
    );
  }
}

PasDeTirResult _demoResult(PasDeTirMode mode) => PasDeTirResult(
  shots: mode == PasDeTirMode.classic
      ? const [ShotOutcome.hit, ShotOutcome.hit, ShotOutcome.hit, ShotOutcome.missBreath, ShotOutcome.hit]
      : const [ShotOutcome.hit, ShotOutcome.hit, ShotOutcome.hit, ShotOutcome.hit, ShotOutcome.missAim],
  duration: Duration(seconds: mode == PasDeTirMode.classic ? 42 : 36),
  mode: mode,
);

RaceState _raceWithDemo() => RaceState()..pasDeTir = _demoResult(PasDeTirMode.ar);

/// Accueil du POC : scénario complet + accès direct à chaque écran.
class PocHomeScreen extends StatefulWidget {
  const PocHomeScreen({super.key});

  @override
  State<PocHomeScreen> createState() => _PocHomeScreenState();
}

class _PocHomeScreenState extends State<PocHomeScreen> {
  /// Modes jouables sur ce téléphone (null pendant la détection).
  Set<PasDeTirMode>? _availableModes;
  PasDeTirMode? _demoMode;
  final _leaderboardAddress = TextEditingController();

  /// Résultat du dernier test de connexion au classement (null = pas testé).
  bool? _leaderboardOk;
  bool _testingLeaderboard = false;

  @override
  void initState() {
    super.initState();
    _loadDemoSettings();
  }

  @override
  void dispose() {
    _leaderboardAddress.dispose();
    super.dispose();
  }

  /// Reprend le mode et l'adresse du classement mémorisés, puis détecte les modes.
  Future<void> _loadDemoSettings() async {
    final (mode, address) = await DemoSettings.load();
    if (!mounted) return;
    _demoMode = mode;
    _leaderboardAddress.text = address;
    await _detectModes();
  }

  Future<void> _testLeaderboard() async {
    setState(() => _testingLeaderboard = true);
    final ok = await LeaderboardClient.ping(_leaderboardAddress.text);
    if (mounted) {
      setState(() {
        _testingLeaderboard = false;
        _leaderboardOk = ok;
      });
    }
  }

  Future<void> _startDemo() async {
    final mode = _demoMode!;
    final address = _leaderboardAddress.text.trim();
    // Sinon le clavier se rouvre sur le champ d'adresse en quittant la démo.
    FocusScope.of(context).unfocus();
    await DemoSettings.save(mode: mode, address: address);
    if (mounted) _push(DemoPlayerScreen(mode: mode, leaderboardAddress: address));
  }

  /// Détecte les modes disponibles, en tenant compte des simulations « sans AR / sans gyro ».
  Future<void> _detectModes() async {
    final (ar, gyro) = await (isArSupported(), isGyroSupported()).wait;
    if (!mounted) return;
    final modes = {
      if (ar) PasDeTirMode.ar,
      if (gyro) PasDeTirMode.gyro,
      if (gyro) PasDeTirMode.gyroCamera,
      PasDeTirMode.classic,
    };
    setState(() {
      _availableModes = modes;
      if (_demoMode == null || !modes.contains(_demoMode)) _demoMode = modes.first;
    });
  }

  void _push(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AlpColors.cream,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 8),
            Text('PAS DE TIR', style: AlpText.condensed.copyWith(fontSize: 34)),
            const Text(
              'POC Alpvengers v2.0 · gamification biathlon',
              style: TextStyle(color: AlpColors.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 20),
            AlpPrimaryButton(
              label: 'Lancer le scénario complet',
              height: 54,
              onPressed: () => _push(RaceMapScreen(race: RaceState())),
            ),
            const SizedBox(height: 6),
            const Text(
              "Approche du POI simulée (~2 s), ouverture automatique à l'arrivée, puis retour en course. "
              "L'icône randonneur en haut à droite de la carte termine l'épreuve.",
              style: TextStyle(color: AlpColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AlpRadii.card),
              child: SwitchListTile(
                title: const Text('Simuler un appareil sans AR'),
                subtitle: const Text('Le choix du mode propose Gyroscope et Classique'),
                value: PocSettings.forceNoAr,
                activeThumbColor: AlpColors.orange,
                onChanged: (v) {
                  setState(() => PocSettings.forceNoAr = v);
                  _detectModes();
                },
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AlpRadii.card),
              child: SwitchListTile(
                title: const Text('Simuler un appareil sans gyroscope'),
                subtitle: const Text("Le mode Gyroscope n'est plus proposé"),
                value: PocSettings.forceNoGyro,
                activeThumbColor: AlpColors.orange,
                onChanged: (v) {
                  setState(() => PocSettings.forceNoGyro = v);
                  _detectModes();
                },
              ),
            ),
            const SizedBox(height: 20),
            _demoSetup(),
            const SizedBox(height: 20),
            const Text('Accès direct aux écrans', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 8),
            _entry('01', 'Approche du pas de tir', () => _push(RaceMapScreen(race: RaceState()))),
            _entry('02', 'Règles et choix du mode', () async {
              final (ar, gyro) = await (isArSupported(), isGyroSupported()).wait;
              if (context.mounted) showPasDeTirIntro(context, arAvailable: ar, gyroAvailable: gyro);
            }),
            _entry('03', 'Classique · Reprends ton souffle', () => _push(const ClassicSessionScreen())),
            _entry(
              '04–06',
              'Classique · Tir (touché / raté)',
              () => _push(const ClassicSessionScreen(skipBreathing: true)),
            ),
            _entry('07', 'Classique · Résultat', () => showPasDeTirResult(context, _demoResult(PasDeTirMode.classic))),
            _entry('08', 'AR · Autorisation caméra', () => showCameraPermissionModal(context)),
            _entry('09–13', 'AR · Scan, placement et tir', () async {
              final ok = await prepareAr();
              if (!context.mounted) return;
              if (ok) {
                _push(const ArSessionScreen());
              } else {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('ARCore indisponible ou caméra refusée')));
              }
            }),
            _entry('14', 'AR · Résultat', () => showPasDeTirResult(context, _demoResult(PasDeTirMode.ar))),
            _entry('G', 'Gyroscope · Calibrage et tir', () async {
              final r = await Navigator.push<Object?>(
                context,
                MaterialPageRoute(builder: (_) => const GyroSessionScreen()),
              );
              if (r is ClassicFallbackSignal && context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Gyroscope indisponible : repli en Classique')));
              }
            }),
            _entry('G2', 'Gyroscope + caméra · Calibrage et tir', () async {
              if (!await requestCameraPermission() || !context.mounted) return;
              final r = await Navigator.push<Object?>(
                context,
                MaterialPageRoute(builder: (_) => const GyroSessionScreen(useCamera: true)),
              );
              if (r is ClassicFallbackSignal && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Gyroscope ou caméra indisponible : repli en Classique')),
                );
              }
            }),
            _entry('15', 'Retour en course', () => _push(RaceMapScreen(race: _raceWithDemo(), startArrived: true))),
            _entry('16', "Résultats de l'épreuve", () => _push(RaceResultsScreen(race: _raceWithDemo()))),
          ],
        ),
      ),
    );
  }

  /// Paramétrage du mode démo : choix du mode, puis boucle pseudo → jeu.
  Widget _demoSetup() {
    final modes = _availableModes;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AlpRadii.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Mode démo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 4),
          const Text(
            'Choisis le mode de ce téléphone. Chaque joueur entre son pseudo et joue uniquement ce mode, '
            'puis la démo revient au pseudo. Appui long sur le titre « PAS DE TIR » pour quitter.',
            style: TextStyle(color: AlpColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (modes == null)
            const Center(
              child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
            )
          else
            SegmentedButton<PasDeTirMode>(
              segments: [
                for (final m in PasDeTirMode.values)
                  if (modes.contains(m))
                    ButtonSegment(
                      value: m,
                      // Une seule ligne, réduite si 4 modes ne tiennent pas en largeur.
                      label: FittedBox(fit: BoxFit.scaleDown, child: Text(m.shortLabel, maxLines: 1, softWrap: false)),
                    ),
              ],
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
              ),
              selected: {?_demoMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _demoMode = s.first),
            ),
          const SizedBox(height: 16),
          const Text('Écran de classement (optionnel)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _leaderboardAddress,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: (_) => setState(() => _leaderboardOk = null),
                  decoration: const InputDecoration(
                    hintText: 'ex. 192.168.1.20:8080',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                child: AlpSecondaryButton(
                  label: _testingLeaderboard ? '…' : 'Tester',
                  onPressed: _testingLeaderboard || _leaderboardAddress.text.trim().isEmpty ? null : _testLeaderboard,
                ),
              ),
            ],
          ),
          if (_leaderboardOk != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _leaderboardOk! ? 'Classement joignable ✓' : "Injoignable : vérifie que le serveur tourne sur l'ordi et que le téléphone est sur le même Wi-Fi",
                style: TextStyle(
                  color: _leaderboardOk! ? AlpColors.petrol : AlpColors.orange,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 12),
          AlpPrimaryButton(label: 'Lancer le mode démo', onPressed: _demoMode == null ? null : _startDemo),
        ],
      ),
    );
  }

  Widget _entry(String number, String title, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AlpRadii.card),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AlpRadii.card)),
          leading: GameIconBadge(
            child: Text(
              number,
              style: const TextStyle(color: AlpColors.petrol, fontWeight: FontWeight.w800, fontSize: 11),
            ),
          ),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ),
    );
  }
}
