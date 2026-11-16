// Écran de classement du mode démo « Pas de tir ».
//
// Lancement (depuis le dossier du projet) :
//   dart leaderboard_server/server.dart            (port 8080)
//   dart leaderboard_server/server.dart 9000       (autre port)
//
// Puis ouvrir http://localhost:8080 sur l'ordi (F11 pour le plein écran) et
// saisir l'adresse affichée dans la console dans le paramétrage démo des
// téléphones. Ordi et téléphones doivent être sur le même réseau Wi-Fi.
//
// Les scores sont enregistrés dans leaderboard_server/scores.json.

import 'dart:convert';
import 'dart:io';

final _scoresFile = File.fromUri(Platform.script.resolve('scores.json'));

/// Toutes les parties reçues, dans l'ordre d'arrivée.
final List<Map<String, dynamic>> _games = [];

Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 8080 : int.parse(args.first);
  if (_scoresFile.existsSync()) {
    _games.addAll((jsonDecode(_scoresFile.readAsStringSync()) as List).cast<Map<String, dynamic>>());
  }

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Classement Pas de tir : ${_games.length} partie(s) chargée(s).');
  stdout.writeln('Écran de classement : http://localhost:$port');
  stdout.writeln('Adresse à saisir sur les téléphones :');
  for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in ni.addresses) {
      stdout.writeln('  ${a.address}:$port   (${ni.name})');
    }
  }

  await for (final req in server) {
    try {
      await _handle(req);
    } catch (e) {
      req.response.statusCode = HttpStatus.badRequest;
      req.response.write('$e');
    }
    await req.response.close();
  }
}

Future<void> _handle(HttpRequest req) async {
  final res = req.response;
  final path = req.uri.path;

  if (req.method == 'GET' && path == '/') {
    res.headers.contentType = ContentType.html;
    res.write(_page);
  } else if (req.method == 'GET' && path == '/api/health') {
    _json(res, {'ok': true, 'games': _games.length});
  } else if (req.method == 'GET' && path == '/api/scores') {
    _json(res, {'ranking': _ranking(), 'games': _games.length});
  } else if (req.method == 'POST' && path == '/api/scores') {
    final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
    final pseudo = (body['pseudo'] as String? ?? '').trim();
    if (pseudo.isEmpty) throw 'pseudo manquant';
    final game = {
      'id': body['id'] ?? '${DateTime.now().microsecondsSinceEpoch}',
      'pseudo': pseudo.length > 20 ? pseudo.substring(0, 20) : pseudo,
      'drops': body['drops'] as int,
      'hits': body['hits'] as int,
      'targets': body['targets'] as int? ?? 5,
      'duration_ms': body['duration_ms'] as int,
      'mode': body['mode'] as String? ?? 'classic',
      'at': DateTime.now().toIso8601String(),
    };
    // Un renvoi après coupure réseau ne doit pas compter deux fois.
    if (!_games.any((g) => g['id'] == game['id'])) {
      _games.add(game);
      _save();
      stdout.writeln('+ ${game['pseudo']} : ${game['drops']} gouttes (${game['hits']}/${game['targets']})');
    }
    _json(res, {'ok': true});
  } else if (req.method == 'POST' && path == '/api/reset') {
    if (_games.isNotEmpty) {
      // Sauvegarde avant remise à zéro, au cas où.
      _scoresFile.copySync(_scoresFile.path.replaceFirst('.json', '-${DateTime.now().millisecondsSinceEpoch}.json'));
    }
    _games.clear();
    _save();
    stdout.writeln('Classement remis à zéro.');
    _json(res, {'ok': true});
  } else if (req.method == 'POST' && path == '/api/delete') {
    // Supprime toutes les parties d'un pseudo (sans tenir compte de la casse).
    final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
    final key = (body['pseudo'] as String? ?? '').trim().toLowerCase();
    if (key.isEmpty) throw 'pseudo manquant';
    final before = _games.length;
    _games.removeWhere((g) => (g['pseudo'] as String).toLowerCase() == key);
    final removed = before - _games.length;
    if (removed > 0) _save();
    stdout.writeln('- $key : $removed partie(s) supprimée(s)');
    _json(res, {'ok': true, 'removed': removed});
  } else {
    res.statusCode = HttpStatus.notFound;
  }
}

