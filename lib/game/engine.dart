import 'dart:math';

import 'geometry.dart';
import 'models.dart';

// ---------------------------------------------------------------- sabitler
// tools/sim_live.py ile birebir aynı değerler (denge ölçümü orada yapılır).

const int kRingCols = 16; // (eski varsayılan; artık seviyeye göre: LevelData.ringCap / kRingLanes)
const int kRingLanes = 3; // yol genişliğindeki şerit sayısı
const int kRingCells = kRingCols * kRingLanes; // eski sabit 48 hücre (artık kullanılmıyor, seviye başına LevelData.ringCap)
const double kLaneStagger = 0.0; // şeritler arası sütun kayması: 0 = yolcular düzgün sıralar halinde dizilir, bir sıra aynı anda biner (referans gibi)
const double kPrefillFront = 0.3; // halkanın kapıya yakın ön kısmı (sağ giriş ile kapı arası) hazır dolarken sağ koldan, gerisi sol koldan dolar
const double kGateSpan = 0.12; // kapıların halka üzerindeki toplam yarı genişliği (devir oranı)
const double kLandSec = 2.2; // UFO'nun park yerine inme süresi
const double kBeamSec = 1.4; // ışınlamanın (Işınla) UFO'yu VIP yuvaya taşıma süresi
const double kIntroMul = 4.0; // bölüm başında halkayı doldururken hız çarpanı
const double kRingSpeed = 0.09; // taban hız: devir / saniye

/// Park şeridi (referans verisi: containerholder_count=4, reward_containerholder_count=3):
/// başlangıçta 4 açık yuva (L4+ ilki VIP) ve reklam izleyerek açılan 3 kilitli yuva.
const int kOpenSlots = 4;
const int kLockedSlots = 3;

/// Arızalı UFO bozulup gidince, bu kadar UFO çıkışından sonra (ya da sahada başka UFO kalmayınca) aynı yerine geri gelir.
const int kFaultAwayMoves = 3;

double fracS(double x) => x - x.floorToDouble();

/// Hücrenin halka üzerindeki yol uzaklığı (devir oranı). Konum = faz - ofset.
double cellOffset(int i, int cols) =>
    ((i ~/ kRingLanes) + (i % kRingLanes) * kLaneStagger) / cols;

/// Referanstaki gibi TEK kapı: halkanın alt kenarının ortası. Bütün park yerlerindeki UFO'lar
/// yolcuları bu kapıdan alır (park sırasına göre ilk uygun UFO biner).
double gateS(int k, int count) => 0.0;

/// Halkadaki tek bir yolcu. id = giriş sırası (benzersiz).
class Passenger {
  final int id;
  final int color;
  const Passenger(this.id, this.color);
}

/// Bir yolcunun UFO'ya binişi. cell: yolcunun bindiği anda durduğu halka hücresi,
/// gate: bindiği kapı (park yeri indeksi).
class BoardEvent {
  final int ufoId;
  final int passengerId;
  final int color;
  final int cell;
  final int gate;
  const BoardEvent(this.ufoId, this.passengerId, this.color, this.cell, this.gate);
}

class UfoState {
  final UfoSpec spec;
  late UfoSpec cur; // şu anki yön (dönen UFO'da ters olabilir); çıkış/engel hesapları bunu kullanır
  late final UfoSpec flip; // ters yönlü kopya
  int boarded = 0;
  bool inGrid = true; // hâlâ sahada (park yerine gitmedi)
  bool spawned; // sahada görünür mü (üst üste doğan araçlarda sadece öndeki, katmanlı düzende sadece açık katman)
  bool departed = false;
  int lastSlot = -1;

  // ---- dönen UFO
  bool rotor = false;
  bool flipped = false;
  double rotOffset = 0.0; // dönüş döngüsünde başlangıç kayması (sn)
  bool belt = false; // bant UFO: bant üstünde kayar, sadece ortadayken çağrılır
  double beltOffset = 0.0;
  double flipClock = -10.0; // son yön değişiminin oyun saati (dönüş animasyonu için)

