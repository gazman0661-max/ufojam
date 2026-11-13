import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Desteklenen diller.
enum AppLang { tr, en }

/// Çok basit çeviri sistemi: metin kodda yan yana yazılır -> L.t('Türkçe', 'English').
///
/// Açılışta dil şöyle seçilir:
///  1. Oyuncu Seçenekler > Dil'den bir dil seçtiyse o,
///  2. seçmediyse cihaz dili: Türkçe ise Türkçe, diğer tüm diller için İngilizce.
///
/// Yeni dil eklemek için [AppLang]'a değer ekleyip [t] içine yeni parametre eklemek yeterli
/// (şimdilik iki dil olduğu için bu hâliyle bırakıldı).
class L {
  static const String _key = 's_lang';

  static AppLang lang = AppLang.en;

  static bool get isTr => lang == AppLang.tr;
  static bool get isEn => lang == AppLang.en;

  /// Seçili dile göre metni döndürür.
  static String t(String tr, String en) => lang == AppLang.tr ? tr : en;

  /// Cihazın birincil dili Türkçe ise Türkçe, değilse İngilizce.
  static AppLang deviceLang() {
    try {
      final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
      return code == 'tr' ? AppLang.tr : AppLang.en;
    } catch (_) {
      return AppLang.en;
    }
  }

  /// Uygulama açılırken çağrılır (main.dart).
  static Future<void> load() async {
    lang = deviceLang();
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(_key);
      for (final l in AppLang.values) {
        if (l.name == saved) lang = l;
      }
    } catch (_) {}
  }

  /// Dili değiştirir, kaydeder ve açık olan tüm ekranları yeniden çizdirir.
  static Future<void> setLang(AppLang l) async {
    if (l == lang) return;
    lang = l;
    rebuildAll();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, l.name);
    } catch (_) {}
  }

  /// Widget ağacındaki her şeyi yeniden çizer (metinler L.t ile build sırasında okunduğu için
  /// dil değişince açık ekranların da güncellenmesi gerekir).
  static void rebuildAll() {
    void rebuild(Element el) {
      el.markNeedsBuild();
      el.visitChildren(rebuild);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
  }
}
