import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';

/// Basit oyun istatistikleri: seviye başına deneme / kazanma / kayıp, reklam teklifi / izlenme, booster kullanımı.
/// Veriler SADECE cihazda saklanır, hiçbir yere gönderilmez. Seçenekler > İstatistikler'den okunur / kopyalanır.
/// Amaç: zorluk ve reklam ayarını gerçek oyuncu verisiyle yapmak.
class Stats {
  // Seviye başına sayaç dizisi indeksleri.
  static const int iStart = 0; // seviye açıldı (yeniden deneme / yeniden başlat dahil)
  static const int iWin = 1;
  static const int iLoseMoves = 2; // hamle bitti
  static const int iLoseSlots = 3; // park yerleri doldu
  static const int iAdOffer = 4; // bu seviyede reklam teklifi gösterildi
  static const int iAdWatch = 5; // bu seviyede reklam izlendi
  static const int iBooster = 6; // bu seviyede booster kullanıldı
  static const int _n = 7;

  /// seviye -> sayaçlar
  static final Map<int, List<int>> levels = <int, List<int>>{};

  /// reklam türü -> [teklif, izlendi]
  static final Map<String, List<int>> ads = <String, List<int>>{};

  static int coinBuys = 0;
  static int currentLevel = 0;

  static const String _key = 'stats_v1';

  static List<int> _lv(int n) => levels.putIfAbsent(n, () => List<int>.filled(_n, 0));
  static List<int> _ad(String tag) => ads.putIfAbsent(tag, () => <int>[0, 0]);

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      levels.clear();
      ads.clear();
      (m['levels'] as Map<String, dynamic>? ?? const <String, dynamic>{}).forEach((k, v) {
        final l = List<int>.filled(_n, 0);
        final src = (v as List<dynamic>).map((e) => (e as num).toInt()).toList();
        for (int i = 0; i < _n && i < src.length; i++) {
          l[i] = src[i];
        }
        levels[int.parse(k)] = l;
      });
      (m['ads'] as Map<String, dynamic>? ?? const <String, dynamic>{}).forEach((k, v) {
        final src = (v as List<dynamic>).map((e) => (e as num).toInt()).toList();
        ads[k] = <int>[src.isNotEmpty ? src[0] : 0, src.length > 1 ? src[1] : 0];
      });
      coinBuys = (m['coinBuys'] as num?)?.toInt() ?? 0;
    } catch (_) {}
  }

  static Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, toJson());
    } catch (_) {}
  }

  static String toJson() => jsonEncode(<String, dynamic>{
        'v': 1,
        'levels': <String, dynamic>{for (final e in levels.entries) '${e.key}': e.value},
        'ads': ads,
        'coinBuys': coinBuys,
      });

  static Future<void> reset() async {
    levels.clear();
    ads.clear();
    coinBuys = 0;
    await save();
  }

  // ------------------------------------------------------------------ olaylar

  static void levelStart(int n) {
    currentLevel = n;
    _lv(n)[iStart]++;
    save();
  }

  static void levelWin(int n) {
    _lv(n)[iWin]++;
    save();
  }

  static void levelLose(int n, {required bool outOfMoves}) {
    _lv(n)[outOfMoves ? iLoseMoves : iLoseSlots]++;
    save();
  }

  static void adOffered(String tag) {
    _ad(tag)[0]++;
    if (currentLevel > 0) _lv(currentLevel)[iAdOffer]++;
    save();
  }

  static void adWatched(String tag) {
    _ad(tag)[1]++;
    if (currentLevel > 0) _lv(currentLevel)[iAdWatch]++;
    save();
  }

  static void boosterUsed() {
    if (currentLevel > 0) _lv(currentLevel)[iBooster]++;
    save();
  }

  static void coinBuy() {
    coinBuys++;
    save();
  }

  // ------------------------------------------------------------------ rapor

  static String _adName(String tag) {
    switch (tag) {
      case 'revive_moves':
        return L.t('+5 hamle (kayıpta)', '+5 moves (on loss)');
      case 'revive_slots':
        return L.t('+2 park yeri (kayıpta)', '+2 slots (on loss)');
      case 'slot_unlock':
        return L.t('Kilitli park yeri', 'Locked parking slot');
      case 'booster_ad':
        return L.t('Booster (+1)', 'Booster (+1)');
      case 'double_coins':
        return L.t('Coin x2', 'Coin x2');
      default:
        return tag;
    }
  }

  /// Ekranda gösterilen özet metin.
  static String report() {
    int starts = 0, wins = 0, losses = 0, boosters = 0;
    for (final l in levels.values) {
      starts += l[iStart];
      wins += l[iWin];
      losses += l[iLoseMoves] + l[iLoseSlots];
      boosters += l[iBooster];
    }
    final b = StringBuffer();
    if (starts == 0) {
      return L.t('Henüz veri yok. Birkaç seviye oyna, sonra tekrar bak.', 'No data yet. Play a few levels, then check again.');
    }
    final lossRate = (wins + losses) == 0 ? 0 : (100 * losses / (wins + losses)).round();
    b.writeln(L.t('Deneme: $starts   Kazanma: $wins   Kayıp: $losses (%$lossRate)',
        'Attempts: $starts   Wins: $wins   Losses: $losses ($lossRate%)'));
    b.writeln(L.t('Booster kullanımı: $boosters   Coinle alınan: $coinBuys', 'Boosters used: $boosters   Bought with coins: $coinBuys'));
    b.writeln();
    b.writeln(L.t('REKLAM (teklif → izlenen)', 'ADS (offered → watched)'));
    if (ads.isEmpty) {
      b.writeln(L.t('Henüz reklam teklifi yok.', 'No ad offers yet.'));
    } else {
      final tags = ads.keys.toList()..sort();
      for (final t in tags) {
        final o = ads[t]![0], w = ads[t]![1];
        final pct = o == 0 ? 0 : (100 * w / o).round();
        b.writeln('${_adName(t)}: $o → $w (%$pct)');
      }
    }
    b.writeln();
    b.writeln(L.t('EN ÇOK KAYBEDİLEN SEVİYELER', 'MOST LOST LEVELS'));
    final rows = levels.entries.where((e) => e.value[iLoseMoves] + e.value[iLoseSlots] > 0).toList()
      ..sort((a, c) {
        final la = a.value[iLoseMoves] + a.value[iLoseSlots];
        final lc = c.value[iLoseMoves] + c.value[iLoseSlots];
        return lc != la ? lc.compareTo(la) : a.key.compareTo(c.key);
      });
    if (rows.isEmpty) {
      b.writeln(L.t('Henüz kayıp yok.', 'No losses yet.'));
    }
    for (final e in rows.take(10)) {
      final v = e.value;
      final lost = v[iLoseMoves] + v[iLoseSlots];
      b.writeln(L.t('Seviye ${e.key}: $lost kayıp / ${v[iStart]} deneme, reklam ${v[iAdWatch]}/${v[iAdOffer]}',
          'Level ${e.key}: $lost lost / ${v[iStart]} tries, ads ${v[iAdWatch]}/${v[iAdOffer]}'));
    }
    return b.toString().trimRight();
  }
}
