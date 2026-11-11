import 'dart:math';

/// Saf Dart modelleri (Flutter'a bağımlı değil, test edilebilir).

/// UFO koltuk sınıfları. Referans oyunda araçlar 4 / 6 / 10 koltuklu (kapasite 16/24/40 = koltuk x 4)
/// ve görseller (ufo4_*, ufo6_*, ufo10_*) de aynı sınıfları çiziyor.
const List<int> kSeatClasses = [4, 6, 10];

/// "Zor" (40 coin ödüllü) seviyeler. İlk 25 seviye yumuşak başlangıç (zor yok); referans ritmi 26'dan
/// başlar: 26, 29, 35, 40, 46, 51, 56, 59, sonrasında her 5. seviye (referansta 5000 sıra boyunca sürer).
/// Zor seviyeden sonra gelen seviye RAHAT (nefes) seviyesidir.
const Set<int> kHardEarly = {26, 29, 35, 40, 46, 51, 56, 59};

bool isHardLevel(int n) {
  if (n <= 59) return kHardEarly.contains(n);
  return n > 60 && n % 5 == 0;
}

bool isReliefLevel(int n) => n > 1 && isHardLevel(n - 1);

/// Bir yolcu = 4 kapasite birimi (referans verisi: kapasite = yolcu x 4). Araç altındaki sayaç 16 / 24 / 40'tan
/// başlar ve ekranda 1'er 1'er düşer (referans öyle); bir yolcu binince 4 hızlı adım sayar. 0 olunca araç gider.
const int kCapPerPassenger = 4;

// ------------------------------------------------------------ gövde ölçüleri
// Birim = referans seviyelerin dünya birimi. Ölçüler referanstaki en sıkı araç aralıklarından çıkarıldı
// (en 0.5, boy 0.9 / 1.0 / 1.35). tools/convert_levels.py ile BİREBİR aynı sabitler.

const double kUfoWidth = 0.5;
const double kStripFactor = 0.5; // aracın önündeki çarpışma şeridi genişliği = en x bu
const double kBodyShrink = 0.8; // başka aracın gövdesi bu kadar küçültülerek test edilir

double ufoLength(int seats) => seats >= 10 ? 1.35 : (seats >= 6 ? 1.0 : 0.9);

/// Ekranda çizilen UFO çapı (birim). Gövde ölçüsünden biraz küçük: UFO yuvarlak, yan yana araçlar sıkışmasın.
double ufoDiameter(int seats) => seats >= 10 ? 0.92 : (seats >= 6 ? 0.78 : 0.68);

// ------------------------------------------------------------ özgün mekanikler (kural katmanı)

/// Özgün mekanikler: hamle bütçesi, dönen UFO, arızalı UFO. (Altın UFO, çift kabin, bukalemun, renk kapısı ve
/// anahtar yolcu denendi, oyunu fazla kolaylaştırdığı/anlamsız bulunduğu için kaldırıldı.)
/// Işınlama kapısı (üst üste doğan UFO'lar) ve katman asansörü kural katmanından değil, seviye düzeninden gelir.
enum Mech { budget, rotor, faulty, belt }

/// Mekaniğin ilk tanıtıldığı seviye (ZOR olmayan, rahat olmayan normal seviye).
const Map<Mech, int> kMechUnlock = {
  Mech.budget: 16,
  Mech.rotor: 21,
  Mech.faulty: 32,
  Mech.belt: 45,
};

const Map<Mech, String> kMechTitle = {
  Mech.budget: 'Hamle bütçesi',
  Mech.rotor: 'Dönen UFO',
  Mech.faulty: 'Arızalı UFO',
  Mech.belt: 'Bant UFO',
};

const Map<Mech, String> kMechDesc = {
  Mech.budget: 'Dokunuş hakkın sınırlı. Kapalı UFO\'ya dokunmak da hamle sayılır.',
  Mech.rotor: 'Mavi halkalı UFO belli aralıkla yön değiştirir. Önü açıkken dokun!',
  Mech.faulty: 'Üstündeki sayı her hamlede düşer. 0 olursa UFO bozulup gider.',
  Mech.belt: 'Bant üstünde kayan UFO sadece ortadayken (yeşil halka) çağrılır.',
};

/// Bir seviyeye uygulanan özel kurallar. Seviye numarasından ve sabit tohumdan üretilir
/// (rules.dart), yani aynı seviye her açıldığında aynı kurallarla gelir.
class LevelRules {
  final List<Mech> mechs;
  final int moveBudget; // 0: yok; en fazla bu kadar UFO dokunuşu (başarılı + kapalı UFO'ya dokunuş)

  /// Dönen UFO'lar (ufo id). Her biri önce özgün yönünde [rotorOn] sn durur, sonra 180° dönüp [rotorOff] sn bekler.
  /// Gövde simetrik olduğu için dönüş başkasının önünü kapatmaz/açmaz: sadece kendi çıkış yönü değişir,
  /// özgün yön her turda geri gelir (çözülebilirlik korunur).
  final List<int> rotors;
  final double rotorOn;
  final double rotorOff;

  /// Arızalı UFO'lar: ufo id -> başlangıç sayacı (her başarılı UFO çıkışında 1 düşer, 0'da UFO bozulup gider).
  final Map<int, int> faulty;
  final int faultSlack; // geri gelen UFO'nun sayacı: önündeki engel zinciri + bu pay

