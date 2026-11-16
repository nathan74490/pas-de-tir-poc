import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pas_de_tir/pas_de_tir_result.dart';

/// Réglages du mode démo, mémorisés sur le téléphone.
abstract final class DemoSettings {
  static const _modeKey = 'demo_mode';
  static const _addressKey = 'leaderboard_address';

  static Future<(PasDeTirMode?, String)> load() async {
    final p = await SharedPreferences.getInstance();
    final mode = PasDeTirMode.values.where((m) => m.apiValue == p.getString(_modeKey)).firstOrNull;
    return (mode, p.getString(_addressKey) ?? '');
  }

  static Future<void> save({required PasDeTirMode mode, required String address}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_modeKey, mode.apiValue);
    await p.setString(_addressKey, address.trim());
  }
}

/// Envoie les scores du mode démo à l'écran de classement
/// (`leaderboard_server/server.dart` sur l'ordi, même réseau Wi-Fi).
///
/// Un score non parvenu (Wi-Fi coupé, ordi éteint) reste en attente et est
/// renvoyé régulièrement ; le serveur ignore les doublons.
class LeaderboardClient extends ChangeNotifier {
  LeaderboardClient(String address) : _base = baseUri(address) {
    _retry = Timer.periodic(const Duration(seconds: 10), (_) => flush());
    flush();
  }

  final Uri _base;
  late final Timer _retry;
  final List<Map<String, dynamic>> _pending = [];
  bool _flushing = false;

  /// Dernier état connu de la connexion (null tant qu'aucun échange n'a eu lieu).
  bool? connected;

  int get pendingCount => _pending.length;

  /// « 192.168.1.20:8080 » ou « http://192.168.1.20:8080 » → URI de base.
  static Uri baseUri(String address) {
    final a = address.trim();
    return Uri.parse(a.contains('://') ? a : 'http://$a');
  }

  static HttpClient _http() => HttpClient()..connectionTimeout = const Duration(seconds: 3);

  /// Vérifie que l'écran de classement répond à cette adresse.
  static Future<bool> ping(String address) async {
    final http = _http();
    try {
      final req = await http.getUrl(baseUri(address).resolve('/api/health'));
      final res = await req.close().timeout(const Duration(seconds: 4));
      await res.drain<void>();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      http.close(force: true);
    }
  }

  void submit(String pseudo, PasDeTirResult r) {
    _pending.add({
      'id': '${DateTime.now().microsecondsSinceEpoch}-${pseudo.hashCode}',
      'pseudo': pseudo,
      'drops': r.drops,
      'hits': r.hits,
      'targets': r.shots.length,
      'duration_ms': r.duration.inMilliseconds,
      'mode': r.mode.apiValue,
    });
    notifyListeners();
    flush();
  }

  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    final http = _http();
    try {
      if (_pending.isEmpty) {
        connected = await ping(_base.toString());
      }
      while (_pending.isNotEmpty) {
        final req = await http.postUrl(_base.resolve('/api/scores'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(_pending.first));
        final res = await req.close().timeout(const Duration(seconds: 4));
        await res.drain<void>();
        if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
        _pending.removeAt(0);
        connected = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Classement injoignable : $e');
      connected = false;
    } finally {
      http.close(force: true);
      _flushing = false;
      notifyListeners();
    }
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry.cancel();
    super.dispose();
  }
}
