import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Basit ilerleme kaydı: açık seviye ve coin.
/// TEST: belirli bir seviyeden başlatmak için sayı yaz (örn. 110). Normal oyun için null.
const int? kTestLevel = null;

class Progress {
  static int level = 1;
  static int coins = 0;
  static Set<String> guidesSeen = <String>{}; // tamamlanan öğretici bölümleri

  /// Booster stoğu: 0 Hemen Bin, 1 Karıştır, 2 Işınla. Her kullanım 1 adet harcar;
  /// stok bitince ödüllü reklamla +1 alınır.
  static const int startStock = 3;
  static List<int> boostStock = <int>[startStock, startStock, startStock];

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      level = p.getInt('level') ?? 1;
      coins = p.getInt('coins') ?? 0;
      guidesSeen = (p.getStringList('guides') ?? <String>[]).toSet();
      final st = p.getStringList('boostStock');
      if (st != null && st.length == 3) {
        boostStock = st.map((e) => max(0, int.tryParse(e) ?? 0)).toList();
      }
    } catch (_) {}
    if (kTestLevel != null) {
      // Test sürümü: uygulama her açılışta bu seviyeden başlar, öğreticiler/açılış pencereleri kapalı.
      level = kTestLevel!;
      guidesSeen.addAll(<String>{
        'basics', 'blocked', 'board', 'shuffle', 'mystery', 'vip', 'spawn',
        'm_gold', 'm_dual', 'm_budget', 'm_chameleon', 'm_gate', 'm_key', 'm_rotor', 'm_faulty', 'm_belt', 'layer',
        'unlock_0', 'unlock_1', 'unlock_2',
      });
    }
  }

  static Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('level', level);
      await p.setInt('coins', coins);
      await p.setStringList('guides', guidesSeen.toList());
      await p.setStringList('boostStock', boostStock.map((e) => '$e').toList());
    } catch (_) {}
  }

  static Future<void> reset() async {
    level = 1;
    coins = 0;
    guidesSeen = <String>{};
    boostStock = <int>[startStock, startStock, startStock];
    await save();
  }
}