  /// Bant UFO'lar (ufo id): bant üzerinde yana doğru ileri geri kayar, sadece ortadayken (pencere) çağrılabilir.
  /// Çarpışma gövdesi hep bulunduğu yerde sayılır (kayma görsel); pencere her turda tekrar açıldığı için
  /// çözülebilirlik korunur.
  final List<int> belts;
  final double beltCycle; // bir tam gidiş-geliş (sn)
  final double beltWin; // pencere: |konum| < beltWin (konum -1..1)

  const LevelRules({
    this.mechs = const <Mech>[],
    this.moveBudget = 0,
    this.rotors = const <int>[],
    this.rotorOn = 3.4,
    this.rotorOff = 1.8,
    this.faulty = const <int, int>{},
    this.faultSlack = 6,
    this.belts = const <int>[],
    this.beltCycle = 4.0,
    this.beltWin = 0.3,
  });

  static const LevelRules none = LevelRules();

  bool get isEmpty => mechs.isEmpty;
}

/// Izgarasız seviyedeki tek bir UFO'nun değişmeyen tanımı. id == listedeki indeks.
class UfoSpec {
  final int id;
  final double x; // tahta birimi, sağa +
  final double y; // tahta birimi, aşağı +
  final double angle; // radyan, saat yönünde, 0 = yukarı bakar
  final int color; // 0..14
  final int seats; // 4, 6 veya 10
  final bool mystery; // önü kapalıyken rengi gizli
  final int group; // -1: tek araç; >= 0: aynı gruptaki araçlar üst üste doğar (öndeki gidince sıradaki belirir)

  const UfoSpec({
    required this.id,
    required this.x,
    required this.y,
    required this.angle,
    required this.color,
    required this.seats,
    this.mystery = false,
    this.group = -1,
  });

  /// Referanstaki kapasite (16 / 24 / 40).
  int get capacity => seats * kCapPerPassenger;

  double get dirX => sin(angle);
  double get dirY => -cos(angle);

  /// Aynı UFO, ters yöne (180°) bakıyor. Gövde dikdörtgeni merkez etrafında simetrik olduğu için
  /// başkalarını engelleme durumu değişmez; sadece kendi çıkış yönü değişir (dönen UFO).
  UfoSpec flipped() => UfoSpec(
        id: id,
        x: x,
        y: y,
        angle: angle + pi,
        color: color,
        seats: seats,
        mystery: mystery,
        group: group,
      );
}

class LevelData {
  final int number;
  final int stage; // düzen anahtarı (halka şekli ve kapasitesi buna bağlı; number değil)
  final int slots; // başlangıç park yeri sayısı
  final int colorCount;
  final List<UfoSpec> ufos;
  final List<List<int>> arms; // iki kolun yolcu sırası (renk indeksleri), 0: sol, 1: sağ
  final int ringCap; // halka hücre sayısı = aynı anda taşıdığı yolcu (3 şeritin katı, seviyeye göre 63..84; ring_data.dart)
  final String hint;
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;
  final LevelRules rules;

  /// Katman asansörü: her UFO'nun katmanı (boş liste: tek katman). Kalabalık düzenlerde 0. katman önce görünür,
  /// hepsi bitince 1. katman asansörle çıkar (stage_extras.dart, tools/solve_layers.py ile doğrulandı).
  final List<int> layerOf;

  /// Her katmanın UFO sınırları: [minX, minY, maxX, maxY] (kamera katmana göre oturur).
  final List<List<double>> layerBounds;

  /// Katmanlı düzende her kolda 1. katman yolcusu sayısı (Karıştır bu sınırı geçmez). Boş: katman yok.
  final List<int> armCut;

  const LevelData({
    required this.number,
    this.stage = 0,
    required this.slots,
    required this.colorCount,
    required this.ufos,
    required this.arms,
    required this.ringCap,
    required this.hint,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    this.rules = LevelRules.none,
    this.layerOf = const <int>[],
    this.layerBounds = const <List<double>>[],
    this.armCut = const <int>[],
  });

  LevelData withRules(LevelRules r) => LevelData(
        number: number,
        stage: stage,
        slots: slots,
        colorCount: colorCount,
        ufos: ufos,
        arms: arms,
        ringCap: ringCap,
        hint: hint,
        minX: minX,
        minY: minY,
        maxX: maxX,
        maxY: maxY,
        rules: r,
        layerOf: layerOf,
        layerBounds: layerBounds,
        armCut: armCut,
      );

  int get layerCount => layerBounds.isEmpty ? 1 : layerBounds.length;

  int layerOfUfo(int id) => layerOf.isEmpty ? 0 : layerOf[id];

  /// l. katmandaki UFO sayısı.
  int layerSize(int l) {
    if (layerOf.isEmpty) return ufos.length;
    int n = 0;
    for (final v in layerOf) {
      if (v == l) n++;
    }
    return n;
  }

  /// l. katmanın [minX, minY, maxX, maxY] sınırları (katman yoksa tüm düzen).
  List<double> boundsOf(int l) =>
      layerBounds.isEmpty ? <double>[minX, minY, maxX, maxY] : layerBounds[l.clamp(0, layerBounds.length - 1)];

  int get totalPassengers => arms[0].length + arms[1].length;

  double get boardW => maxX - minX;
  double get boardH => maxY - minY;

  bool get isHard => isHardLevel(number);

  /// VIP yuva (park şeridinde 1. yuva, altın renkli) 10. seviyeden itibaren (referansta 4'tü, yumuşak başlangıç için 10).
  bool get hasVip => number >= 10;

  /// Referans: zor seviyede 40, diğerlerinde 20 coin.
  int get reward => isHard ? 40 : 20;
}