/// Meilleure partie de chaque joueur (pseudo sans tenir compte de la casse),
/// classée par gouttes, puis temps le plus court, puis ancienneté.
List<Map<String, dynamic>> _ranking() {
  int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byDrops = (b['drops'] as int).compareTo(a['drops'] as int);
    if (byDrops != 0) return byDrops;
    final byTime = (a['duration_ms'] as int).compareTo(b['duration_ms'] as int);
    if (byTime != 0) return byTime;
    return (a['at'] as String).compareTo(b['at'] as String);
  }

  final best = <String, Map<String, dynamic>>{};
  final last = <String, String>{};
  for (final g in _games) {
    final key = (g['pseudo'] as String).toLowerCase();
    if (best[key] == null || compare(g, best[key]!) < 0) best[key] = g;
    last[key] = g['at'] as String;
  }
  return [
    for (final e in best.entries) {...e.value, 'last_played': last[e.key]},
  ]..sort(compare);
}

void _json(HttpResponse res, Object data) {
  res.headers.contentType = ContentType.json;
  res.headers.set('Cache-Control', 'no-store');
  res.write(jsonEncode(data));
}

void _save() => _scoresFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_games));

const _page = r'''<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Classement Pas de tir</title>
<style>
  :root {
    --orange: #FF6B1A; --petrol: #00607C; --cyan: #00C8FF; --gold: #FFDD15;
    --cream: #F5F3ED; --text: #0A0A0A; --muted: #737373; --line: #E5E2DA;
  }
  * { box-sizing: border-box; margin: 0; }
  html, body { height: 100%; }
  body {
    background: var(--cream); color: var(--text);
    font-family: "Segoe UI", Roboto, system-ui, sans-serif;
    display: flex; flex-direction: column; padding: 3vh 4vw; gap: 3vh; overflow: hidden;
  }
  header { display: flex; align-items: center; gap: 2vw; }
  .logo {
    width: 7vh; height: 7vh; border-radius: 50%; background: var(--orange); flex: none;
    display: grid; place-items: center; box-shadow: 0 0 0 1.2vh rgba(255,107,26,.2);
  }
  .logo i { width: 3.4vh; height: 3.4vh; border-radius: 50%; border: .5vh solid #fff; position: relative; }
  .logo i::after { content: ""; position: absolute; inset: .7vh; border-radius: 50%; background: #fff; }
  h1 { font-family: "Arial Narrow", "Roboto Condensed", sans-serif; font-stretch: condensed;
       font-size: 6vh; font-weight: 800; letter-spacing: .02em; line-height: 1; }
  .sub { color: var(--muted); font-size: 2.2vh; margin-top: .6vh; }
  .count { margin-left: auto; text-align: right; font-size: 2.2vh; color: var(--muted); }
  .count b { display: block; font-size: 5vh; color: var(--petrol); line-height: 1; }

  .board { display: grid; grid-template-columns: 1fr 1fr; gap: 1.4vh 2vw; flex: 1; align-content: start; }
  .row {
    display: grid; grid-template-columns: 7vh 1fr auto auto; align-items: center; gap: 1.6vw;
    background: #fff; border-radius: 1.8vh; padding: 0 2vw; height: 8.4vh;
    box-shadow: 0 .3vh 1.2vh rgba(0,0,0,.05); transition: transform .4s;
  }
  .row.top { grid-column: span 2; height: 10.5vh; }
  .rank { font-size: 3.6vh; font-weight: 800; color: var(--muted); text-align: center; }
  .top .rank { width: 6.4vh; height: 6.4vh; border-radius: 50%; display: grid; place-items: center; color: #fff; }
  .r1 .rank { background: #E3B400; } .r2 .rank { background: #9AA3A8; } .r3 .rank { background: #C07A3B; }
  .name { font-size: 3.4vh; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .top .name { font-size: 4.4vh; }
  .meta { color: var(--muted); font-size: 2.2vh; white-space: nowrap; }
  .drops { font-size: 3.8vh; font-weight: 800; color: var(--petrol); white-space: nowrap; display: flex; align-items: center; gap: .8vh; }
  .top .drops { font-size: 4.8vh; }
  .drop { width: 2.6vh; height: 2.6vh; background: var(--cyan); border-radius: 50% 0 50% 50%; transform: rotate(-45deg); }
  .row.new { animation: flash 2.4s ease-out; }
  @keyframes flash {
    0% { background: var(--orange); color: #fff; transform: scale(1.04); }
    100% { background: #fff; transform: scale(1); }
  }
  .empty { grid-column: span 2; text-align: center; color: var(--muted); font-size: 3vh; padding-top: 12vh; }
  .offline { position: fixed; bottom: 2vh; left: 50%; transform: translateX(-50%); background: #262A2C; color: #fff;
             padding: 1vh 2vw; border-radius: 1vh; font-size: 2vh; display: none; }
  #reset { position: fixed; right: 1.5vw; bottom: 1.5vh; border: .2vh solid var(--line); background: #fff; color: var(--muted);
           border-radius: 1vh; padding: 1vh 1.5vw; font-size: 1.8vh; font-weight: 600; cursor: pointer;
           transition: background .2s, color .2s, border-color .2s; }
  #reset:hover { background: #D93025; border-color: #D93025; color: #fff; }

  /* Suppression d'un joueur : croix visible au survol de sa ligne. */
  .row { position: relative; }
  .del { position: absolute; top: 50%; right: 1vw; transform: translateY(-50%) scale(.8);
         width: 4.4vh; height: 4.4vh; border-radius: 50%; border: 0; background: #D93025; color: #fff;
         font-size: 2.6vh; line-height: 1; cursor: pointer; opacity: 0; pointer-events: none;
         transition: opacity .15s, transform .15s; box-shadow: 0 .3vh 1vh rgba(0,0,0,.2); }
  .row:hover .del { opacity: 1; pointer-events: auto; transform: translateY(-50%) scale(1); }
  .row:hover .drops { visibility: hidden; }
  .del:hover { background: #A8231B; }
</style>
</head>
<body>
  <header>
    <div class="logo"><i></i></div>
    <div>
      <h1>MEILLEURS TIREURS DU JOUR</h1>
      <div class="sub">Pas de tir · Alpvengers — joue sur le téléphone et entre dans le classement</div>
    </div>
    <div class="count"><b id="players">0</b>joueurs</div>
  </header>
  <main class="board" id="board"></main>
  <div class="offline" id="offline">Connexion au serveur perdue…</div>
  <button id="reset" title="Remettre tout le classement à zéro">Réinitialiser le classement</button>
<script>
  const MAX_ROWS = 13;
  const MODES = { ar: 'AR', gyro: 'Gyro', classic: 'Classique' };
  const seen = new Set();
  let first = true;

  const esc = s => s.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const secs = ms => (ms / 1000).toFixed(1).replace('.', ',') + ' s';

  async function refresh() {
    try {
      const r = await fetch('/api/scores', { cache: 'no-store' });
      const { ranking } = await r.json();
      document.getElementById('offline').style.display = 'none';
      document.getElementById('players').textContent = ranking.length;
      const board = document.getElementById('board');
      if (!ranking.length) {
        board.innerHTML = '<div class="empty">Aucun tireur pour l\'instant. À toi de jouer !</div>';
      } else {
        board.innerHTML = ranking.slice(0, MAX_ROWS).map((g, i) => {
          const key = g.pseudo.toLowerCase() + '|' + g.last_played;
          const isNew = !first && !seen.has(key);
          seen.add(key);
          const cls = ['row', i < 3 ? 'top r' + (i + 1) : '', isNew ? 'new' : ''].join(' ');
          return `<div class="${cls}">
            <div class="rank">${i + 1}</div>
            <div class="name">${esc(g.pseudo)}</div>
            <div class="meta">${g.hits}/${g.targets} cibles · ${secs(g.duration_ms)} · ${MODES[g.mode] || g.mode}</div>
            <div class="drops">${g.drops}<span class="drop"></span></div>
            <button class="del" data-pseudo="${esc(g.pseudo)}" title="Supprimer ${esc(g.pseudo)} du classement">✕</button>
          </div>`;
        }).join('');
        if (first) ranking.forEach(g => seen.add(g.pseudo.toLowerCase() + '|' + g.last_played));
      }
      first = false;
    } catch (e) {
      document.getElementById('offline').style.display = 'block';
    }
  }

  document.getElementById('reset').onclick = async () => {
    if (!confirm('Remettre tout le classement à zéro ? (une sauvegarde est gardée sur le serveur)')) return;
    await fetch('/api/reset', { method: 'POST' });
    refresh();
  };

  // Croix au survol d'une ligne : supprime toutes les parties de ce joueur.
  document.getElementById('board').addEventListener('click', async e => {
    const btn = e.target.closest('.del');
    if (!btn) return;
    const pseudo = btn.dataset.pseudo;
    if (!confirm(`Supprimer « ${pseudo} » du classement ? (toutes ses parties)`)) return;
    await fetch('/api/delete', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pseudo }),
    });
    refresh();
  });

  refresh();
  setInterval(refresh, 2000);
</script>
</body>
</html>
''';