  // ---- arızalı UFO
  int fault = 0; // 0: arızalı değil; > 0: kalan hamle sayacı
  int faultBase = 0; // başlangıç sayacı (tamirde buna dönülür)
  bool away = false; // bozulup gitti, birazdan geri gelecek (spawned == false)
  int awayMoves = 0;

  UfoState(this.spec, this.spawned) {
    cur = spec;
    flip = spec.flipped();
  }

  bool get faulty => faultBase > 0;
}

/// CANLI OYUN (arayüzün kullandığı motor).
///
/// - Araçlar serbest konum ve serbest açıdadır (ızgara yok): bir araç, kendi yönündeki şeritte başka araç
///   yoksa çıkabilir (geometry.dart). Aynı gruptaki araçlar üst üste doğar: öndeki gidince sıradaki belirir.
/// - Halka 48 hücreli sabit bir konveyör, sürekli döner. Her hücrede en fazla 1 yolcu.
/// - İki kol (sol/sağ) sırayla yolcu besler: çift sıralı yolcu sol, tek sıralı sağ girişten girer.
///   Boş bir hücre sırası gelen kolun giriş noktasından geçerken yolcu halkaya girer (en fazla ringCap).
/// - Park yerindeki UFO indikten sonra, yolcu SADECE kendi hücresi o park yerinin kapısından
///   geçerken biner (rengi aynıysa ve koltuk varsa). Sırası gelmeyen yolcu turlamaya devam eder.
/// - Koltuklar dolunca UFO gider, park yeri boşalır.
/// - Kazanma: halka ve dış sıra boş. Kaybetme: park yerleri dolu ve hiçbir şey ilerleyemez.
class GameState {
  final LevelData level;
  final List<UfoState> ufos;
  final Map<int, List<int>> groups = <int, List<int>>{}; // grup -> araç id'leri (doğma sırasıyla)
  final List<Passenger?> cells;
  int occupied = 0;
  // Kollar: sol kol çift sıralı, sağ kol tek sıralı yolcuları taşır; her kol kendi sırasıyla bağımsız beslenir.
  final List<List<int>> armQ;
  final List<int> armHead = [0, 0];
  bool introDone = false;
  final List<int> slots; // park yerindeki ufo id, boşsa -1
  final List<double> slotReady; // UFO'nun inmiş olacağı an (clock)
  double phase = 0.0;
  double clock = 0.0;
  int boardedTotal = 0;
  double entryL = 0.405; // sol kolun halkaya giriş noktası (arayüz ayarlar)
  double entryR = 0.595; // sağ kolun giriş noktası
  double speed = kRingSpeed;
  int lockedSlots = kLockedSlots; // reklamla açılabilecek kalan kilitli yuva

  // ---- hamle bütçesi (LevelRules; rules.dart)
  LevelRules get rules => level.rules;
  int movesUsed = 0; // başarılı UFO dokunuşu + kapalı UFO'ya dokunuş

  // ---- katman asansörü (LevelData.layerOf)
  int curLayer = 0; // şu an sahada olan katman
  int layerEvents = 0; // her yeni katman çıkışında artar (arayüz asansör animasyonunu buradan görür)

  // ---- dönen UFO
  int rotVersion = 0; // herhangi bir dönen UFO yön değiştirince artar (arayüz yeniden çizer)

  // ---- arızalı UFO
  final List<int> breakQueue = <int>[]; // sayacı 0'a inen, arayüzün karara bağlayacağı UFO'lar (tamir / bırak)
  int faultEvents = 0; // bozulup gitme / geri gelme olaylarında artar

