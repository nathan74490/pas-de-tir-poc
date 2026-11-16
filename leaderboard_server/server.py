#!/usr/bin/env python3
"""Écran de classement du mode démo « Pas de tir » (portage Python de server.dart).

Lancement (depuis le dossier du projet) :
  python leaderboard_server/server.py            (port 8080)
  python leaderboard_server/server.py 9000       (autre port)

Puis ouvrir http://localhost:8080 sur l'ordi (F11 pour le plein écran) et
saisir l'adresse affichée dans la console dans le paramétrage démo des
téléphones.

Les scores sont enregistrés dans leaderboard_server/scores.json (même fichier
et même format que server.dart : on peut passer de l'un à l'autre).
Bibliothèque standard uniquement (Python 3.8+), aucune dépendance.
"""

import json
import shutil
import socket
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

SCORES_FILE = Path(__file__).resolve().parent / "scores.json"

# Toutes les parties reçues, dans l'ordre d'arrivée.
_games: list = []
_lock = threading.Lock()


class BadRequest(Exception):
    pass


def _int_field(body: dict, key: str, default=None) -> int:
    value = body.get(key, default)
    if isinstance(value, bool) or not isinstance(value, int):
        raise BadRequest(f"{key} invalide")
    return value


def _str_field(body: dict, key: str, default: str) -> str:
    value = body.get(key)
    if value is None:
        return default
    if not isinstance(value, str):
        raise BadRequest(f"{key} invalide")
    return value


def _save() -> None:
    SCORES_FILE.write_text(json.dumps(_games, indent=2, ensure_ascii=False), encoding="utf-8")


def _ranking() -> list:
    """Meilleure partie de chaque joueur (pseudo sans tenir compte de la casse),
    classée par gouttes, puis temps le plus court, puis ancienneté."""

    def key(g):
        return (-g["drops"], g["duration_ms"], g["at"])

    best: dict = {}
    last: dict = {}
    for g in _games:
        k = g["pseudo"].lower()
        if k not in best or key(g) < key(best[k]):
            best[k] = g
        last[k] = g["at"]
    ranking = [{**g, "last_played": last[k]} for k, g in best.items()]
    ranking.sort(key=key)
    return ranking


def _add_game(body: dict) -> None:
    pseudo = _str_field(body, "pseudo", "").strip()
    if not pseudo:
        raise BadRequest("pseudo manquant")
    game = {
        "id": body["id"] if body.get("id") is not None else str(time.time_ns() // 1000),
        "pseudo": pseudo[:20],
        "drops": _int_field(body, "drops"),
        "hits": _int_field(body, "hits"),
        "targets": _int_field(body, "targets", 5),
        "duration_ms": _int_field(body, "duration_ms"),
        "mode": _str_field(body, "mode", "classic"),
        "at": datetime.now().isoformat(timespec="microseconds"),
    }
    with _lock:
        # Un renvoi après coupure réseau ne doit pas compter deux fois.
        if not any(g["id"] == game["id"] for g in _games):
            _games.append(game)
            _save()
            print(f"+ {game['pseudo']} : {game['drops']} gouttes ({game['hits']}/{game['targets']})", flush=True)


def _reset() -> None:
    with _lock:
        if _games and SCORES_FILE.exists():
            # Sauvegarde avant remise à zéro, au cas où.
            backup = SCORES_FILE.with_name(f"scores-{int(time.time() * 1000)}.json")
            shutil.copyfile(SCORES_FILE, backup)
        _games.clear()
        _save()
    print("Classement remis à zéro.", flush=True)


class Handler(BaseHTTPRequestHandler):
    server_version = "PasDeTir/1.0"

    def log_message(self, format, *args):  # pas de log à chaque requête
        pass

    def _send(self, status: int, body: bytes = b"", content_type: str = None) -> None:
        self.send_response(status)
        if content_type:
            self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, data) -> None:
        self._send(200, json.dumps(data, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

    def _read_body(self) -> bytes:
        # Le HttpClient Dart de l'app envoie le corps en « chunked », sans Content-Length.
        if "chunked" in (self.headers.get("Transfer-Encoding") or "").lower():
            data = b""
            while True:
                size = int(self.rfile.readline().split(b";")[0].strip(), 16)
                if size == 0:
                    while self.rfile.readline() not in (b"\r\n", b"\n", b""):
                        pass  # en-têtes de fin éventuels
                    return data
                data += self.rfile.read(size)
                self.rfile.readline()  # CRLF après chaque morceau
        return self.rfile.read(int(self.headers.get("Content-Length") or 0))

    def _dispatch(self) -> None:
        path = urlsplit(self.path).path
        try:
            if self.command == "GET" and path == "/":
                self._send(200, PAGE.encode("utf-8"), "text/html; charset=utf-8")
            elif self.command == "GET" and path == "/api/health":
                with _lock:
                    count = len(_games)
                self._json({"ok": True, "games": count})
            elif self.command == "GET" and path == "/api/scores":
                with _lock:
                    data = {"ranking": _ranking(), "games": len(_games)}
                self._json(data)
            elif self.command == "POST" and path == "/api/scores":
                try:
                    body = json.loads(self._read_body().decode("utf-8"))
                except ValueError as e:
                    raise BadRequest(f"JSON invalide : {e}")
                if not isinstance(body, dict):
                    raise BadRequest("objet JSON attendu")
                _add_game(body)
                self._json({"ok": True})
            elif self.command == "POST" and path == "/api/reset":
                _reset()
                self._json({"ok": True})
            else:
                self._send(404)
        except Exception as e:  # même comportement que server.dart : 400 + message
            self._send(400, str(e).encode("utf-8"), "text/plain; charset=utf-8")

    do_GET = _dispatch
    do_POST = _dispatch


def _local_addresses() -> list:
    addrs = set()
    try:
        addrs.update(socket.gethostbyname_ex(socket.gethostname())[2])
    except OSError:
        pass
    try:  # adresse de la sortie réseau par défaut (aucun paquet n'est envoyé)
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))
            addrs.add(s.getsockname()[0])
    except OSError:
        pass
    addrs.add("127.0.0.1")
    return sorted(addrs)


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    if SCORES_FILE.exists():
        _games.extend(json.loads(SCORES_FILE.read_text(encoding="utf-8")))

    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"Classement Pas de tir : {len(_games)} partie(s) chargée(s).")
    print(f"Écran de classement : http://localhost:{port}")
    print("Adresse à saisir sur les téléphones :")
    for a in _local_addresses():
        print(f"  {a}:{port}")
    sys.stdout.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


# Page de l'écran de classement, identique à celle de server.dart.
PAGE = r'''<!doctype html>
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
  #reset { position: fixed; right: 1.5vw; bottom: 1.5vh; opacity: 0; border: 0; background: #fff; border-radius: 1vh;
           padding: 1vh 1.5vw; font-size: 1.8vh; cursor: pointer; }
  #reset:hover { opacity: 1; }
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
  <button id="reset" title="Remettre le classement à zéro">Réinitialiser</button>
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
    if (!confirm('Remettre le classement à zéro ? (une sauvegarde est gardée sur l\'ordi)')) return;
    await fetch('/api/reset', { method: 'POST' });
    refresh();
  };

  refresh();
  setInterval(refresh, 2000);
</script>
</body>
</html>
'''


if __name__ == "__main__":
    main()
