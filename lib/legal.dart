import 'dart:io' show Platform, exit;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n.dart';

/// Kullanım Şartları + Gizlilik Politikası onayı.
///
/// Metinler değişirse [kLegalVersion] değerini artır: herkese popup yeniden gösterilir.
const int kLegalVersion = 1;

/// Metinlerin altında "İletişim" olarak görünür. Boşsa o bölüm hiç eklenmez.
/// TODO: yayından önce gerçek e-posta adresini yaz.
const String kLegalContact = '';

/// Yayınlanmış metin adresleri (https://...). Doluysa popup ve Seçenekler tarayıcıda bu
/// adresi açar; boşsa ya da açılamazsa uygulama içindeki metin gösterilir.
const String _kTermsUrlTr = 'https://filinta01453-ui.github.io/ufo_legal/kullanim-sartlari.html';
const String _kPrivacyUrlTr = 'https://filinta01453-ui.github.io/ufo_legal/gizlilik-politikasi.html';

/// İngilizce yayınlanmış adresler. TODO: İngilizce sayfaları yayınlayınca buraya yaz.
/// Boş kaldığı sürece İngilizce oyuncular uygulama içindeki İngilizce metni görür.
const String _kTermsUrlEn = '';
const String _kPrivacyUrlEn = '';

/// Seçili dile göre yayınlanmış adres (dil değişince otomatik güncellenir).
String get kTermsUrl => L.isTr ? _kTermsUrlTr : _kTermsUrlEn;
String get kPrivacyUrl => L.isTr ? _kPrivacyUrlTr : _kPrivacyUrlEn;

class Legal {
  static bool accepted = false;

  /// [url] dış tarayıcıda açılır. Boşsa ya da açılamazsa false döner (çağıran yedek metne düşer).
  static Future<bool> openUrl(String url) async {
    if (url.isEmpty) return false;
    try {
      return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static String get _key => 'legal_accepted_v$kLegalVersion';

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      accepted = p.getBool(_key) ?? false;
    } catch (_) {}
  }

  static Future<void> accept() async {
    accepted = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key, true);
    } catch (_) {}
  }

  /// Reddedilince oyunu kapatır. Android: uygulama kapanır. iOS'ta kodla kapatma
  /// önerilmez ama istenen davranış bu olduğu için exit(0) kullanılır.
  static Future<void> quit() async {
    await SystemNavigator.pop();
    if (Platform.isIOS) exit(0);
  }
}

// ---------------------------------------------------------------------------
// Metinler: [başlık, metin, başlık, metin, ...]  (InfoScreen bu sırayla gösterir)
// Hem ilk açılış popup'ı hem Seçenekler > Hakkında sayfaları bunları kullanır.
// ---------------------------------------------------------------------------

/// Seçili dile göre Kullanım Şartları metni.
List<String> get kTermsText => L.isTr ? _termsTr() : _termsEn();

/// Seçili dile göre Gizlilik Politikası metni.
List<String> get kPrivacyText => L.isTr ? _privacyTr() : _privacyEn();

List<String> _termsTr() => <String>[
  'Son güncelleme',
  '10 Kasım 2026',
  '1. Kabul',
  'UFO Bus Jam\'i indirerek veya oynayarak bu Kullanım Şartları\'nı kabul etmiş olursun. Kabul etmiyorsan oyunu kullanma.',
  '2. Kullanım hakkı',
  'Oyunu kişisel ve ticari olmayan eğlence amacıyla kullanman için sana sınırlı, devredilemez bir kullanım hakkı verilir.',
  '3. Yasak davranışlar',
  'Oyunu kopyalamak, değiştirmek, tersine mühendislikle çözmeye çalışmak, yeniden satmak veya dağıtmak; hile ya da otomasyon yazılımı kullanmak; oyunun işleyişini bozmaya çalışmak yasaktır.',
  '4. Oyun içi ögeler',
  'Coin ve güçlendiriciler yalnızca oyun içinde geçerli sanal ögelerdir. Gerçek para değeri yoktur, nakde çevrilemez ve başkasına devredilemez.',
  '5. Reklam ve satın alma',
  'Oyuna ileride reklam veya uygulama içi satın alma eklenebilir. Eklendiğinde bu şartlar güncellenir; satın alımlar ilgili mağazanın (Google Play / App Store) kurallarına tabidir.',
  '6. İlerleme kaydı',
  'İlerlemen yalnızca cihazında saklanır. Uygulamayı silmek, verilerini temizlemek veya cihaz değiştirmek ilerlemeni silebilir; bu durumda kayıp geri getirilemez.',
  '7. Fikri haklar',
  'Oyunun yazılımı, görselleri, sesleri ve diğer içeriklerine ilişkin haklar geliştiriciye aittir veya lisanslıdır. Bu haklar sana devredilmez.',
  '8. Sorumluluk',
  'Oyun "olduğu gibi" sunulur; kesintisiz ya da hatasız çalışacağı garanti edilmez. Yasaların izin verdiği ölçüde, oyunun kullanımından doğabilecek zararlardan sorumluluk kabul edilmez.',
  '9. Değişiklikler',
  'Bu şartlar zaman zaman güncellenebilir. Önemli değişikliklerde onayın yeniden istenebilir. Güncellemeden sonra oyunu kullanmaya devam etmen yeni şartları kabul ettiğin anlamına gelir.',
  if (kLegalContact.isNotEmpty) ...<String>['10. İletişim', 'Sorular için: $kLegalContact'],
];

