import 'dart:io' show Platform, exit;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Kullanım Şartları + Gizlilik Politikası onayı.
///
/// Metinler değişirse [kLegalVersion] değerini artır: herkese popup yeniden gösterilir.
const int kLegalVersion = 1;

/// Metinlerin altında "İletişim" olarak görünür. Boşsa o bölüm hiç eklenmez.
/// TODO: yayından önce gerçek e-posta adresini yaz.
const String kLegalContact = '';

/// Yayınlanmış metin adresleri (https://...). Doluysa popup ve Seçenekler tarayıcıda bu
/// adresi açar; boşsa ya da açılamazsa uygulama içindeki metin gösterilir.
const String kTermsUrl = 'https://filinta01453-ui.github.io/ufo_legal/kullanim-sartlari.html';
const String kPrivacyUrl = 'https://filinta01453-ui.github.io/ufo_legal/gizlilik-politikasi.html';

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

final List<String> kTermsText = <String>[
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

final List<String> kPrivacyText = <String>[
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
