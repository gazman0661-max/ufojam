import 'package:shared_preferences/shared_preferences.dart';

/// Uygulama sürümü (Seçenekler sayfasının altında görünür).
const String kAppVersion = '0.13.33';

/// Kalıcı kullanıcı ayarları (Seçenekler sayfası).
class Settings {
  static bool music = true; // arka plan müziği (lib/audio.dart)
  static bool sfx = true; // ses efektleri (lib/audio.dart)
  static bool vibration = true; // titreşim (oyunda kullanılıyor)
  static bool screenFx = true; // ekran efektleri: havai fişek, kapı/portal/kat parıltıları

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      music = p.getBool('s_music') ?? true;
      sfx = p.getBool('s_sfx') ?? true;
      vibration = p.getBool('s_vibration') ?? true;
      screenFx = p.getBool('s_screenFx') ?? true;
    } catch (_) {}
  }

  static Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('s_music', music);
      await p.setBool('s_sfx', sfx);
      await p.setBool('s_vibration', vibration);
      await p.setBool('s_screenFx', screenFx);
    } catch (_) {}
  }

  /// Titreşim ayarı açıksa verilen titreşimi çalıştırır: Settings.vibe(HapticFeedback.mediumImpact);
  static void vibe(Future<void> Function() haptic) {
    if (vibration) haptic();
  }
}