List<String> _privacyTr() => <String>[
  'Son güncelleme',
  '10 Kasım 2026',
  'Kısaca',
  'Bu sürümde senden kişisel veri toplamıyoruz. Hesap açman, ad, e-posta, konum, rehber ya da fotoğraf izni vermen gerekmez.',
  'Cihazında saklananlar',
  'Seviyen, coin ve güçlendirici stokun, öğretici ilerlemen, ses/titreşim/ekran efekti ayarların ve bu şartları kabul ettiğin bilgisi yalnızca cihazının yerel depolamasında tutulur. Bu bilgiler bize ya da bir sunucuya gönderilmez.',
  'Üçüncü taraflar',
  'Bu sürüm reklam, analiz, çökme raporlama veya sosyal medya girişi gibi üçüncü taraf hizmetleri kullanmaz ve seni takip etmez.',
  'Reklamlar (ileride)',
  'Oyuna reklam eklenirse reklam sağlayıcıları reklam kimliği, yaklaşık konum ve cihaz bilgisi gibi verileri işleyebilir. Böyle bir değişiklikte bu metin güncellenir, gerekli durumlarda rızan istenir ve rızanı Seçenekler > Reklam Rızasını Yönet bölümünden yönetebilirsin.',
  'Çocuklar',
  'Çocuklardan bilerek kişisel veri toplamıyoruz.',
  'Verilerini silmek',
  'Verilerin yalnızca cihazında durduğu için uygulamayı silerek hepsini kaldırabilirsin. Ana ekrandaki “İlerlemeyi sıfırla” düğmesi de oyun ilerlemeni baştan başlatır.',
  'Hakların',
  'Kişisel verilerin korunmasına ilişkin yürürlükteki mevzuat (KVKK vb.) kapsamındaki haklarını kullanmak için bize ulaşabilirsin.',
  'Değişiklikler',
  'Bu politika güncellenebilir. Önemli değişikliklerde onayın yeniden istenebilir.',
  if (kLegalContact.isNotEmpty) ...<String>['İletişim', kLegalContact],
];

List<String> _termsEn() => <String>[
  'Last updated',
  'November 10, 2026',
  '1. Acceptance',
  'By downloading or playing UFO Bus Jam, you agree to these Terms of Use. If you do not agree, do not use the game.',
  '2. License',
  'You are granted a limited, non-transferable license to use the game for personal, non-commercial entertainment.',
  '3. Prohibited conduct',
  'You may not copy, modify, reverse engineer, resell or distribute the game; use cheats or automation software; or try to disrupt how the game works.',
  '4. In-game items',
  'Coins and boosters are virtual items that only have value inside the game. They have no real-world monetary value, cannot be exchanged for cash and cannot be transferred to anyone else.',
  '5. Ads and purchases',
  'Ads or in-app purchases may be added to the game in the future. If so, these terms will be updated; purchases are subject to the rules of the relevant store (Google Play / App Store).',
  '6. Saved progress',
  'Your progress is stored only on your device. Deleting the app, clearing its data or switching devices may erase your progress, and it cannot be recovered.',
  '7. Intellectual property',
  'The rights to the game\'s software, graphics, sounds and other content belong to the developer or are licensed to them. These rights are not transferred to you.',
  '8. Liability',
  'The game is provided "as is"; it is not guaranteed to run without interruption or errors. To the extent permitted by law, no liability is accepted for any damages arising from the use of the game.',
  '9. Changes',
  'These terms may be updated from time to time. For significant changes, your consent may be requested again. If you keep using the game after an update, you accept the new terms.',
  if (kLegalContact.isNotEmpty) ...<String>['10. Contact', 'For questions: $kLegalContact'],
];

List<String> _privacyEn() => <String>[
  'Last updated',
  'November 10, 2026',
  'In short',
  'This version does not collect personal data from you. You do not need to create an account or give permission for your name, email, location, contacts or photos.',
  'Stored on your device',
  'Your level, coins and booster stock, tutorial progress, sound / vibration / screen effect settings and the fact that you accepted these terms are kept only in your device\'s local storage. This information is not sent to us or to any server.',
  'Third parties',
  'This version does not use third-party services such as ads, analytics, crash reporting or social login, and it does not track you.',
  'Ads (in the future)',
  'If ads are added to the game, ad providers may process data such as the advertising ID, approximate location and device information. If that happens, this text will be updated, your consent will be requested where required, and you can manage it under Options > Manage Ad Consent.',
  'Children',
  'We do not knowingly collect personal data from children.',
  'Deleting your data',
  'Because your data only stays on your device, you can remove all of it by uninstalling the app. The “Reset progress” button on the home screen also restarts your game progress from the beginning.',
  'Your rights',
  'You can contact us to exercise your rights under the applicable personal data protection legislation (e.g. KVKK).',
  'Changes',
  'This policy may be updated. For significant changes, your consent may be requested again.',
  if (kLegalContact.isNotEmpty) ...<String>['Contact', kLegalContact],
];
