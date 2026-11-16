# Pas de tir — POC Alpvengers

POC Flutter (Android) de gamification biathlon « Pas de tir » : séance de tir en
réalité augmentée (ARCore), au gyroscope ou classique, avec un **mode démo
multi-joueurs** et un **écran de classement** en direct.

## App (Flutter)

```
flutter pub get
flutter run
```

Code dans `lib/` : `pas_de_tir/` (logique, écrans AR / gyro / classique),
`demo/` (mode démo + envoi des scores), `race/` (carte et résultats de course).

## Serveur de classement

Deux versions équivalentes (même API, même fichier `scores.json`) :

```
python leaderboard_server/server.py        # Python 3.8+, aucune dépendance
dart leaderboard_server/server.dart        # Dart
```

Port 8080 par défaut (passer un autre port en argument). Ouvrir
`http://localhost:8080` pour l'écran de classement, puis saisir l'adresse du
serveur dans le paramétrage démo des téléphones.

API : `GET /api/health`, `GET /api/scores`, `POST /api/scores`, `POST /api/reset`.