  GameState(this.level)
      : ufos = [],
        cells = List<Passenger?>.filled(level.ringCap, null),
        armQ = [
          List<int>.from(level.arms[0]),
          List<int>.from(level.arms[1]),
        ],
        // 4. seviyeden itibaren 0. yuva VIP: normal dokunuşla DOLDURULAMAZ, sadece Işınla ile.
        slots = List<int>.filled(level.slots + (level.hasVip ? 1 : 0), -1, growable: true),
        slotReady = List<double>.filled(level.slots + (level.hasVip ? 1 : 0), 0.0, growable: true) {
    for (final s in level.ufos) {
      if (s.group >= 0) groups.putIfAbsent(s.group, () => <int>[]).add(s.id);
    }
    for (final s in level.ufos) {
      final first = (s.group < 0 || groups[s.group]!.first == s.id) && level.layerOfUfo(s.id) == 0;
      ufos.add(UfoState(s, first));
    }
    // Dönen / arızalı UFO'lar (kural katmanı)
    int ri = 0;
    for (final id in level.rules.rotors) {
      if (id < 0 || id >= ufos.length) continue;
      ufos[id].rotor = true;
      ufos[id].rotOffset = (ri * 1.3) % (level.rules.rotorOn + level.rules.rotorOff);
      ri++;
    }
    int bi = 0;
    for (final id in level.rules.belts) {
      if (id < 0 || id >= ufos.length) continue;
      ufos[id].belt = true;
      ufos[id].beltOffset = (bi * 1.1) % level.rules.beltCycle;
      bi++;
    }
    level.rules.faulty.forEach((id, c) {
      if (id < 0 || id >= ufos.length) return;
      ufos[id].fault = c;
      ufos[id].faultBase = c;
    });
    // Halka bölüm başında HAZIR dolu başlar (referans gibi); kollar da dolu kalır.
    final pre = min(level.ringCap, level.totalPassengers);
    // Her koldan RENK BLOKLARI halinde alınır (hücreler sütun sütun dolar): çorba gibi karışık değil, aynı renk yan yana.
    final cols0 = (level.ringCap / kRingLanes).ceil();
    for (int i = 0; i < pre; i++) {
      int a = ((i ~/ kRingLanes) / cols0) < kPrefillFront ? 1 : 0;
      if (armHead[a] >= armQ[a].length) a = 1 - a;
      cells[i] = Passenger(armId(a, armHead[a]), armQ[a][armHead[a]]);
      armHead[a]++;
      occupied++;
    }
    introDone = true;
  }

  /// Halkaya girmiş toplam yolcu sayısı.
  int get qHead => armHead[0] + armHead[1];

  int get outsideCount => level.totalPassengers - qHead;

  int armRemaining(int a) => armQ[a].length - armHead[a];

  /// a. kolun m. yolcusunun benzersiz kimliği (kuyruktaki genel sıra).
  int armId(int a, int m) => 2 * m + a;

  int get remainingTotal => occupied + outsideCount;

  /// Halkadaki sütun sayısı: referansta halka şekli/uzunluğu seviyeye göre değişir (ringCap seviyeden gelir).
  int get ringCols => (level.ringCap / kRingLanes).ceil();

  double cellS(int i) => fracS(phase - cellOffset(i, ringCols));

  int get moveBudget => rules.moveBudget;
  int get movesLeft => moveBudget > 0 ? moveBudget - movesUsed : 0;
  bool get outOfMoves => moveBudget > 0 && movesUsed >= moveBudget && ufos.any((u) => u.inGrid);

  /// Kapalı UFO'ya dokunuş da bir hamledir (hamle bütçesi seviyelerinde).
  void noteWastedTap() {
    movesUsed++;
  }

  /// Kayıp ekranında ödüllü reklamla ek hamle.
  void grantMoves(int n) {
    movesUsed = max(0, movesUsed - n);
  }

  /// Bölüm başında halka dolana kadar hızlı döner (bir kez).
  bool get introActive {
    if (introDone) return false;
    if (occupied >= min(level.ringCap, level.totalPassengers) || clock >= 10.0) {
      introDone = true;
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------- saha

  /// Araç sahada ve görünür mü (henüz doğmamış üst üste araçlar dokunulamaz, çarpmaz).
  bool isOnField(int id) => ufos[id].inGrid && ufos[id].spawned;

  /// Yönünde ilk çarptığı aracın mesafesi (tahta birimi, ön kenardan). Engel yoksa -1.
  double blockerDistance(int id) {
    final m = ufos[id].cur;
    double best = -1;
    for (final o in ufos) {
      if (o.spec.id == id || !o.inGrid || !o.spawned) continue;
      final d = sweepHit(m, o.cur);
      if (d != null && (best < 0 || d < best)) best = d;
    }
    return best;
  }

  /// Yönünde ilk çarptığı aracın id'si (engel yoksa null). Öğretici "önündekini çıkar" demek için kullanır.
  int? firstBlocker(int id) {
    final m = ufos[id].cur;
    double best = -1;
    int? who;
    for (final o in ufos) {
      if (o.spec.id == id || !o.inGrid || !o.spawned) continue;
      final d = sweepHit(m, o.cur);
      if (d != null && (best < 0 || d < best)) {
        best = d;
        who = o.spec.id;
      }
    }
    return who;
  }

  bool canLaunch(int id) {
    if (!isOnField(id)) return false;
    if (ufos[id].belt && !beltOpen(ufos[id])) return false;
    final m = ufos[id].cur;
    for (final o in ufos) {
      if (o.spec.id == id || !o.inGrid || !o.spawned) continue;
      if (sweepHit(m, o.cur) != null) return false;
    }
    return true;
  }

  List<int> launchable() {
    final out = <int>[];
    for (final u in ufos) {
      if (canLaunch(u.spec.id)) out.add(u.spec.id);
    }
    return out;
  }

  /// Araç sahadan çıkar; aynı gruptaki sıradaki araç belirir.
  void removeFromField(int id) {
    final u = ufos[id];
    u.inGrid = false;
    u.away = false;
    final g = u.spec.group;
    if (g >= 0) {
      final list = groups[g]!;
      final i = list.indexOf(id);
      if (i >= 0 && i + 1 < list.length) ufos[list[i + 1]].spawned = true;
    }
    _checkLayer();
  }

  /// Katman asansörü: açık katmanın son UFO'su da sahadan çıkınca bir sonraki katman yukarı çıkar
  /// (o katmandaki tek araçlar ve her grubun öndeki aracı belirir).
  void _checkLayer() {
    while (curLayer < level.layerCount - 1) {
      bool anyLeft = false;
      for (final u in ufos) {
        if (u.inGrid && level.layerOfUfo(u.spec.id) == curLayer) {
          anyLeft = true;
          break;
        }
      }
      if (anyLeft) return;
      curLayer++;
      layerEvents++;
      for (final u in ufos) {
        final id = u.spec.id;
        if (!u.inGrid || level.layerOfUfo(id) != curLayer) continue;
        final gr = u.spec.group;
        if (gr < 0 || groups[gr]!.first == id) u.spawned = true;
      }
    }
  }

  bool isVipSlot(int k) => level.hasVip && k == 0;

  /// Normal dokunuşla kullanılabilen boş park yeri (VIP hariç). Yoksa -1.
  int freeSlot() {
    for (int i = level.hasVip ? 1 : 0; i < slots.length; i++) {
      if (slots[i] == -1) return i;
    }
    return -1;
  }

  int get freeSlotCount {
    int n = 0;
    for (int i = level.hasVip ? 1 : 0; i < slots.length; i++) {
      if (slots[i] == -1) n++;
    }
    return n;
  }

  /// UFO'yu park yerine gönderir. Başarılıysa park yeri indeksi, değilse -1.
  int tap(int id) {
    if (!canLaunch(id)) return -1;
    final k = freeSlot();
    if (k < 0) return -1;
    final u = ufos[id];
    removeFromField(id);
    movesUsed++;
    u.lastSlot = k;
    slots[k] = id;
    slotReady[k] = clock + kLandSec;
    _afterMove();
    return k;
  }

  /// Işınla: önü kapalı olması fark etmeksizin istenen UFO'yu ışınlayarak VIP yuvaya taşır.
  /// Başarılıysa 0 (VIP yuva indeksi), değilse -1.
  int tapVip(int id) {
    if (!level.hasVip || slots[0] != -1) return -1;
    final u = ufos[id];
    if (!isOnField(id)) return -1;
    removeFromField(id);
    movesUsed++;
    u.lastSlot = 0;
    slots[0] = id;
    slotReady[0] = clock + kBeamSec;
    _afterMove();
    return 0;
  }

  // ---------------------------------------------------------- arızalı UFO

  /// UFO'nun önündeki engel zinciri (doğrudan ve dolaylı engelleyenler, şu anki sahada).
  int blockerChain(int id) {
    final seen = <int>{id};
    final stack = <int>[id];
    while (stack.isNotEmpty) {
      final a = stack.removeLast();
      final m = ufos[a].cur;
      for (final o in ufos) {
        if (seen.contains(o.spec.id) || !o.inGrid || !o.spawned) continue;
        if (sweepHit(m, o.cur) != null) {
          seen.add(o.spec.id);
          stack.add(o.spec.id);
        }
      }
    }
    return seen.length - 1;
  }

  /// Her başarılı UFO çıkışından sonra: arızalı sayaçlar düşer, bozulanlar arayüze bildirilir,
  /// bozulup giden UFO'ların dönüş sayacı ilerler.
  void _afterMove() {
    for (final u in ufos) {
      if (u.fault > 0 && u.inGrid && u.spawned && !u.away) {
        u.fault--;
        if (u.fault == 0 && !breakQueue.contains(u.spec.id)) breakQueue.add(u.spec.id);
      }
      if (u.away) u.awayMoves++;
    }
    _tryReturn();
  }

  /// Bozulup giden UFO'lar: yeterli hamle geçtiyse ya da sahada başka UFO kalmadıysa aynı yerine geri gelir.
  void _tryReturn() {
    for (final u in ufos) {
      if (!u.away) continue;
      bool others = false;
      for (final o in ufos) {
        if (o.spec.id != u.spec.id && o.inGrid && o.spawned && !o.away) {
          others = true;
          break;
        }
      }
      if (u.awayMoves >= kFaultAwayMoves || !others) {
        u.away = false;
        u.spawned = true;
        u.fault = blockerChain(u.spec.id) + level.rules.faultSlack;
        faultEvents++;
      }
    }
  }

  /// Tamir (ödüllü reklam): sayaç başlangıç değerine döner, UFO sahada kalır.
  void repairUfo(int id) {
    breakQueue.remove(id);
    final u = ufos[id];
    u.fault = u.faultBase;
  }

  /// Bırak: UFO bozulup gider (sahadan kalkar, hiçbir şeyi engellemez), birkaç hamle sonra geri gelir.
  void breakUfo(int id) {
    breakQueue.remove(id);
    final u = ufos[id];
    u.fault = 0;
    u.away = true;
    u.awayMoves = 0;
    u.spawned = false;
    faultEvents++;
    _tryReturn();
  }

  // ---------------------------------------------------------- bant UFO

  /// Bant üstündeki konum (-1..1): sinüs gidiş-geliş. 0 = bandın ortası (ev konumu).
  double beltPos(UfoState u) => sin(2 * pi * ((clock + u.beltOffset) % level.rules.beltCycle) / level.rules.beltCycle);

  /// Pencere açık mı (UFO bandın ortasında)?
  bool beltOpen(UfoState u) => beltPos(u).abs() < level.rules.beltWin;

  /// Yolu açık olsa bile sadece bant penceresi yüzünden çağrılamıyor mu? (arayüz "kaçırdın" demek için)
  bool missedBelt(int id) {
    final u = ufos[id];
    if (!u.belt || !isOnField(id) || beltOpen(u)) return false;
    final m = u.cur;
    for (final o in ufos) {
      if (o.spec.id == id || !o.inGrid || !o.spawned) continue;
      if (sweepHit(m, o.cur) != null) return false;
    }
    return true;
  }

  // ---------------------------------------------------------- dönen UFO

  /// Dönen UFO'nun şu an özgün yönde mi olduğunu söyleyen döngü zamanı (0..on+off).
  double rotPhase(UfoState u) {
    final cyc = level.rules.rotorOn + level.rules.rotorOff;
    return (clock + u.rotOffset) % cyc;
  }

  /// Bir sonraki yön değişimine kalan süre (sn).
  double rotTimeLeft(UfoState u) {
    final ph = rotPhase(u);
    return ph < level.rules.rotorOn ? level.rules.rotorOn - ph : level.rules.rotorOn + level.rules.rotorOff - ph;
  }

  void _updateRotors() {
    if (level.rules.rotors.isEmpty) return;
    for (final u in ufos) {
      if (!u.rotor) continue;
      final f = rotPhase(u) >= level.rules.rotorOn;
      if (f != u.flipped) {
        u.flipped = f;
        u.cur = f ? u.flip : u.spec;
        u.flipClock = clock;
        rotVersion++;
      }
    }
  }

  // ---------------------------------------------------------- zaman

  /// Oyunu dt saniye ilerletir, bu sürede olan binişleri döndürür.
  List<BoardEvent> step(double dt) {
    final ev = <BoardEvent>[];
    double left = dt;
    while (left > 1e-9) {
      final h = left > 0.02 ? 0.02 : left;
      left -= h;
      _advance(h, ev);
    }
    return ev;
  }

  void _advance(double h, List<BoardEvent> ev) {
    clock += h;
    _updateRotors();
    final mul = introActive ? kIntroMul : 1.0;
    final dp = speed * mul * h;
    final p0 = phase;
    phase += dp;
    final n = slots.length;

    // Kapılar: yolcu hücresi kapıdan bu adımda geçtiyse ve UFO uygunsa biner.
    for (int g = 0; g < n; g++) {
      final uid = slots[g];
      if (uid < 0 || clock < slotReady[g]) continue;
      final u = ufos[uid];
      if (u.departed) continue; // dolmuş, kalkış bekliyor: yolcu almaz
      final gs = gateS(g, n);
      for (int i = 0; i < cells.length; i++) {
        final p = cells[i];
        if (p == null) continue;
        if (u.boarded >= u.spec.seats) break;
        if (p.color != u.spec.color) continue;
        final d = fracS(gs - fracS(p0 - cellOffset(i, ringCols)));
        if (d > 0 && d <= dp) {
          cells[i] = null;
          occupied--;
          u.boarded++;
          boardedTotal++;
          ev.add(BoardEvent(uid, p.id, p.color, i, g));
        }
      }
      if (u.boarded >= u.spec.seats) {
        // Yuva, UFO duraktan gerçekten ayrılana kadar dolu kalır (releaseSlot).
        u.departed = true;
      }
    }

    // Giriş: iki kol bağımsız beslenir; boş hücre bir kolun giriş noktasından geçerken o kolun
    // sıradaki yolcusu halkaya girer (halkada en fazla ringCap yolcu).
    if (qHead < level.totalPassengers && occupied < level.ringCap) {
      for (int i = 0; i < cells.length; i++) {
        if (cells[i] != null) continue;
        if (occupied >= level.ringCap) break;
        final off = fracS(p0 - cellOffset(i, ringCols));
        for (int a = 0; a < 2; a++) {
          if (armHead[a] >= armQ[a].length) continue;
          final es = a == 0 ? entryL : entryR;
          final d = fracS(es - off);
          if (d > 0 && d <= dp) {
            cells[i] = Passenger(armId(a, armHead[a]), armQ[a][armHead[a]]);
            armHead[a]++;
            occupied++;
            break;
          }
        }
      }
    }
  }

  // ---------------------------------------------------------- bitiş

  bool get won => occupied == 0 && qHead >= level.totalPassengers;

  /// Park yerleri dolu ve hiçbir park yerindeki UFO'ya binecek yolcu halkada
  /// (ya da halkaya girecek sıradakiler arasında) yok.
  bool get stuck {
    if (freeSlot() >= 0) return false;
    for (final id in slots) {
      if (id >= 0 && ufos[id].departed) return false; // kalkmakta olan UFO yuvayı boşaltacak
    }
    final need = <int>{};
    for (final id in slots) {
      if (id < 0) continue;
      final u = ufos[id];
      if (u.boarded < u.spec.seats) need.add(u.spec.color);
    }
    for (final p in cells) {
      if (p != null && need.contains(p.color)) return false;
    }
    // Halkaya girecek sıradakiler: kollardan dönüşümlü, boş yer kadar.
    int e = level.ringCap - occupied;
    final rem = level.totalPassengers - qHead;
    if (rem < e) e = rem;
    final h = [armHead[0], armHead[1]];
    int arm = 0;
    for (int j = 0; j < e; j++) {
      if (h[arm] >= armQ[arm].length) arm = 1 - arm;
      if (h[arm] >= armQ[arm].length) break;
      if (need.contains(armQ[arm][h[arm]])) return false;
      h[arm]++;
      arm = 1 - arm;
    }
    return true;
  }

  bool get lost => !won && (outOfMoves || stuck);

  // ---------------------------------------------------------- booster'lar

  /// Dolan UFO duraktan ayrıldığında arayüz çağırır: yuva boşalır, yeni UFO çağrılabilir.
  void releaseSlot(int uid) {
    for (int i = 0; i < slots.length; i++) {
      if (slots[i] == uid && ufos[uid].departed) slots[i] = -1;
    }
  }

  /// Duraktan ayrılmayı bekleyen (dolmuş ama yuvada duran) UFO var mı?
  bool get hasDeparting {
    for (final id in slots) {
      if (id >= 0 && ufos[id].departed) return true;
    }
    return false;
  }

  void addSlots(int n) {
    for (int i = 0; i < n; i++) {
      slots.add(-1);
      slotReady.add(0.0);
    }
  }

  /// Kilitli bir yuvayı açar (reklam izlendikten sonra çağrılır). Kilitli yuva kalmadıysa false.
  bool unlockSlot() {
    if (lockedSlots <= 0) return false;
    lockedSlots--;
    addSlots(1);
    return true;
  }

  /// n yuva verir: önce kilitli yuvaları açar, kalan olursa ekstra yuva ekler (revive / booster).
  void grantSlots(int n) {
    for (int i = 0; i < n; i++) {
      if (!unlockSlot()) addSlots(1);
    }
  }

  /// "Hemen Bin": inmiş park yerlerindeki UFO'lar halkadaki kendi renklerini
  /// konumlarına bakmadan hemen alır (referanstaki Direct Boarding).
  List<BoardEvent> directBoard() {
    final ev = <BoardEvent>[];
    for (int g = 0; g < slots.length; g++) {
      final uid = slots[g];
      if (uid < 0 || clock < slotReady[g]) continue;
      final u = ufos[uid];
      if (u.departed) continue;
      for (int i = 0; i < cells.length && u.boarded < u.spec.seats; i++) {
        final p = cells[i];
        if (p == null || p.color != u.spec.color) continue;
        cells[i] = null;
        occupied--;
        u.boarded++;
        boardedTotal++;
        ev.add(BoardEvent(uid, p.id, p.color, i, g));
      }
      if (u.boarded >= u.spec.seats) {
        u.departed = true;
      }
    }
    return ev;
  }

  /// Kollarda bekleyen yolcuların renk sırasını karıştırır (kol uzunlukları aynı kalır).
  /// Katmanlı düzende 1. katmanın yolcuları ile 2. katmanınkiler ayrı havuzlarda karışır (sınırı geçmez):
  /// böylece yolcu sırası katman sırasıyla uyumlu kalır ve seviye çözülebilir olmaya devam eder.
  void shuffleQueue(int seed) {
    int s = (seed * 2654435761) % 4294967296;
    final cut = level.armCut;
    final phases = cut.isEmpty ? 1 : 2;
    for (int ph = 0; ph < phases; ph++) {
      final pos = <List<int>>[];
      for (int a = 0; a < 2; a++) {
        int lo = armHead[a];
        int hi = armQ[a].length;
        if (cut.isNotEmpty) {
          if (ph == 0) {
            hi = min(hi, cut[a]);
          } else {
            lo = max(lo, cut[a]);
          }
        }
        for (int m = lo; m < hi; m++) {
          pos.add(<int>[a, m]);
        }
      }
      final vals = <int>[for (final q in pos) armQ[q[0]][q[1]]];
      for (int i = vals.length - 1; i > 0; i--) {
        s = (s * 1664525 + 1013904223) % 4294967296;
        final j = s % (i + 1);
        final t = vals[i];
        vals[i] = vals[j];
        vals[j] = t;
      }
      for (int i = 0; i < pos.length; i++) {
        armQ[pos[i][0]][pos[i][1]] = vals[i];
      }
    }
  }
}
