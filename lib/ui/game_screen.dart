import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ads.dart';
import '../audio.dart';
import '../game/engine.dart';
import '../game/geometry.dart';
import '../game/level_repo.dart';
import '../game/models.dart';
import '../l10n.dart';
import '../progress.dart';
import '../stats.dart';
import '../settings.dart';
import 'game_popup.dart';
import 'tutorial.dart';
import 'win_overlay.dart';
import 'ring_shapes.dart';

/// Renk sırası: level_data'daki color indeksi bu listeye karşılık gelir.
const List<String> kColorNames = [
  'red',
  'blue',
  'green',
  'yellow',
  'purple',
  'orange',
  'pink',
  'lightblue',
  // Referanstaki 9-15. renkler (v0.5: kırmızı sprite'tan boyandı).
  'white',
  'black',
  'brown',
  'lime',
  'teal',
  'maroon',
  'navy',
];

const List<Color> kColors = [
  Color(0xFFE53935),
  Color(0xFF3F6FFF),
  Color(0xFF43C443),
  Color(0xFFFFD600),
  Color(0xFF9C4DFF),
  Color(0xFFFF8F00),
  Color(0xFFFF6FB0),
  Color(0xFF5CC8FF),
  Color(0xFFF2F2F2), // beyaz
  Color(0xFF787878), // siyah (UFO/yolcu ile aynı nötr gri)
  Color(0xFF8D5A3C), // kahverengi
  Color(0xFFB4E33D), // limon yeşili
  Color(0xFF26C6A6), // turkuaz
  Color(0xFF9B1C1C), // bordo
  Color(0xFF283593), // lacivert
];

/// Koltuk sayısına göre UFO görseli: ufo4_* / ufo6_* / ufo10_* (koltuk sınıfıyla birebir).
int _ufoClass(int seats) => seats >= 10 ? 10 : (seats >= 6 ? 6 : 4);

/// Dönüş efektinin görünürlüğü: ilk ve son %14'te yumuşakça belirir / söner (ani belirme yok).
double _spinFade(double f) {
  final a = (f / 0.14).clamp(0.0, 1.0);
  final b = ((1.0 - f) / 0.14).clamp(0.0, 1.0);
  final m = min(a, b);
  return m * m * (3 - 2 * m);
}

double _seatScale(int seats) => seats >= 10 ? 1.0 : (seats >= 6 ? 0.9 : 0.8);

const double _armGap = 19.0; // kollarda sıra aralığı (1 sıra = yan yana 3 yolcu birimi)
const int _armLanes = 3; // kolun genişliği (yolcu birimi sayısı)
const int _armRows = 40; // kolda görünebilecek en fazla sıra (gerçek sınır kol uzunluğu)
const double _armLaneGap = 11.5;
const int _kernels = 2; // bir yolcu birimi ekranda yan yana/ardışık bu kadar mısır tanesi gibi küçük uzaylı çizilir
const double _kernelSize = 13.0; // küçük uzaylının çizim boyu (px)
/// Sayaç saniyede kaç birim düşer: 1'er 1'er (40, 39, 38 ...) sayar. Bir yolcu 4 birim = 4 hızlı adım.
const double _counterTickPerSec = 40.0;
const double _counterH = 8.0; // park yerinin altında sayaç için AYRILAN yükseklik (sayaç kutusu pad'in alt kenarına biner)
const double _counterBox = 18.0; // sayaç kutusunun kendi yüksekliği
const double _gridUfoScale = 1.0; // v0.16.4: gövde artık disk çapı kadar (ufoDiameter), çizim 1:1; eskiden 1.4 idi ve ince şerit gövdelerle diskler üst üste biniyordu
const double _minTap = 34.0;

/// Sahadaki UFO'ları, dizilimi (konumları) bozmadan, üst üste binmeyecek en büyük ölçeğe kadar büyütülen
/// düzenler (stage anahtarı). 1010 = 10. seviye. Ölçek ekran boyutuna göre çalışma anında hesaplanır.
const double _growMax = 2.0; // v0.16.10: en fazla bu kadar büyür (eskiden 1.6; seyrek kalan UFO daha çok büyür, ızgara dolu görünür)
const double _growGap = 0.05; // komşu UFO'lar arasında kalacak boşluk payı (en yakın çiftte %5)
// Sprite'ların görünen kutusu (görsel dosyalarının alfa sınırlarından): en / boy oranı (çizim boyuna göre).
double _spriteW(int seats) => 0.97;
double _spriteH(int seats) => seats >= 10 ? 0.82 : (seats >= 6 ? 0.62 : 0.65);

/// Kamera uzaklaşması: kalabalık seviyelerde (birim alana düşen UFO sayısı yüksek) sahne uzaklaşır.
/// UFO çizim ölçeği ve üstteki halka/kol/park yeri bölümü aynı oranda küçülür, UFO tahtası büyür.
const double _camDensLo = 0.8; // bu yoğunluğa kadar zoom 1.0 (eskisi gibi)
const double _camDensHi = 1.4; // bu yoğunlukta en uzak
const double _targetUnit = 46.0; // sahadaki UFO birimi (px) bundan küçük kalıyorsa halka bölümü küçülür (_fitRingZoom)
const double _camMin = 0.72; // en uzak zoom (halka %72 boyuta iner)
const double _camMinLayered = 0.88; // katmanlı düzende en uzak zoom (her katmanda UFO sayısı az: halka daha az küçülür)

double _camZoomFor(LevelData lv) {
  if (lv.layerCount > 1) {
    // Katmanlı düzen: katmanlar birbirinin yerine geçtiği için en yoğun katmana göre TEK zoom (katman değişince halka
    // boyutu zıplamasın). Her katmanda UFO sayısı yarıya yakın olduğu için en uzak zoom daha az uzaklaşır.
    double dens = 0;
    for (int l = 0; l < lv.layerCount; l++) {
      final b = lv.boundsOf(l);
      dens = max(dens, lv.layerSize(l) / ((b[2] - b[0]) * (b[3] - b[1])));
    }
    final t = ((dens - _camDensLo) / (_camDensHi - _camDensLo)).clamp(0.0, 1.0);
    return 1.0 - t * (1.0 - _camMinLayered);
  }
  final dens = lv.ufos.length / (lv.boardW * lv.boardH);
  final t = ((dens - _camDensLo) / (_camDensHi - _camDensLo)).clamp(0.0, 1.0);
  return 1.0 - t * (1.0 - _camMin);
} // küçük UFO'lar için en küçük dokunma alanı

const int _landMs = 2200; // UFO'nun park yerine uçuş süresi (kLandSec ile aynı); uçarken 1 tur topaç gibi döner
const int _departMs = 2800; // dolan UFO'nun dönerek sağdan çıkış süresi (2 tur)
const double _departRise = 1.0; // çıkışta önce yükselme miktarı (UFO boyu kadar)
const double _departSplit = 0.30; // çıkış süresinin ilk kısmı yükselme, kalanı sağa uçuş
const int _slotFreeMs = 2000; // UFO havalandıktan bu kadar sonra (duraktan ayrılmış sayılır) yuva boşalır, yenisi çağrılabilir
const int _departWaitMs = 500; // son yolcu bindikten sonra UFO'nun havalanmadan önce bekleme süresi
const int _beamMs = 1400; // Işınla: UFO'nun VIP yuvaya ışınlanma süresi (kBeamSec ile aynı)
const int _bumpMs = 380; // kapalı UFO'nun çarpıp geri dönme süresi
const int _flyMs = 1000; // tek yolcunun kapıdan yuvaya yürüyüp oradan UFO'ya ışınlanma süresi
const double _walkFrac = 0.62; // _flyMs'in ilk yarısı: yolcu yuvaya iner; ikinci yarısı: ışınla yukarı UFO'ya çıkar

/// Gizemli UFO: renkleri koyulaştırır (neredeyse siyah, gölgeleme korunur).
const ColorFilter _mysteryFilter = ColorFilter.matrix(<double>[
  0.16, 0.16, 0.16, 0, 8, //
  0.16, 0.16, 0.16, 0, 8, //
  0.17, 0.17, 0.17, 0, 14, //
  0, 0, 0, 1, 0, //
]);

/// Booster açılış seviyeleri (referans oyunla aynı: Board 2, Refresh 3, Remove/VIP 5).
const int _unlockBoard = 2;
const int _unlockShuffle = 3;
const int _unlockVip = kVipUnlockLevel;

/// Işınlanan tek bir yolcu (animasyon kaydı).
class _Fly {
  final int id;
  final int ufo;
  final int color;
  final double fx; // başlangıç: halkadaki hücre
  final double fy;
  final double px; // yuvanın üstünde duracağı nokta (ışının indiği yer)
  final double py;
  final double tx; // hedef: havada duran UFO'nun alt kenarı
  final double ty;

  _Fly(this.id, this.ufo, this.color, this.fx, this.fy, this.px, this.py, this.tx, this.ty);
}

/// Kapalı UFO'nun çarpma animasyonu: başlangıç anı ve engele olan mesafe (tahta birimi).
class _Bump {
  final int startMs;
  final double dist;
  const _Bump(this.startMs, this.dist);
}

/// Yol üzerindeki nokta ve dış normali.
class _Pt {
  final double x;
  final double y;
  final double nx;
  final double ny;
  final double gap; // bu noktada şeritler arası mesafe (ekran px)
  const _Pt(this.x, this.y, this.nx, this.ny, [this.gap = 0]);
}

/// Ekran yerleşimi (koddaki tüm konumlar buradan hesaplanır).
class _G {
  List<double> growOf = const <double>[]; // her UFO'nun ek büyütme çarpanı (komşuya/panel kenarına değmeden)
  double W = 0;
  double H = 0;
  double hudH = 56;
  double hintH = 0;
  double topInset = 0; // durum çubuğu payı: sadece başlık/ipucu bunun altına iner, oyun alanı ekranın en üstünden başlar
  double armsH = 78; // halkanın üstündeki kol alanı yüksekliği (uzun U biçimli kollar)
  double armTop = 0;
  double armWait = 0; // kolda bekleme sırasının başı: girişten bu kadar uzakta (yolun dışında)
  double ringTop = 0;
  double ringH = 0;
  double cx = 0;
  double cy = 0;
  double L = 0; // alt/üst düz kenarın yarı uzunluğu
  double r = 0; // uç yarım dairelerin yarıçapı
  double perim = 1;
  double entryL = 0.375;
  double entryR = 0.625;
  Offset entryPtL = Offset.zero;
  Offset entryPtR = Offset.zero;
  List<List<Offset>> arms = <List<Offset>>[];
  List<List<double>> armCum = <List<double>>[];
  double alien = 0;
  double roadW = 0;
  late RingShape shape;
  double sc = 1; // görsel px -> ekran px
  double imgLeft = 0;
  double imgTop = 0;
  List<Offset> ringPts = <Offset>[];
  List<double> ringCum = <double>[];
  List<double> ringGap = <double>[];
  double ringLen = 1;
  double k = 1.0; // kamera zoom (1: yakın, küçüldükçe uzak): halka/kol/park yeri bu oranda küçülür
  double ufoScale = _gridUfoScale; // sahadaki UFO çizim ölçeği (zoom ile azalır)
  double slotSize = 0;
  double slotsH = 0;
  double slotsTop = 0;
  double hoverH = 0; // yuvanın üstünde havada duran UFO'ya ayrılan yükseklik
  double get padTop => slotsTop + hoverH; // yuva (pad) görselinin üst kenarı
  double slotsLeft = 0;
  double gridLeft = 0;
  double gridTop = 0;
  double gridW = 0;
  double gridH = 0;
  double panelLeft = 0; // zemin panelinin (sabit) konumu ve boyutu
  double panelTop = 0;
  double panelW = 0;
  double panelH = 0;
  double unit = 0; // 1 tahta birimi kaç piksel (dikey ve UFO boyutu)
  double unitX = 0; // yatay aralık: tahta yanlara genişler, UFO boyutu değişmez
  double bMinX = 0; // şu an görünen katmanın sınırları (tahta birimi)
  double bMinY = 0;
  double bW = 1;
  double bH = 1;
  double boostH = 78;
  int slotCount = 0;
}

/// Şekil dosyasındaki halka yolu (ring_shapes.dart). s = 0: kapı (alt orta), yolcular SOLA akar (saat yönü).
/// Nokta ve dış normal döner; gap = o noktada şeritler arası mesafe.
_Pt _pathAt(_G g, double s) {
  final d = fracS(s) * g.ringLen;
  final cum = g.ringCum;
  int lo = 0;
  int hi = cum.length - 1;
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (cum[mid] <= d) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final a = g.ringPts[lo];
  final b = g.ringPts[(lo + 1) % g.ringPts.length];
  final seg = cum[lo + 1] - cum[lo];
  final t = seg <= 0 ? 0.0 : ((d - cum[lo]) / seg).clamp(0.0, 1.0);
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final len = sqrt(dx * dx + dy * dy);
  final hx = len == 0 ? -1.0 : dx / len;
  final hy = len == 0 ? 0.0 : dy / len;
  final ga = g.ringGap[lo];
  final gb = g.ringGap[(lo + 1) % g.ringGap.length];
  // Dış normal (saat yönünde akışta): (hy, -hx).
  return _Pt(a.dx + dx * t, a.dy + dy * t, hy, -hx, ga + (gb - ga) * t);
}

Offset _ringPoint(_G g, double s, double off) {
  final p = _pathAt(g, s);
  return Offset(p.x + p.nx * off, p.y + p.ny * off);
}

class GameScreen extends StatefulWidget {
  final int level;
  const GameScreen({super.key, required this.level});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late LevelData level;
  late GameState game;
  late AnimationController _clock;
  final Set<int> bouncing = <int>{};
  final Map<int, int> pending = <int, int>{};
  final Set<int> landed = <int>{};
  final Map<int, int> spinStart = <int, int>{}; // kalkış (park yerine) dönüşünün başlangıcı
  final Map<int, int> departStart = <int, int>{}; // çıkış uçuşunun başlangıcı
  final Set<int> _fullChimed = <int>{}; // dolma sesi çalınan UFO'lar
  final Map<int, int> lastBoard = <int, int>{}; // ufo id -> son biniş (ms)
  final Map<int, int> gateFlash = <int, int>{}; // kapı -> son biniş (ms)
  final Map<int, int> birth = <int, int>{}; // yolcu id -> ilk görülme (ms)
  final Map<int, _Bump> bumps = <int, _Bump>{}; // ufo id -> çarpma animasyonu
  final Set<int> beaming = <int>{}; // ışınlanan UFO'lar (Işınla)
  final Map<int, Offset> beamFrom = <int, Offset>{}; // ışınlama başlangıç noktası
  final List<_Fly> flies = <_Fly>[];
  final List<double> _armVis = <double>[0.0, 0.0]; // kollardaki görsel sıra başı (yumuşakça yaklaşır)
  int _lastTick = 0;
  int _flyId = 0;
  double _lastW = 390;
  double _lastH = 700;
  double _lastTop = 0;
  String? message;
  int _msgToken = 0;
  bool ended = false;
  bool revived = false;
  bool vipArmed = false; // Kaldır seçildi: bir sonraki UFO dokunuşu VIP yuvaya taşır
  int _newBoost = -1; // yeni açılan booster (düğme parıldar), -1: yok
  bool _popupOpen = false; // "Yeni açıldı" penceresi açıkken oyun durur
  bool _breakOpen = false; // arızalı UFO tamir penceresi akışı sürüyor
  int _lastRot = 0; // dönen UFO yön değişimlerini izler
  int _lastLayerEv = 0; // katman asansörü olaylarını izler
  int _lastFaultEv = 0; // arızalı UFO bozulma / geri gelme olaylarını izler
  int _layerFlashMs = -100000; // asansör parıltısının başlangıcı
  final Set<int> _seenSpawned = <int>{}; // sahaya çıkmış UFO'lar (yeni belirenler için kapı parıltısı)
  final Map<int, int> portalFlash = <int, int>{}; // grup -> son belirme (ms)

  // ---- Öğretici durumu
  final GlobalKey _boardKey = GlobalKey();
  final List<GlobalKey> _boostKeys = List<GlobalKey>.generate(3, (_) => GlobalKey());
  final List<String> _tutQueue = <String>[]; // sıradaki öğretici bölümleri
  TutGuide? _tut; // şu an oynayan bölüm
  int _tutIdx = 0;
  int _tutStepMs = 0;
  bool _tutHold = false; // dokunuş sonrası kısa bekleme (animasyon görünsün)
  int? _tutUfo; // şu adımın hedef UFO'su
  int? _tutMem; // adımlar arası hatırlanan UFO (dokunulan / engellenen)
  bool _tutBoarded = false; // oyunda ilk biniş oldu mu
  final Map<int, ui.Image> _alienImgs = <int, ui.Image>{}; // yolcu sprite'ları (tek CustomPaint ile hızlı çizim)
  bool _tutFlag = false; // etkileşimli adımlar arası işaret
  int _tutMark = 0;
  bool _tutShown = false; // şu anki bölümde en az bir adım gerçekten gösterildi mi
  final Map<int, double> _cnt = <int, double>{}; // ufo id -> ekranda görünen sayaç (yumuşak, 1'er düşer)

  @override
  void initState() {
    super.initState();
    Audio.music(MusicTrack.game);
    _clock = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(_tick)
      ..repeat();
    _lastTick = DateTime.now().millisecondsSinceEpoch;
    _load(widget.level);
    _loadAliens();
  }

  Future<void> _loadAliens() async {
    for (int c = 0; c < kColorNames.length; c++) {
      try {
        final data = await rootBundle.load('assets/img/alien_${kColorNames[c]}.webp');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: 72);
        final fr = await codec.getNextFrame();
        if (!mounted) return;
        _alienImgs[c] = fr.image;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final im in _alienImgs.values) {
      im.dispose();
    }
    _alienImgs.clear();
    _clock.dispose();
    Audio.music(MusicTrack.menu);
    super.dispose();
  }

  void _load(int n) {
    Stats.levelStart(n);
    level = LevelRepo.get(n);
    game = GameState(level);
    bouncing.clear();
    pending.clear();
    landed.clear();
    spinStart.clear();
    departStart.clear();
    _fullChimed.clear();
    lastBoard.clear();
    gateFlash.clear();
    birth.clear();
    flies.clear();
    _armVis[0] = 0.0;
    _armVis[1] = 0.0;
    ended = false;
    revived = false;
    vipArmed = false;
    bumps.clear();
    beaming.clear();
    beamFrom.clear();
    message = null;
    _cnt.clear();
    _lastRot = game.rotVersion;
    _lastLayerEv = game.layerEvents;
    _lastFaultEv = game.faultEvents;
    _layerFlashMs = -100000;
    _breakOpen = false;
    portalFlash.clear();
    _seenSpawned
      ..clear()
      ..addAll(<int>[for (final u in game.ufos) if (u.spawned) u.spec.id]);
    _tutInit(n);
    _maybeUnlockPopup(n);
    final g0 = _geom(_lastW, _lastH);
    game.entryL = g0.entryL;
    game.entryR = g0.entryR;
    Audio.play(Sfx.levelStart);
  }

  /// Üst bilgi altındaki özel kural özeti (hamle bütçesi).
  String _rulesLine() {
    final p = <String>[];
    if (level.rules.moveBudget > 0) p.add(L.t('👆 Hamle ${game.movesLeft}', '👆 Moves ${game.movesLeft}'));
    if (level.layerCount > 1) p.add(L.t('⬆ Kat ${game.curLayer + 1}/${level.layerCount}', '⬆ Floor ${game.curLayer + 1}/${level.layerCount}'));
    if (level.rules.rotors.isNotEmpty) p.add('🔄 ${level.rules.rotors.length}');
    if (level.rules.faulty.isNotEmpty) p.add('🔧 ${level.rules.faulty.length}');
    if (level.rules.belts.isNotEmpty) p.add('⇆ ${level.rules.belts.length}');
    return p.join('   ');
  }

  void _flash(String m) {
    final token = ++_msgToken;
    setState(() => message = m);
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted && token == _msgToken) setState(() => message = null);
    });
  }

  // ------------------------------------------------------------ zaman

  void _tick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    double dt = (now - _lastTick) / 1000.0;
    if (dt > 0.1) dt = 0.1;
    if (dt < 0) dt = 0;
    _lastTick = now;

    final k = min(1.0, dt * 8.0);
    for (int a = 0; a < 2; a++) {
      _armVis[a] += (_armTaken(a) - _armVis[a]) * k;
    }

    // Park yeri sayacı: hedefe doğru tek tek düşer.
    for (final u in game.ufos) {
      final id = u.spec.id;
      if (u.inGrid || !landed.contains(id)) continue;
      final pend = pending[id] ?? 0;
      final target = (max(0, u.spec.seats - max(0, u.boarded - pend)) * kCapPerPassenger).toDouble();
      final cur = _cnt[id] ?? u.spec.capacity.toDouble();
      _cnt[id] = cur > target ? max(target, cur - dt * _counterTickPerSec) : target;
    }
    _tutWatch();
    if (ended || _popupOpen || _tutPausesGame) return;
    final g = _geom(_lastW, _lastH);
    game.entryL = g.entryL;
    game.entryR = g.entryR;
    final ev = game.step(dt);
    if (ev.isNotEmpty) _handleBoard(ev);
    // Dolan UFO duraktan ayrılınca yuvası boşalır.
    if (game.hasDeparting) {
      bool freed = false;
      for (final id in List<int>.from(game.slots)) {
        if (id < 0 || !game.ufos[id].departed) continue;
        final ds = departStart[id];
        if (ds != null && now - ds >= _slotFreeMs) {
          game.releaseSlot(id);
          freed = true;
        }
      }
      if (freed && mounted) setState(() {});
    }
    _trackSpawns(now);
    if (game.rotVersion != _lastRot) {
      // Dönen UFO yön değiştirdi: UFO katmanını yeniden çiz (ok, kapalı/açık durumu).
      _lastRot = game.rotVersion;
      if (mounted) setState(() {});
    }
    if (game.layerEvents != _lastLayerEv) {
      // Katman asansörü: alt kat yukarı çıktı.
      _lastLayerEv = game.layerEvents;
      if (Settings.screenFx) _layerFlashMs = now;
      Settings.vibe(HapticFeedback.mediumImpact);
      if (mounted) setState(() {});
      Audio.play(Sfx.layerUp);
      _flash(L.t('⬆ ${game.curLayer + 1}. kat yükseldi!', '⬆ Floor ${game.curLayer + 1} unlocked!'));
    }
    if (game.faultEvents != _lastFaultEv) {
      _lastFaultEv = game.faultEvents;
      if (mounted) setState(() {});
    }
    _checkEnd();
  }

  /// Yeni belirmiş UFO'lar: gruptaki (ışınlama kapısı) UFO'lar için kapı parıltısı başlatır.
  void _trackSpawns(int now) {
    for (final u in game.ufos) {
      if (!u.spawned || !u.inGrid) continue;
      if (_seenSpawned.add(u.spec.id) && u.spec.group >= 0) {
        Audio.play(Sfx.portalSpawn);
        if (Settings.screenFx) portalFlash[u.spec.group] = now;
      }
    }
  }

  /// Arızalı UFO'nun sayacı 0'a inince: tamir (ödüllü reklam, şimdilik demo) ya da bırak.
  Future<void> _handleBreaks() async {
    if (_breakOpen) return;
    _breakOpen = true;
    while (mounted && !ended && game.breakQueue.isNotEmpty) {
      final id = game.breakQueue.first;
      Audio.play(Sfx.ufoBreak);
      setState(() => _popupOpen = true);
      final repair = await showGamePopup<bool>(
        context,
        emoji: '🔧',
        title: L.t('UFO bozuldu!', 'UFO broke down!'),
        message: L.t(
          'Sayacı 0\'a indi. Reklam izleyip tamir edersen sahada kalır. '
              'Vazgeçersen bozulup gider, birkaç hamle sonra aynı yerine geri gelir.',
          'Its counter hit 0. Watch an ad to repair it and it stays on the field. '
              'If you give up, it breaks down and leaves, then comes back to the same spot after a few moves.',
        ),
        accent: const Color(0xFFFF9800),
        buttons: [
          PopupBtn<bool>(L.t('Vazgeç', 'Cancel'), kind: PopupKind.ghost, value: false),
          PopupBtn<bool>(L.t('İzle', 'Watch'), icon: Icons.play_arrow_rounded, kind: PopupKind.reward, value: true),
        ],
      );
      if (!mounted) break;
      final watched = repair == true && await Ads.play(context);
      if (!mounted) break;
      setState(() {
        _popupOpen = false;
        if (watched) {
          game.repairUfo(id);
        } else {
          game.breakUfo(id);
        }
      });
      if (watched) Audio.play(Sfx.ufoRepair);
      _flash(watched ? L.t('🔧 Tamir edildi', '🔧 Repaired') : L.t('UFO bozulup gitti', 'The UFO broke down and left'));
    }
    _breakOpen = false;
  }

  /// Halka hücresinin ekran konumu.
  Offset _cellPoint(_G g, int i) {
    final p = _pathAt(g, game.cellS(i));
    final off = ((i % kRingLanes) - (kRingLanes - 1) / 2) * p.gap;
    return Offset(p.x + p.nx * off, p.y + p.ny * off);
  }

  /// a. koldan (0: sol, 1: sağ) çıkan yolcu sayısı. Çift sıralı yolcular sol, tek sıralılar sağ koldan girer.
  int _armTaken(int a) => game.armHead[a];

  /// Kol üzerinde, girişten q uzaklıkta (girişe doğru sıra başı), şerit kaymasıyla nokta.
  Offset _armPoint(_G g, int arm, double q, double off) {
    final pts = g.arms[arm];
    final cum = g.armCum[arm];
    int i = 1;
    while (i < pts.length - 1 && cum[i] < q) {
      i++;
    }
    final a = pts[i - 1];
    final b = pts[i];
    final segLen = cum[i] - cum[i - 1];
    final t = segLen <= 0 ? 0.0 : (q - cum[i - 1]) / segLen;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = sqrt(dx * dx + dy * dy);
    final ux = len == 0 ? 0.0 : dx / len;
    final uy = len == 0 ? -1.0 : dy / len;
    return Offset(a.dx + dx * t - uy * off, a.dy + dy * t + ux * off);
  }

  // ------------------------------------------------------------ yerleşim

  /// Tahta YÜKSEKLİKTEN dolayı küçülüyorsa (UFO birimi _targetUnit'ten küçükse) halka + kollar + park yeri
  /// bölümünü kademeli küçültür (en fazla _camMin'e kadar); UFO'lara ayrılan alan büyür. Tahta genişlikten
  /// sınırlıysa halkayı küçültmek UFO'yu büyütmez, o zaman halka olduğu gibi kalır. Katmanlı düzenlerde tek zoom
  /// bütün katmanlara bakar (katman değişince zıplamasın).
  double _fitRingZoom(double W, double H, double kMax, double boostH) {
    final lv = game.level;
    final sh = ringShapeFor(lv.stage);
    final slotCount = game.slots.length + game.lockedSlots;
    final bounds = <List<double>>[for (int l = 0; l < lv.layerCount; l++) lv.boundsOf(l)];
    double k = kMax;
    while (true) {
      final sc = min((W - 6) / sh.fitW, 0.42) * k;
      final ringH = sh.contentH * sc;
      final slotSize = min(72.0, (W - 16) / slotCount) * k;
      final hoverH = max(36.0 * k, slotSize * 0.8);
      final areaTop = ringH + 2 + hoverH + slotSize + _counterH + 2;
      final areaH = max(120.0, H - areaTop - boostH - 4);
      bool need = false;
      for (final b in bounds) {
        final wl = (W - 28) / (b[2] - b[0]);
        final hl = areaH / (b[3] - b[1]);
        final unit = max(14.0, min(min(wl, hl), 64.0));
        if (hl < wl && unit < _targetUnit) need = true; // yükseklik sınırlı ve küçük
      }
      if (!need || k <= _camMin + 1e-6) return max(k, min(kMax, _camMin));
      k -= 0.02;
    }
  }

  _G _geom(double W, double H) {
    final g = _G();
    g.W = W;
    g.H = H;
    g.hintH = 0.0; // ipucu yazısı kaldırıldı
    g.topInset = _lastTop;
    // Kollar + halka + park yerleri ekranın EN ÜSTÜNDEN başlar; başlık ve ipucu bunların üstüne biner.
    g.armTop = 0;
    // Halka + kollar hazır görselden (referans gibi seviyeye göre şekil). Görsel genişliği ekrana sığar,
    // yolcu yolu görseldeki yolun orta çizgisini izler.
    final sh = ringShapeFor(game.level.stage);
    g.shape = sh;
    // UFO çizim ölçeği yoğunluğa göre (eskisi gibi); halka/kollar/park yerleri ise UFO'lar çok küçük kalmasın diye
    // gerekirse daha da küçülür (v0.13.11): kalan dikey alan UFO tahtasına geçer, UFO'lar küçülmez.
    final kUfo = _camZoomFor(game.level);
    g.k = _fitRingZoom(W, H, kUfo, g.boostH);
    g.ufoScale = _gridUfoScale * kUfo;
    g.sc = min((W - 6) / sh.fitW, 0.42) * g.k;
    g.imgLeft = W / 2 - sh.centerX * g.sc;
    g.imgTop = g.armTop;
    Offset tp(List<double> p) => Offset(g.imgLeft + p[0] * g.sc, g.imgTop + p[1] * g.sc);
    g.ringPts = [for (final p in sh.ring) tp(p)];
    g.ringCum = <double>[0.0];
    for (int i = 0; i < g.ringPts.length; i++) {
      final a = g.ringPts[i];
      final b = g.ringPts[(i + 1) % g.ringPts.length];
      g.ringCum.add(g.ringCum.last + (b - a).distance);
    }
    g.ringLen = g.ringCum.last;
    g.ringGap = <double>[];
    for (int i = 0; i < g.ringPts.length; i++) {
      final a = g.ringPts[i];
      final b = g.ringPts[(i + 1) % g.ringPts.length];
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final len = sqrt(dx * dx + dy * dy);
      final nx = len == 0 ? 0.0 : dy / len;
      final ny = len == 0 ? 0.0 : -dx / len;
      final w = nx * nx;
      final vert = ny < 0 ? sh.gapTop : sh.gapBottom;
      g.ringGap.add((sh.gapSide * w + vert * (1 - w)) * g.sc);
    }
    double minY = 1e9, maxY = -1e9;
    for (final p in g.ringPts) {
      minY = min(minY, p.dy);
      maxY = max(maxY, p.dy);
    }
    g.cx = W / 2;
    g.cy = (minY + maxY) / 2;
    g.r = (maxY - minY) / 2;
    g.roadW = sh.trackW * g.sc;
    g.ringTop = g.armTop;
    g.ringH = sh.contentH * g.sc;
    // Girişler: kolların halka ile birleştiği noktalar (yolun en yakın köşesi).
    double sOf(List<double> j) {
      final q = tp(j);
      int best = 0;
      double bd = 1e18;
      for (int i = 0; i < g.ringPts.length; i++) {
        final d = (g.ringPts[i] - q).distanceSquared;
        if (d < bd) {
          bd = d;
          best = i;
        }
      }
      return g.ringCum[best] / g.ringLen;
    }

    g.entryL = sOf(sh.armL.first);
    g.entryR = sOf(sh.armR.first);
    g.armWait = g.roadW / 2 + 14 * g.k;
    g.entryPtL = _ringPoint(g, g.entryL, 0);
    g.entryPtR = _ringPoint(g, g.entryR, 0);
    // Kollar: şekildeki kol yolu (nokta 0 = halkaya giriş).
    g.arms = <List<Offset>>[];
    g.armCum = <List<double>>[];
    for (int a = 0; a < 2; a++) {
      final src = a == 0 ? sh.armL : sh.armR;
      final pts = <Offset>[for (final p in src) tp(p)];
      pts[0] = a == 0 ? g.entryPtL : g.entryPtR;
      final cum = <double>[0.0];
      for (int i = 1; i < pts.length; i++) {
        cum.add(cum.last + (pts[i] - pts[i - 1]).distance);
      }
      g.arms.add(pts);
      g.armCum.add(cum);
    }
    g.alien = 20.0 * g.k;
    g.slotCount = game.slots.length + game.lockedSlots; // açık + kilitli yuvalar yan yana
    g.slotSize = min(72.0, (W - 16) / g.slotCount) * g.k;
    // Park yerinin altında kalan kapasite sayacı için ekstra satır (counterH).
    g.hoverH = max(36.0 * g.k, g.slotSize * 0.8);
    g.slotsH = g.hoverH + g.slotSize + 10 + _counterH;
    g.slotsTop = g.ringTop + g.ringH + 2;
    g.slotsLeft = (W - g.slotSize * g.slotCount) / 2;
    // Zemin paneli sayaç satırının hemen altından başlar (boşluk küçüldü: UFO tahtası büyür).
    final gridAreaTop = g.slotsTop + g.hoverH + g.slotSize + _counterH + 2;
    final gridAreaH = max(120.0, H - gridAreaTop - g.boostH - 4);
    // Serbest konumlu tahta: bölümün sınırları (birim) ekrana sığacak şekilde ölçeklenir.
    // Katmanlı düzende kamera sadece şu an görünen katmana oturur (diğer katman asansörle gelince yeniden oturur).
    final lb = level.boundsOf(game.curLayer);
    final sbW = lb[2] - lb[0];
    final sbH = lb[3] - lb[1];
    // Panel (zemin) sabit: seviyenin tüm sınırına göre.
    final sUnit = max(
      14.0,
      min(min((W - 28) / sbW, gridAreaH / sbH), 64.0),
    );
    // Panel sağa-sola büyür: UFO aralıkları yatayda en fazla %30 açılır, UFO boyutu aynı kalır.
    // Katmanlı düzenler dar-uzun olduğu için yatayda ekran genişliğine kadar açılır (v0.13.6);
    // diğerlerinde en fazla %30.
    final maxStretch = game.level.layerCount > 1 ? 3.0 : 1.3;
    final sUnitX = max(sUnit, min((W - 28) / sbW, sUnit * maxStretch));
    g.panelW = sUnitX * sbW;
    g.panelH = sUnit * sbH;
    g.panelLeft = (W - g.panelW) / 2;
    g.panelTop = gridAreaTop + max(0.0, (gridAreaH - g.panelH) / 2);
    // İçerik: kalan UFO'lara göre yumuşak kamera, panelin içine sığar (UFO'lar iner/gider, panel yerinde kalır).
    final cb = lb; // kamera sabit: seviye sınırı (UFO'lar boşaldıkça büyümez)
    g.bMinX = cb[0];
    g.bMinY = cb[1];
    g.bW = max(0.5, cb[2] - cb[0]);
    g.bH = max(0.5, cb[3] - cb[1]);
    g.unit = max(sUnit, min(min(g.panelW / g.bW, g.panelH / g.bH), 64.0));
    g.unitX = max(g.unit, min(g.panelW / g.bW, g.unit * maxStretch));
    g.gridW = g.unitX * g.bW;
    g.gridH = g.unit * g.bH;
    g.gridLeft = g.panelLeft + (g.panelW - g.gridW) / 2;
    g.gridTop = g.panelTop + (g.panelH - g.gridH) / 2;
    final gk = '${game.level.number}|${g.unit.toStringAsFixed(2)}|${g.unitX.toStringAsFixed(2)}|${g.ufoScale.toStringAsFixed(3)}';
    if (gk != _growKey) {
      _growKey = gk;
      _growVal = _computeGrow(g);
    }
    g.growOf = _growVal;
    return g;
  }

  String _growKey = '';
  List<double> _growVal = const <double>[];

  /// Her UFO'yu, konumunu değiştirmeden, kendi komşularına ve panel kenarına binmeyecek kadar büyütür (>= 1).
  /// Her çift (i, j) için çarpanlar f_i, f_j <= dist / ((ri + rj) * (1 + gap)) ise ri*f_i + rj*f_j <= dist/(1+gap),
  /// yani iki UFO hiçbir zaman üst üste binmez. Boş bölgedeki UFO büyür, sıkışıktakiler olduğu gibi kalır.
  /// Sadece görsel: çarpışma/engel mantığı (geometry.dart) etkilenmez.
  List<double> _computeGrow(_G g) {
    final us = game.level.ufos;
    final res = List<double>.filled(us.length, _growMax);
    final gridW = g.unitX * g.bW;
    final gridH = g.unit * g.bH;
    for (int i = 0; i < us.length; i++) {
      final a = us[i];
      final da = g.unit * ufoDiameter(a.seats) * g.ufoScale;
      double best = _growMax;
      for (int j = 0; j < us.length; j++) {
        if (i == j) continue;
        final b = us[j];
        if (game.level.layerOfUfo(i) != game.level.layerOfUfo(j)) continue;
        final dx = (b.x - a.x) * g.unitX;
        final dy = (b.y - a.y) * g.unit;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist < 1e-6) continue; // aynı noktada doğan (üst üste doğan) araçlar: sırayla görünür
        final th = atan2(dy, dx);
        final db = g.unit * ufoDiameter(b.seats) * g.ufoScale;
        final rs = _ellipseR(da, a.seats, th) + _ellipseR(db, b.seats, th);
        best = min(best, dist / (rs * (1 + _growGap)));
      }
      // Panel kenarı: büyüyen UFO tahtanın dışına taşmasın.
      final cx = (a.x - g.bMinX) * g.unitX;
      final cy = (a.y - g.bMinY) * g.unit;
      final hw = da * _spriteW(a.seats) / 2;
      final hh = da * _spriteH(a.seats) / 2;
      best = min(best, min(cx, gridW - cx) / hw);
      best = min(best, min(cy, gridH - cy) / hh);
      res[i] = max(1.0, best);
    }
    return res;
  }

  /// Çizim boyu [d] olan UFO'nun görünen elipsinin, [th] yönündeki yarıçapı (px).
  double _ellipseR(double d, int seats, double th) {
    final ea = d * _spriteW(seats) / 2;
    final eb = d * _spriteH(seats) / 2;
    return ea * eb / sqrt(pow(eb * cos(th), 2) + pow(ea * sin(th), 2));
  }

  // ---- Park yerinde havada duran UFO (yuvaya konmaz; yuvanın üstünde süzülür, ışın altından iner)
  double _hoverSize(_G g, int seats) => g.slotSize * 0.98 * _seatScale(seats);
  double _hoverCx(_G g, int k) => g.slotsLeft + k * g.slotSize + g.slotSize / 2;
  double _hoverCy(_G g, double size) => g.slotsTop + 0.36 * size + 2;

  /// UFO'nun görünen alt kenarı (ışın buradan çıkar, yolcular buraya ışınlanır).
  double _hoverBottom(_G g, double size) => _hoverCy(g, size) + 0.30 * size;

  /// Yolcunun yuvada durduğu nokta (pad görselinin üst yüzeyi).
  Offset _padStand(_G g, int k) => Offset(_hoverCx(g, k), g.padTop + g.slotSize * 0.43 - 2);

  /// Sahadaki UFO'nun ekran merkezi.
  // ---- UFO çizim boyu (v0.16.4): gövde = disk çapı olduğu için ayrıca küçültme yok (v0.16.3'ün komşu uzaklığına göre
  // küçültme yaması kaldırıldı; UFO'lar yan yana değer ama üst üste binmez).
  double _fitFor(_G g, int id) => id < g.growOf.length ? g.growOf[id] : 1.0;

  /// Sahadaki UFO'nun ekranda çizilen çapı (px).
  double _gridUfoPx(_G g, UfoSpec sp) => g.unit * ufoDiameter(sp.seats) * g.ufoScale * _fitFor(g, sp.id);

  Offset _ufoCenter(_G g, UfoSpec s) => Offset(
        g.gridLeft + (s.x - g.bMinX) * g.unitX,
        g.gridTop + (s.y - g.bMinY) * g.unit,
      );

  // ------------------------------------------------------------ oyun akışı

  void _onTapUfo(int id) {
    if (ended) return;
    final u = game.ufos[id];
    if (!u.inGrid) return;
    if (!_tutAllowTap(id)) return;

    // Işınla: seçilen UFO (önü kapalı olsa da) ışınlanıp VIP yuvaya gider.
    if (vipArmed) {
      final k = game.tapVip(id);
      if (k < 0) {
        _flash(L.t('VIP yuva dolu', 'VIP slot is full'));
        return;
      }
      vipArmed = false;
      if (_tut == null) {
        // Öğretici sırasında ücretsiz; gerçek kullanımda 1 stok harcanır.
        Progress.boostStock[2] = max(0, Progress.boostStock[2] - 1);
        Progress.save();
        Stats.boosterUsed();
      }
      Settings.vibe(HapticFeedback.mediumImpact);
      if (game.breakQueue.isNotEmpty) _handleBreaks();
      final g = _geom(_lastW, _lastH);
      Audio.play(Sfx.vipTeleport);
      beamFrom[id] = _ufoCenter(g, u.spec);
      setState(() => beaming.add(id));
      Future.delayed(const Duration(milliseconds: _beamMs), () {
        if (!mounted) return;
        setState(() {
          landed.add(id);
          beaming.remove(id);
          beamFrom.remove(id);
        });
      });
      _tutAfterTap(id);
      return;
    }

    if (game.missedBelt(id)) {
      // Bant UFO'su ortada değil: ceza yok, sadece doğru anı beklet.
      Settings.vibe(HapticFeedback.selectionClick);
      Audio.play(Sfx.warn);
      _flash(L.t('Ortadayken dokun!', 'Tap it when it\'s in the middle!'));
      return;
    }
    if (!game.canLaunch(id)) {
      // Önü kapalı: UFO önündeki araca çarpıp yerine geri döner.
      Settings.vibe(HapticFeedback.heavyImpact);
      Audio.play(Sfx.ufoBlocked);
      game.noteWastedTap(); // hamle bütçesi seviyesinde kapalı UFO'ya dokunuş da hamle sayılır
      final dist = game.blockerDistance(id);
      setState(() {
        bumps[id] = _Bump(DateTime.now().millisecondsSinceEpoch, dist < 0 ? 0.0 : dist);
      });
      _tutAfterTap(id);
      return;
    }
    final k = game.tap(id);
    if (k < 0) {
      Settings.vibe(HapticFeedback.heavyImpact);
      Audio.play(Sfx.warn);
      _flash(L.t('Maks.', 'Max.'));
      return;
    }
    Settings.vibe(HapticFeedback.lightImpact);
    Audio.play(Sfx.ufoCall);
    spinStart[id] = DateTime.now().millisecondsSinceEpoch;
    setState(() {});
    if (game.breakQueue.isNotEmpty) _handleBreaks();
    Future.delayed(const Duration(milliseconds: _landMs), () {
      if (mounted) setState(() => landed.add(id));
    });
    _tutAfterTap(id);
  }

  /// Binişleri ışınlama animasyonuna çevirir. Yolcu bindiği kapıdan (halkadaki
  /// bulunduğu noktadan) UFO kubbesine doğru ışınlanır, UFO titrer.
  void _handleBoard(List<BoardEvent> events) {
    final g = _geom(_lastW, _lastH);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (events.isNotEmpty) _tutBoarded = true;
    setState(() {
      for (final e in events) {
        final u = game.ufos[e.ufoId];
        Audio.beam();
        if (u.departed && _fullChimed.add(e.ufoId)) {
          // Son yolcu UFO'ya varınca dolma sesi.
          Future<void>.delayed(const Duration(milliseconds: _flyMs), () {
            if (mounted) Audio.play(Sfx.ufoFull);
          });
        }
        final slot = max(0, u.lastSlot);
        final size = _hoverSize(g, u.spec.seats);
        final stand = _padStand(g, slot);
        final tx = _hoverCx(g, slot);
        final ty = _hoverBottom(g, size) - size * 0.12;
        final pt = _cellPoint(g, e.cell);
        final f = _Fly(_flyId++, e.ufoId, e.color, pt.dx, pt.dy, stand.dx, stand.dy, tx, ty);
        flies.add(f);
        pending[e.ufoId] = (pending[e.ufoId] ?? 0) + 1;
        lastBoard[e.ufoId] = now;
        if (Settings.screenFx) gateFlash[e.gate] = now;
        // Son yolcudan sonra UFO'nun kalkış zamanı gelince arayüzü yeniden çiz (UFO katmanı sadece setState ile yenilenir).
        Future.delayed(const Duration(milliseconds: _flyMs + _departWaitMs + 80), () {
          if (mounted) setState(() {});
        });
        Future.delayed(const Duration(milliseconds: _flyMs), () {
          if (!mounted) return;
          setState(() {
            flies.removeWhere((x) => x.id == f.id);
            pending[f.ufo] = max(0, (pending[f.ufo] ?? 1) - 1);
            bouncing.add(f.ufo);
          });
          Future.delayed(const Duration(milliseconds: 140), () {
            if (mounted) setState(() => bouncing.remove(f.ufo));
          });
          Future.delayed(const Duration(milliseconds: 380), () {
            if (mounted) setState(() {});
          });
        });
      }
    });
  }

  /// Dolan bütün UFO'ların çıkış uçuşu bitti mi (ekrandan çıktılar mı)?
  bool _allDeparted() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final u in game.ufos) {
      if (u.inGrid || !u.departed) continue;
      final ds = departStart[u.spec.id];
      if (ds == null || now - ds < _departMs + 150) return false;
    }
    return true;
  }

  void _checkEnd() {
    if (ended) return;
    if (game.won) {
      if (!_allDeparted()) return; // son UFO ekrandan çıkana kadar bölüm bitmez
      ended = true;
      _onWin();
    } else if (game.lost) {
      ended = true;
      _onLose();
    }
  }

  Future<void> _onWin() async {
    final reward = level.reward;
    Stats.levelWin(level.number);
    Progress.coins += reward;
    if (Progress.level <= level.number) Progress.level = level.number + 1;
    await Progress.save();
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    Audio.duckMusic(4900); // bölüm bitiş jingle'ı (4,85 sn) sürerken arka plan müziği tamamen susar
    Audio.play(Sfx.win);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, a1, a2) => WinOverlay(
        levelNumber: level.number,
        reward: reward,
        onDouble: () async {
          Progress.coins += reward;
          await Progress.save();
        },
        onMenu: () {
          Audio.play(Sfx.click);
          Navigator.of(ctx).pop();
          Navigator.of(context).pop();
        },
        onNext: () {
          Audio.play(Sfx.click);
          Navigator.of(ctx).pop();
          setState(() => _load(level.number + 1));
        },
      ),
    );
  }

  Future<void> _onLose() async {
    final moves = game.outOfMoves;
    Stats.levelLose(level.number, outOfMoves: moves);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    Audio.duckMusic(2000); // kaybetme sesi 1,9 sn
    Audio.play(Sfx.lose);
    await showGamePopup<void>(
      context,
      emoji: moves ? '👆' : '😵',
      title: moves ? L.t('Hamlen bitti', 'Out of moves') : L.t('Park yerleri doldu', 'Parking slots are full'),
      message: moves
          ? L.t('Dokunuş hakkın doldu. Kapalı veya kilitli UFO\'lara dokunmak da hamle sayılır!',
              'You\'ve used all your taps. Tapping blocked or locked UFOs also counts as a move!')
          : L.t('Hiçbir UFO yolcu alamıyor. Halkadaki renklere göre UFO seç!',
              'No UFO can take any passengers. Pick UFOs based on the colors on the ring!'),
      accent: const Color(0xFFFF5C7A),
      stacked: true,
      buttons: [
        if (!revived)
          PopupBtn<void>(
            moves ? L.t('+5 hamle (reklam)', '+5 moves (ad)') : L.t('+2 park yeri (reklam)', '+2 parking slots (ad)'),
            icon: Icons.ondemand_video_rounded,
            kind: PopupKind.reward,
            onTap: (ctx) async {
              final ok = await Ads.watch(
                ctx,
                tag: moves ? 'revive_moves' : 'revive_slots',
                title: moves ? L.t('+5 hamle', '+5 moves') : L.t('+2 park yeri', '+2 parking slots'),
                message: moves
                    ? L.t('Reklam izleyerek 5 ek hamle kazan ve devam et.', 'Watch an ad to get 5 extra moves and keep playing.')
                    : L.t('Reklam izleyerek 2 ek park yeri kazan ve devam et.', 'Watch an ad to get 2 extra parking slots and keep playing.'),
              );
              if (!ok || !mounted || !ctx.mounted) return;
              Navigator.of(ctx).pop();
              setState(() {
                if (moves) {
                  game.grantMoves(5);
                } else {
                  game.grantSlots(2);
                }
                revived = true;
                ended = false;
              });
            },
          ),
        PopupBtn<void>(
          L.t('Tekrar dene', 'Try again'),
          icon: Icons.replay_rounded,
          onTap: (ctx) async {
            Navigator.of(ctx).pop();
            setState(() => _load(level.number));
          },
        ),
        PopupBtn<void>(
          L.t('Menü', 'Menu'),
          kind: PopupKind.ghost,
          onTap: (ctx) async {
            Navigator.of(ctx).pop();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  // ------------------------------------------------------------ öğretici
  //
  // Referanstaki GuideChain mantığı: sırayla adımlar, oyun duraklar, sadece gösterilen şeye dokunulur.
  // Bölümler (kayıt anahtarı Progress.guidesSeen): basics (1. seviye), blocked (kapalı UFO),
  // board / shuffle / vip (booster açılışı), mystery (gizemli UFO), spawn (üst üste doğan UFO).

  TutStep? get _step {
    final t = _tut;
    if (t == null || _tutHold || _tutIdx >= t.steps.length) return null;
    return t.steps[_tutIdx];
  }

  bool get _tutPausesGame => _tut != null && (_tutHold || (_step?.pausesGame ?? false));

  void _tutInit(int n) {
    _tut = null;
    _tutIdx = 0;
    _tutHold = false;
    _tutUfo = null;
    _tutMem = null;
    _tutBoarded = false;
    _tutQueue.clear();
    bool need(String id) => !Progress.guidesSeen.contains(id);
    if (n == 1 && need('basics')) _tutQueue.add('basics');
    if (n >= 2 && need('blocked') && _pickBlocked() != null) _tutQueue.add('blocked');
    if (n >= _unlockBoard && need('board')) _tutQueue.add('board');
    if (n >= _unlockShuffle && need('shuffle')) _tutQueue.add('shuffle');
    if (level.ufos.any((u) => u.mystery) && need('mystery')) _tutQueue.add('mystery');
    if (level.hasVip && n >= _unlockVip && need('vip')) _tutQueue.add('vip');
    if (level.ufos.any((u) => u.group >= 0) && need('spawn')) _tutQueue.add('spawn');
    // Özgün mekanikler: ilk karşılaşmada kısa tanıtım (hepsi bilgi adımı; oyun durur).
    for (final m in level.rules.mechs) {
      final gid = _mechGuideId(m);
      // Hamle bütçesi: sadece tanıtım seviyesinde (L16). Dönen / arızalı UFO: ilk göründükleri seviyede bir kez.
      if (need(gid) && (m != Mech.budget || n == kMechUnlock[m])) _tutQueue.add(gid);
    }
    if (level.layerCount > 1 && need('layer')) _tutQueue.add('layer');
    _tutNextGuide();
  }

  void _tutNextGuide() {
    _tut = null;
    _tutUfo = null;
    while (_tutQueue.isNotEmpty) {
      final id = _tutQueue.removeAt(0);
      final guide = _tutGuide(id);
      if (guide.steps.isEmpty) continue;
      _tut = guide;
      _tutShown = false;
      _tutGoto(0);
      if (_tut != null) return;
    }
  }

  /// Adıma geç (setState çağırmaz). Hedef UFO bulunamazsa adım atlanır; bitince bölüm kaydedilir.
  void _tutGoto(int i) {
    final t = _tut;
    if (t == null) return;
    if (i >= t.steps.length) {
      // Hiç adım gösterilemediyse (hedef UFO yoktu) bölümü "görüldü" sayma; sonraki seviyede tekrar denensin.
      if (_tutShown) {
        Progress.guidesSeen.add(t.id);
        Progress.save();
      }
      _tutNextGuide();
      return;
    }
    if (i == 0) {
      // Her bölüm temiz başlar (adımlar arası hatırlanan değerler sıfırlanır).
      _tutMem = null;
    }
    _tutIdx = i;
    _tutStepMs = DateTime.now().millisecondsSinceEpoch;
    final st = t.steps[i];
    _tutUfo = st.ufo?.call();
    if (st.ufo != null && _tutUfo == null) {
      _tutGoto(i + 1);
    } else {
      _tutShown = true;
      st.onEnter?.call();
    }
  }

  void _tutAdvance(int holdMs) {
    final next = _tutIdx + 1;
    if (holdMs <= 0) {
      setState(() => _tutGoto(next));
      return;
    }
    setState(() => _tutHold = true);
    Future.delayed(Duration(milliseconds: holdMs), () {
      if (!mounted) return;
      setState(() {
        _tutHold = false;
        _tutGoto(next);
      });
    });
  }

  void _tutSkipAll() {
    final t = _tut;
    if (t != null) Progress.guidesSeen.add(t.id);
    for (final id in _tutQueue) {
      Progress.guidesSeen.add(id);
    }
    Progress.save();
    setState(() {
      vipArmed = false;
      _tutQueue.clear();
      _tut = null;
      _tutUfo = null;
      _tutHold = false;
    });
  }

  /// watch adımı: olay olunca ya da süre dolunca sonraki adıma geçer.
  void _tutWatch() {
    final st = _step;
    if (st == null || st.kind != TutKind.watch) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((st.done?.call() ?? false) || now - _tutStepMs > st.timeoutMs) {
      setState(() => _tutGoto(_tutIdx + 1));
    }
  }

  bool _tutAllowTap(int id) {
    if (_tut == null) return true;
    if (_tutHold) return false;
    final st = _step;
    if (st == null) return true;
    if (st.kind == TutKind.watch) return true;
    if (st.kind == TutKind.tapUfo) {
      if (id == _tutUfo) return true;
      _flash(L.t('Parlayan UFO\'ya dokun', 'Tap the glowing UFO'));
      return false;
    }
    if (st.kind == TutKind.tapBtn) _flash(L.t('Parlayan düğmeye dokun', 'Tap the glowing button'));
    return false;
  }

  void _tutAfterTap(int id) {
    final st = _step;
    if (st != null && st.kind == TutKind.tapUfo && id == _tutUfo) {
      _tutMem = id;
      _tutAdvance(st.holdMs);
    }
  }

  /// Halkadaki yolcu renklerine en çok uyan, önü açık UFO.
  int? _pickLaunch({int? exclude}) {
    final opts = game.launchable().where((id) => id != exclude).toList();
    if (opts.isEmpty) return null;
    int score(int id) {
      int n = 0;
      for (final p in game.cells) {
        if (p != null && p.color == game.ufos[id].spec.color) n++;
      }
      return n;
    }

    opts.sort((a, b) => score(b).compareTo(score(a)));
    return opts.first;
  }

  /// Önü kapalı ve önündeki araç serbest olan UFO (öğretici: "önündekini çıkar").
  int? _pickBlocked() {
    int? best;
    double bestD = 1e9;
    for (final u in game.ufos) {
      final id = u.spec.id;
      if (!u.inGrid || !u.spawned || game.canLaunch(id)) continue;
      final b = game.firstBlocker(id);
      if (b == null || !game.canLaunch(b)) continue;
      final d = game.blockerDistance(id);
      if (d < bestD) {
        bestD = d;
        best = id;
      }
    }
    return best;
  }

  String _mechGuideId(Mech m) => 'm_${m.toString().split('.').last}';

  TutGuide _tutGuide(String id) {
    switch (id) {
      case 'm_budget':
        return TutGuide(id, [
          TutStep(
            kind: TutKind.info,
            title: '👆 ${kMechTitle[Mech.budget]}',
            text: L.t('Dokunuş hakkın sınırlı. Kalan hamle burada yazıyor: ${game.movesLeft}. Bitince seviye biter.',
                'Your taps are limited. The moves you have left are shown here: ${game.movesLeft}. When they run out, the level ends.'),
            region: 'hud',
            button: L.t('Anladım', 'Got it'),
          ),
          TutStep(
            kind: TutKind.tapUfo,
            text: L.t('Önü kapalı bir UFO\'ya dokun: boşa dokunuş da hamle sayılır. (Bu seferlik öğretmek için)', 'Tap a blocked UFO: a wasted tap also counts as a move. (Just this once, to teach you)'),
            ufo: () {
              _tutMem = _pickBlocked();
              return _tutMem;
            },
            holdMs: 900,
          ),
          TutStep(
            kind: TutKind.info,
            title: L.t('Hamle azaldı!', 'Moves went down!'),
            text: L.t('Gördün mü, sayaç düştü. Kapalı UFO\'lara boşuna dokunma; önü açıkları çağırarak hamleni akıllıca kullan.', 'See, the counter dropped. Don\'t waste taps on blocked UFOs; call the ones with a clear path and spend your moves wisely.'),
            region: 'hud',
            ufo: () => _tutMem,
            button: L.t('Tamam', 'OK'),
          ),
        ]);
      case 'm_rotor':
        return TutGuide(id, [
          TutStep(
            kind: TutKind.info,
            title: '🔄 ${kMechTitle[Mech.rotor]}',
            text: L.t('Mavi halkalı UFO belli aralıkla yön değiştirir. Halka sarı yanıp sönerse dönmek üzere!', 'The UFO with the blue ring changes direction at set intervals. If the ring blinks yellow, it is about to turn!'),
            ufo: () => _pickRotorTarget(),
            button: L.t('Anladım', 'Got it'),
          ),
          TutStep(
            kind: TutKind.watch,
            text: L.t('İzle: UFO yön değiştiriyor. Okun gösterdiği yöne çıkar.', 'Watch: the UFO is changing direction. It leaves in the direction its arrow points.'),
            ufo: () => _tutMem,
            onEnter: () => _tutMark = game.rotVersion,
            done: () => game.rotVersion != _tutMark,
            timeoutMs: 9000,
          ),
          TutStep(
            kind: TutKind.watch,
            text: L.t('Şimdi önü açık yöne dönmesini bekle…', 'Now wait for it to turn to a direction with a clear path…'),
            ufo: () => _tutMem,
            done: () => _tutMem != null && !game.ufos[_tutMem!].flipped && game.canLaunch(_tutMem!),
            timeoutMs: 9000,
          ),
          TutStep(
            kind: TutKind.tapUfo,
            text: L.t('Önü açıkken dokun!', 'Tap it while its path is clear!'),
            ufo: () => _tutMem,
            holdMs: 700,
          ),
        ]);
      case 'm_belt':
        return TutGuide(id, [
          TutStep(
            kind: TutKind.info,
            title: '⇆ ${kMechTitle[Mech.belt]}',
            text: L.t('Bantta kayan UFO sadece bandın ortasındayken çağrılır. Ortaya gelince halkası yeşil yanar.', 'A UFO sliding on the belt can only be called when it is in the middle of the belt. Its ring turns green when it gets there.'),
            ufo: () => _pickBeltTarget(),
            button: L.t('Anladım', 'Got it'),
          ),
          TutStep(
            kind: TutKind.watch,
            text: L.t('İzle: UFO kayıyor. Yeşil halka yanınca ortadadır.', 'Watch: the UFO is sliding. When the green ring lights up, it is in the middle.'),
            ufo: () => _tutMem,
            onEnter: () => _tutFlag = false,
            done: () {
              final t = _tutMem;
              if (t == null) return true;
              final open = game.beltOpen(game.ufos[t]);
              if (!open) _tutFlag = true;
              return _tutFlag && open;
            },
            timeoutMs: 9000,
          ),
          TutStep(
            kind: TutKind.tapUfo,
            text: L.t('Şimdi dokun! Kaçırırsan ceza yok, bir sonraki geçişi beklersin.', 'Tap now! If you miss it, there is no penalty; you just wait for the next pass.'),
            ufo: () => _tutMem,
            holdMs: 700,
          ),
        ]);
      case 'm_faulty':
        return TutGuide(id, [
          TutStep(
            kind: TutKind.info,
            title: '🔧 ${kMechTitle[Mech.faulty]}',
            text: L.t('Üstündeki sayı her UFO çıkışında düşer. 0 olursa UFO bozulur.', 'The number on it drops every time a UFO leaves. If it reaches 0, the UFO breaks down.'),
            ufo: () => _pickFaultyTarget(),
            button: L.t('Anladım', 'Got it'),
          ),
          TutStep(
            kind: TutKind.tapUfo,
            text: L.t('Başka bir UFO çağır, sayacın düştüğünü gör.', 'Call another UFO and watch the counter drop.'),
            ufo: () => _pickPlain(),
            holdMs: 900,
          ),
          TutStep(
            kind: TutKind.info,
            title: L.t('Sayaç düştü!', 'Counter dropped!'),
            text: L.t(
                '0 olursa reklamla tamir edersin ya da bırakırsın: UFO gider, birkaç hamle sonra geri gelir. '
                    'Önündekileri temizleyip erken çağır.',
                'If it reaches 0, you can repair it with an ad or let it go: the UFO leaves and comes back after a few moves. '
                    'Clear what is in front of it and call it early.'),
            ufo: () => _pickFaultyTarget(),
            button: L.t('Tamam', 'OK'),
          ),
        ]);
      case 'layer':
        return TutGuide('layer', [
          TutStep(
            kind: TutKind.info,
            title: L.t('⬆ Katman asansörü', '⬆ Floor elevator'),
            text: L.t(
                'Bu seviye çok katlı! Önce görünen UFO\'ları bitir; sonra alttaki kat asansörle yukarı çıkar. '
                    'Her katta yolcular o katın renkleriyle gelir.',
                'This level has multiple floors! Finish the visible UFOs first; then the floor below rises up by elevator. '
                    'On each floor, passengers arrive in that floor\'s colors.'),
            button: L.t('Anladım', 'Got it'),
          ),
        ]);
      case 'basics':
        return TutGuide(id, [
          TutStep(
            kind: TutKind.info,
            title: L.t('Hoş geldin!', 'Welcome!'),
            text: L.t('Uzaylılar halkada dönüyor. Amacın hepsini kendi renkli UFO\'suna bindirmek.', 'The aliens are circling on the ring. Your goal is to get each one onto the UFO of its own color.'),
            region: 'ring',
            button: L.t('Başla', 'Start'),
          ),
          TutStep(
            kind: TutKind.tapUfo,
            text: L.t('Önü açık bir UFO\'ya dokun. Park yerine uçar.', 'Tap a UFO with a clear path. It flies to a parking slot.'),
            ufo: () => _pickLaunch(),
            holdMs: 700,
          ),
          TutStep(
            kind: TutKind.watch,
            text: L.t('Aynı renkteki uzaylılar kapıdan geçerken UFO\'ya biner.', 'Aliens of the same color board the UFO as they pass the gate.'),
            region: 'pads',
            done: () => _tutBoarded && _tutMem != null && landed.contains(_tutMem),
          ),
          TutStep(
            kind: TutKind.info,
            title: L.t('Kalan kapasite', 'Remaining capacity'),
            text: L.t('UFO\'nun altındaki sayı kalan kapasite. Her uzaylıda azalır, 0 olunca UFO yolcularıyla gider.', 'The number under the UFO is its remaining capacity. It goes down with every alien, and at 0 the UFO leaves with its passengers.'),
            region: 'counter',
            button: L.t('Anladım', 'Got it'),
          ),
          TutStep(
            kind: TutKind.info,
            title: L.t('Park yerlerin sınırlı', 'Your parking slots are limited'),
            text: L.t(
                'Sadece ${level.slots} park yerin var. Hepsi doluyken yeni UFO çağıramazsın; '
                    'uygun renk gelmezse seviye biter. Yerleri akıllıca kullan.',
                'You only have ${level.slots} parking slots. When they are all full, you can\'t call a new UFO; '
                    'if no matching color comes, the level ends. Use your slots wisely.'),
            region: 'pads',
            button: L.t('Tamam', 'OK'),
          ),
          TutStep(
            kind: TutKind.tapUfo,
            text: L.t('Şimdi sıradaki UFO\'yu sen çağır!', 'Now call the next UFO yourself!'),
            ufo: () => _pickLaunch(exclude: _tutMem),
            holdMs: 500,
          ),
        ]);
      case 'blocked':
        return TutGuide(id, [
          TutStep(
            kind: TutKind.tapUfo,
            text: L.t('Bu UFO\'nun önü kapalı (ok yönüne bak). Dokun, ne olacağını gör.', 'This UFO\'s path is blocked (look at its arrow). Tap it and see what happens.'),
            ufo: () {
              _tutMem = _pickBlocked();
              return _tutMem;
            },
            holdMs: 900,
          ),
          TutStep(
            kind: TutKind.info,
            title: L.t('Yol kapalı!', 'Path blocked!'),
            text: L.t('UFO önündeki araca çarpıp geri döndü. Önce yoldaki UFO\'yu çıkarman gerek.', 'The UFO bumped into the vehicle ahead and came back. You need to clear the UFO in the way first.'),
            ufo: () => _tutMem == null ? null : game.firstBlocker(_tutMem!),
            button: L.t('Devam', 'Continue'),
          ),
          TutStep(
            kind: TutKind.tapUfo,
            text: L.t('Önündekini çıkar: ona dokun!', 'Clear the one in front: tap it!'),
            ufo: () => _tutMem == null ? null : game.firstBlocker(_tutMem!),
            holdMs: 600,
          ),
          TutStep(
            kind: TutKind.info,
            title: L.t('Güzel!', 'Nice!'),
            text: L.t('Kural basit: UFO ok yönünde çıkar. Önü açıksa uçar, kapalıysa çarpar. Önünü açarak ilerle.', 'The rule is simple: a UFO leaves in the direction of its arrow. If the path is clear it flies, if blocked it bumps. Make progress by clearing the way.'),
            button: L.t('Tamam', 'OK'),
          ),
        ]);
      case 'board':
        return TutGuide('board', [
          TutStep(
            kind: TutKind.info,
            title: L.t('Hemen Bin', 'Board Now'),
            text: L.t('Park yerinde bekleyen UFO\'lar için halkadaki uygun yolcuları anında bindirir. Stoğun olduğu sürece istediğin kadar kullan.', 'Instantly boards the matching passengers on the ring onto the UFOs waiting in the parking slots. Use it as much as you like while you have stock.'),
            boost: 0,
            region: 'pads',
            button: L.t('Anladım', 'Got it'),
          ),
        ]);
      case 'shuffle':
        return TutGuide('shuffle', [
          TutStep(
            kind: TutKind.info,
            title: L.t('Karıştır', 'Shuffle'),
            text: L.t('Kollarda bekleyen yolcuların sırasını değiştirir. İstediğin renk geç geliyorsa kullan. Stoğun olduğu sürece istediğin kadar.', 'Changes the order of the passengers waiting on the arms. Use it if the color you want is coming late. As much as you like while you have stock.'),
            boost: 1,
            region: 'ring',
            button: L.t('Anladım', 'Got it'),
          ),
        ]);
      case 'vip':
        return TutGuide('vip', [
          TutStep(
            kind: TutKind.info,
            title: L.t('Işınla & VIP yuva', 'Teleport & VIP slot'),
            text: L.t('Altın yuva VIP yuva: normal dokunuşla dolmaz. Işınla ile önü kapalı bile olsa istediğin UFO\'yu buraya gönderirsin.', 'The golden slot is the VIP slot: it can\'t be filled with a normal tap. With Teleport you can send any UFO here, even if its path is blocked.'),
            boost: 2,
            region: 'vip',
            button: L.t('Devam', 'Continue'),
          ),
          TutStep(
            kind: TutKind.tapBtn,
            text: L.t('Önce Işınla düğmesine dokun!', 'First tap the Teleport button!'),
            boost: 2,
          ),
          TutStep(
            kind: TutKind.tapUfo,
            text: L.t('Şimdi bir UFO seç: önü kapalı olsa da VIP yuvaya ışınlanır.', 'Now pick a UFO: it teleports to the VIP slot even if its path is blocked.'),
            ufo: () => _pickBlocked() ?? _pickLaunch(),
            holdMs: 1700,
          ),
          TutStep(
            kind: TutKind.info,
            title: L.t('Işınlandı!', 'Teleported!'),
            text: L.t('UFO altın VIP yuvada yolcu bekliyor. VIP yuva boşken Işınla\'yı tekrar kullanabilirsin; stoğun bitince reklamla +1 alırsın.', 'The UFO is waiting for passengers in the golden VIP slot. When the VIP slot is empty you can use Teleport again; when your stock runs out you get +1 by watching an ad.'),
            region: 'vip',
            button: L.t('Tamam', 'OK'),
          ),
        ]);
      case 'mystery':
        return TutGuide(id, [
          TutStep(
            kind: TutKind.info,
            title: L.t('Gizemli UFO', 'Mystery UFO'),
            text: L.t('Siyah "?" işaretli UFO\'nun rengi, önü kapalıyken gizli. Yolunu açınca rengi ortaya çıkar.', 'The color of the UFO marked with a black "?" is hidden while its path is blocked. Clear its way and the color is revealed.'),
            ufo: () {
              for (final u in game.ufos) {
                if (u.spec.mystery && u.inGrid && u.spawned) return u.spec.id;
              }
              return null;
            },
            button: L.t('Anladım', 'Got it'),
          ),
        ]);
      default: // spawn
        return TutGuide('spawn', [
          TutStep(
            kind: TutKind.info,
            title: L.t('Işınlama kapısı', 'Teleport gate'),
            text: L.t('Mor kapıdan UFO\'lar sırayla gelir: öndeki gidince arkasındaki yeni UFO kapıdan çıkar.', 'UFOs come through the purple gate in order: when the front one leaves, the next UFO behind it comes out of the gate.'),
            ufo: () => _pickPortalFront(),
            button: L.t('Anladım', 'Got it'),
          ),
          TutStep(
            kind: TutKind.tapUfo,
            text: L.t('Kapıdaki öndeki UFO\'yu çağır.', 'Call the UFO at the front of the gate.'),
            ufo: () => _pickPortalFront(),
            holdMs: 700,
          ),
          TutStep(
            kind: TutKind.info,
            title: L.t('Yeni UFO geldi!', 'A new UFO arrived!'),
            text: L.t('Kapıdan sıradaki UFO çıktı. Kapıdaki sayı (+N) kaç UFO daha beklediğini gösterir.', 'The next UFO came out of the gate. The number on the gate (+N) shows how many more UFOs are waiting.'),
            ufo: () {
              final m = _tutMem;
              if (m == null) return null;
              final list = game.groups[game.ufos[m].spec.group];
              if (list == null) return null;
              for (final id in list) {
                final u = game.ufos[id];
                if (u.inGrid && u.spawned) return id;
              }
              return null;
            },
            button: L.t('Tamam', 'OK'),
          ),
        ]);
    }
  }

  // ---- etkileşimli öğretici hedef seçicileri

  /// Hedef UFO'nun ev yönünde önü açık mı (dönüş / bant penceresi hesaba katılmadan).
  bool _homeOpen(UfoState u) {
    for (final o in game.ufos) {
      if (o.spec.id == u.spec.id || !o.inGrid || !o.spawned) continue;
      if (sweepHit(u.spec, o.cur) != null) return false;
    }
    return true;
  }

  int? _pickRotorTarget() {
    int? any;
    for (final u in game.ufos) {
      if (!u.rotor || !u.inGrid || !u.spawned) continue;
      any ??= u.spec.id;
      if (_homeOpen(u)) {
        _tutMem = u.spec.id;
        return u.spec.id;
      }
    }
    _tutMem = null; // önü açık dönen UFO yok: sadece bilgi kartı
    return any;
  }

  int? _pickBeltTarget() {
    int? any;
    for (final u in game.ufos) {
      if (!u.belt || !u.inGrid || !u.spawned) continue;
      any ??= u.spec.id;
      if (_homeOpen(u)) {
        _tutMem = u.spec.id;
        return u.spec.id;
      }
    }
    _tutMem = null;
    return any;
  }

  int? _pickFaultyTarget() {
    for (final u in game.ufos) {
      if (u.faulty && u.inGrid && u.spawned) return u.spec.id;
    }
    return null;
  }

  /// Öğretici için sade bir UFO: arızalı / dönen / bant olmayan, önü açık.
  int? _pickPlain() {
    final opts = game.launchable().where((id) {
      final u = game.ufos[id];
      return !u.faulty && !u.rotor && !u.belt;
    }).toList();
    if (opts.isEmpty) return null;
    return opts.first;
  }

  /// Işınlama kapısındaki öndeki UFO (önü açık, arkasında bekleyen var).
  int? _pickPortalFront() {
    for (final u in game.ufos) {
      final gr = u.spec.group;
      if (gr < 0 || !u.inGrid || !u.spawned) continue;
      if ((game.groups[gr]?.length ?? 0) < 2) continue;
      if (game.canLaunch(u.spec.id)) return u.spec.id;
    }
    return null;
  }

  Rect? _keyRect(GlobalKey k) {
    final ro = k.currentContext?.findRenderObject();
    final bo = _boardKey.currentContext?.findRenderObject();
    if (ro is RenderBox && bo is RenderBox && ro.hasSize && bo.attached && ro.attached) {
      return ro.localToGlobal(Offset.zero, ancestor: bo) & ro.size;
    }
    return null;
  }

  Widget _tutLayer(_G g, double W, double H) {
    final st = _step;
    if (_tut == null || st == null || ended) return const SizedBox.shrink();
    final guide = _tut!;
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final holes = <TutHole>[];
          Offset? handAt;
          Rect? boostRect;
          if (st.ufo != null && _tutUfo != null && game.ufos[_tutUfo!].inGrid) {
            final u = game.ufos[_tutUfo!];
            final c = _ufoCenter(g, u.spec);
            final size = _gridUfoPx(g, u.spec);
            holes.add(TutHole.circle(c, max(size * 0.62, 26.0)));
            // El SADECE gerçekten dokunulabilen UFO'da görünür (bilgi adımlarında dokunuş çalışmaz).
            if (st.kind == TutKind.tapUfo) handAt = c;
          }
          if (st.boost != null) {
            final r = _keyRect(_boostKeys[st.boost!]);
            if (r != null) {
              holes.add(TutHole.box(r));
              // Booster adımında parlayan düğmeye dokunmak da "Anladım" gibi devam ettirir
              // (booster'ı harcamaz; öğretici seviye başında, park yeri boşken gösterilir).
              boostRect = r.inflate(6);
              handAt = r.center;
            }
          }
          switch (st.region) {
            case 'ring':
              holes.add(TutHole.box(Rect.fromLTWH(4, g.ringTop, W - 8, g.ringH)));
              break;
            case 'pads':
              holes.add(TutHole.box(Rect.fromLTWH(
                  g.slotsLeft, g.slotsTop, g.slotSize * g.slotCount, g.hoverH + g.slotSize + _counterH)));
              break;
            case 'vip':
              holes.add(TutHole.box(
                  Rect.fromLTWH(g.slotsLeft, g.slotsTop, g.slotSize, g.hoverH + g.slotSize + _counterH)));
              break;
            case 'hud':
              holes.add(TutHole.box(Rect.fromLTWH(W * 0.2, g.topInset, W * 0.6, g.hudH)));
              break;
            case 'counter':
              int k = 0;
              if (_tutMem != null && !game.ufos[_tutMem!].inGrid) k = max(0, game.ufos[_tutMem!].lastSlot);
              holes.add(TutHole.box(
                  Rect.fromLTWH(g.slotsLeft + k * g.slotSize, g.padTop + g.slotSize - 6, g.slotSize, _counterBox)));
              break;
          }
          double fy = H * 0.5;
          if (holes.isNotEmpty) {
            fy = holes.map((h) => h.rect.center.dy).reduce((a, b) => a + b) / holes.length;
          }
          final cardTop = fy > H * 0.5;
          final isInfo = st.kind == TutKind.info;
          final card = TutCard(
            title: st.title,
            text: st.text,
            button: isInfo ? st.button : null,
            onButton: isInfo ? () => _tutAdvance(0) : null,
            onSkip: _tutSkipAll,
            stepNo: _tutIdx + 1,
            stepCount: guide.steps.length,
          );
          final kids = <Widget>[];
          if (isInfo) {
            // Bilgi adımı: arkadaki oyuna dokunuşu engelle.
            kids.add(Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {})));
            if (boostRect != null) {
              kids.add(Positioned.fromRect(
                rect: boostRect,
                child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _tutAdvance(0)),
              ));
            }
          }
          kids.add(Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: TutSpotPainter(holes, _clock.value, dim: st.kind != TutKind.watch)),
            ),
          ));
          if (handAt != null) {
            kids.add(Positioned(
              left: handAt.dx - 12,
              top: handAt.dy - 6,
              child: IgnorePointer(child: TutHand(t: _clock.value)),
            ));
          }
          kids.add(Positioned(
            left: 16,
            right: 16,
            top: cardTop ? g.topInset + g.hudH + 8 : null,
            bottom: cardTop ? null : g.boostH + 10,
            child: Align(alignment: Alignment.center, heightFactor: 1.0, child: card),
          ));
          return Stack(children: kids);
        },
      ),
    );
  }

  // ------------------------------------------------------------ booster'lar

  bool _locked(int unlockLevel) {
    if (level.number < unlockLevel) {
      _flash(L.t('Seviye $unlockLevel\'de açılır', 'Unlocks at level $unlockLevel'));
      return true;
    }
    return false;
  }

  void _useBoard() {
    if (_tut != null) {
      _flash(L.t('Önce öğreticiyi bitir', 'Finish the tutorial first'));
      return;
    }
    if (ended || _locked(_unlockBoard)) return;
    if (Progress.boostStock[0] <= 0) {
      _askBooster(0, L.t('Hemen Bin', 'Board Now'));
      return;
    }
    final ev = game.directBoard();
    if (ev.isEmpty) {
      _flash(L.t('Park yerinde bekleyen UFO yok', 'No UFO waiting in the parking slots'));
      return;
    }
    Progress.boostStock[0] = max(0, Progress.boostStock[0] - 1);
    Progress.save();
    Stats.boosterUsed();
    Audio.play(Sfx.boosterBoard);
    _handleBoard(ev);
    _flash(L.t('Hemen bin!', 'Boarded!'));
  }

  void _useShuffle() {
    if (_tut != null) {
      _flash(L.t('Önce öğreticiyi bitir', 'Finish the tutorial first'));
      return;
    }
    if (ended || _locked(_unlockShuffle)) return;
    if (Progress.boostStock[1] <= 0) {
      _askBooster(1, L.t('Karıştır', 'Shuffle'));
      return;
    }
    Progress.boostStock[1] = max(0, Progress.boostStock[1] - 1);
    Progress.save();
    Stats.boosterUsed();
    Audio.play(Sfx.shuffle);
    setState(() => game.shuffleQueue(level.number * 31 + game.remainingTotal));
    _flash(L.t('Sıradaki yolcular karıştı!', 'Upcoming passengers shuffled!'));
  }

  void _useVip() {
    final st = _step;
    final tutBtn = _tut != null && st != null && st.kind == TutKind.tapBtn && st.boost == 2;
    if (_tut != null && !tutBtn) {
      _flash(L.t('Önce öğreticiyi bitir', 'Finish the tutorial first'));
      return;
    }
    if (ended || _locked(_unlockVip)) return;
    if (game.slots.isEmpty || game.slots[0] != -1) {
      _flash(L.t('VIP yuva dolu', 'VIP slot is full'));
      return;
    }
    if (tutBtn) {
      // Öğretici: stok harcamaz; düğmeye dokununca UFO seçme adımına geçer.
      setState(() => vipArmed = true);
      _tutAdvance(0);
      return;
    }
    if (!vipArmed && Progress.boostStock[2] <= 0) {
      _askBooster(2, L.t('Işınla', 'Teleport'));
      return;
    }
    setState(() => vipArmed = !vipArmed);
    if (vipArmed) _flash(L.t('Işınlamak için bir UFO seç', 'Pick a UFO to teleport'));
  }

  /// Booster al: reklam izleyerek (+1) ya da coinle (kBoosterCoinPrice). Stok bitince ve "+" düğmesine basınca açılır.
  Future<void> _askBooster(int idx, String name) async {
    if (ended) return;
    if (_tut != null) {
      _flash(L.t('Önce öğreticiyi bitir', 'Finish the tutorial first'));
      return;
    }
    final canBuy = Progress.coins >= kBoosterCoinPrice;
    const boosterAssets = [
      'assets/img/booster_board.webp',
      'assets/img/booster_shuffle.webp',
      'assets/img/booster_vip.webp',
    ];
    final asset = boosterAssets[idx.clamp(0, 2).toInt()];
    final choice = await showGamePopup<String>(
      context,
      badge: Padding(padding: const EdgeInsets.all(13), child: Image.asset(asset, fit: BoxFit.contain)),
      title: L.t('$name al', 'Get $name'),
      dismissible: true,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PopupChip(leading: Image.asset(asset, width: 20, height: 20), text: L.t('Stok ${Progress.boostStock[idx]}', 'Stock ${Progress.boostStock[idx]}')),
              const SizedBox(width: 10),
              PopupChip(leading: Image.asset('assets/img/coin.webp', width: 20, height: 20), text: '${Progress.coins}'),
            ],
          ),
          if (!canBuy)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(L.t('Yeterli coin yok.', 'Not enough coins.'),
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13.5)),
            ),
        ],
      ),
      buttons: [
        PopupBtn<String>(L.t('Reklam izle  +1', 'Watch ad  +1'), icon: Icons.ondemand_video_rounded, kind: PopupKind.reward, value: 'ad'),
        PopupBtn<String>(
          L.t('$kBoosterCoinPrice coin ile al', 'Buy for $kBoosterCoinPrice coins'),
          leading: Image.asset('assets/img/coin.webp', width: 22, height: 22),
          kind: PopupKind.gold,
          value: 'coin',
          enabled: canBuy,
        ),
        PopupBtn<String>(L.t('Vazgeç', 'Cancel'), kind: PopupKind.ghost),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'ad') {
      // Reklam isteğe bağlı: önce "İzle / Vazgeç" onayı, sonra reklam.
      final watched = await Ads.watch(
        context,
        tag: 'booster_ad',
        title: '+1 $name',
        message: L.t('Reklam izleyerek 1 adet $name kazan.', 'Watch an ad to earn 1 $name.'),
      );
      if (!watched || !mounted) return;
      setState(() => Progress.boostStock[idx] += 1);
      Progress.save();
      _flash('+1 $name');
    } else if (choice == 'coin') {
      if (Progress.coins < kBoosterCoinPrice) return;
      setState(() {
        Progress.coins -= kBoosterCoinPrice;
        Progress.boostStock[idx] += 1;
      });
      Progress.save();
      Stats.coinBuy();
      _flash('+1 $name');
    }
  }

  /// Booster ilk açıldığı seviyede kısa "Yeni açıldı" penceresi (bir kez) ve düğme parıltısı.
  void _maybeUnlockPopup(int n) {
    _newBoost = -1;
    int idx = -1;
    String name = '';
    String asset = '';
    String desc = '';
    if (n == _unlockBoard) {
      idx = 0;
      name = L.t('Hemen Bin', 'Board Now');
      asset = 'assets/img/booster_board.webp';
      desc = L.t('Park yerinde bekleyen UFO\'lara halkadan anında yolcu bindirir.',
          'Instantly boards passengers from the ring onto the UFOs waiting in the parking slots.');
    } else if (n == _unlockShuffle) {
      idx = 1;
      name = L.t('Karıştır', 'Shuffle');
      asset = 'assets/img/booster_shuffle.webp';
      desc = L.t('Kollarda bekleyen yolcuların sırasını değiştirir.', 'Changes the order of the passengers waiting on the arms.');
    } else if (n == _unlockVip) {
      idx = 2;
      name = L.t('Işınla & VIP yuva', 'Teleport & VIP slot');
      asset = 'assets/img/booster_vip.webp';
      desc = L.t('Altın VIP yuva açıldı! Işınla ile istediğin UFO\'yu oraya gönder.',
          'The golden VIP slot is now open! Use Teleport to send any UFO there.');
    }
    if (idx < 0) return;
    final id = 'unlock_$idx';
    if (Progress.guidesSeen.contains(id)) return;
    Progress.guidesSeen.add(id);
    Progress.save();
    _newBoost = idx;
    _popupOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await showGamePopup<void>(
        context,
        badge: Padding(padding: const EdgeInsets.all(13), child: Image.asset(asset, fit: BoxFit.contain)),
        title: L.t('🔓 Yeni açıldı!', '🔓 Unlocked!'),
        accent: const Color(0xFFFFB300),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(desc,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withAlpha(215), fontSize: 15, fontWeight: FontWeight.w600, height: 1.35)),
            const SizedBox(height: 10),
            Text(L.t('Hediye: ${Progress.startStock} adet', 'Gift: ${Progress.startStock}'),
                style: const TextStyle(color: Colors.amber, fontSize: 14.5, fontWeight: FontWeight.w800)),
          ],
        ),
        buttons: [PopupBtn<void>(L.t('Harika!', 'Awesome!'), kind: PopupKind.gold)],
      );
      if (mounted) setState(() => _popupOpen = false);
    });
  }

  /// Kilitli yuvaya dokununca: reklam izle, yuva aç (şimdilik demo; gerçek oyunda ödüllü reklam).
  Future<void> _askUnlockSlot() async {
    if (ended || game.lockedSlots <= 0) return;
    if (_tut != null) {
      _flash(L.t('Önce öğreticiyi bitir', 'Finish the tutorial first'));
      return;
    }
    final ok = await Ads.watch(context,
        tag: 'slot_unlock',
        title: L.t('Yeni park yeri', 'New parking slot'),
        message: L.t('Reklam izleyerek kilitli bir park yerini aç.', 'Watch an ad to unlock a locked parking slot.'));
    if (ok && mounted) setState(() => game.unlockSlot());
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/img/bg_station.webp', fit: BoxFit.cover),
          Container(color: Colors.black.withAlpha(70)),
          SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, c) {
                _lastW = c.maxWidth;
                _lastH = c.maxHeight;
                _lastTop = MediaQuery.of(context).padding.top;
                return _board(c.maxWidth, c.maxHeight);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _board(double W, double H) {
    final g = _geom(W, H);
    final now = DateTime.now().millisecondsSinceEpoch;
    final children = <Widget>[];

    // Halka + kollar: hazır görsel (şekil), altındaki yürüyüş yolu kırpılır.
    children.add(Positioned(
      left: 0,
      right: 0,
      top: g.ringTop,
      height: g.ringH,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          minHeight: 0,
          maxWidth: g.shape.imgW * g.sc,
          maxHeight: g.shape.imgH * g.sc,
          child: Transform.translate(
            offset: Offset(g.imgLeft, 0),
            child: SizedBox(
              width: g.shape.imgW * g.sc,
              height: g.shape.imgH * g.sc,
              child: Image.asset(g.shape.asset, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
            ),
          ),
        ),
      ),
    ));

    // Zemin paneli (UFO ızgarası)
    children.add(Positioned(
      left: g.panelLeft - 6,
      top: g.panelTop - 6,
      width: g.panelW + 12,
      height: g.panelH + 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x8839E6FF), width: 2),
          image: DecorationImage(
            image: const AssetImage('assets/img/floor_tile.webp'),
            repeat: ImageRepeat.repeat,
            scale: 2.2,
            colorFilter: ColorFilter.mode(
              Colors.black.withAlpha(45),
              BlendMode.darken,
            ),
          ),
        ),
      ),
    ));

    // Katman asansörü parıltısı: alt kat yukarı çıkarken tahtanın altından yukarı süzülen ışık.
    children.add(Positioned(
      left: g.panelLeft - 6,
      top: g.panelTop - 6,
      width: g.panelW + 12,
      height: g.panelH + 12,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _clock,
          builder: (context, _) {
            final el = DateTime.now().millisecondsSinceEpoch - _layerFlashMs;
            if (el < 0 || el > 900) return const SizedBox.shrink();
            final f = el / 900.0;
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    const Color(0xFF39E6FF).withAlpha((160 * (1 - f)).round()),
                    const Color(0x0039E6FF),
                  ],
                  stops: [0.0, (0.25 + 0.75 * f).clamp(0.05, 1.0)],
                ),
              ),
            );
          },
        ),
      ),
    ));

    // Dönen halka + beslenme yolu + kapılar + üzerindeki uzaylılar (her karede yenilenir)
    children.add(Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _clock,
          builder: (context, _) => _ringLayer(g),
        ),
      ),
    ));

    // Park yuvaları: açık yuvalar (L4+ ilki VIP, altın) + reklamla açılan kilitli yuvalar.
    final openCount = game.slots.length;
    final lastFree = game.freeSlotCount == 1 && openCount >= 3;
    for (int k = 0; k < g.slotCount; k++) {
      final left = g.slotsLeft + k * g.slotSize;
      if (k >= openCount) {
        children.add(Positioned(
          left: left,
          top: g.padTop,
          width: g.slotSize,
          height: g.slotSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _askUnlockSlot,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: 0.85,
                  child: Image.asset('assets/img/pad_locked.webp',
                      fit: BoxFit.contain),
                ),
                Positioned(
                  bottom: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xCC1B8E3E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('+ ▶',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
        ));
        continue;
      }
      final isFree = game.slots[k] == -1;
      final vip = game.isVipSlot(k);
      Widget pad = Image.asset('assets/img/pad_empty.webp', fit: BoxFit.contain);
      if (vip) {
        // VIP yuva her zaman altın: "son boş yuva" kırmızı uyarısı sadece normal yuvalar için.
        pad = ColorFiltered(
          colorFilter:
              const ColorFilter.mode(Color(0xAAFFC400), BlendMode.srcATop),
          child: pad,
        );
      } else if (lastFree && isFree) {
        pad = ColorFiltered(
          colorFilter:
              const ColorFilter.mode(Color(0xAAFF1744), BlendMode.srcATop),
          child: pad,
        );
      }
      children.add(Positioned(
        left: left,
        top: g.padTop,
        width: g.slotSize,
        height: g.slotSize,
        child: pad,
      ));
      if (vip) {
        children.add(Positioned(
          left: left,
          top: g.padTop + g.slotSize - 14,
          width: g.slotSize,
          child: const IgnorePointer(
            child: Text('VIP',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xFFFFC400),
                    fontSize: 11,
                    fontWeight: FontWeight.w900)),
          ),
        ));
      }
    }

    // Işınlama ışını: havada duran UFO'nun ALTINDAN yuvaya iner; yuvada UFO renginde parıltı olur.
    for (final u in game.ufos) {
      final id = u.spec.id;
      final pend = pending[id] ?? 0;
      if (u.inGrid) continue;
      if (u.departed && pend == 0) continue;
      final size = _hoverSize(g, u.spec.seats);
      final k = max(0, u.lastSlot);
      final cx = _hoverCx(g, k);
      final stand = _padStand(g, k);
      final beamTop = _hoverBottom(g, size) - size * 0.10;
      final beamBottom = stand.dy + g.slotSize * 0.10;
      final beamW = g.slotSize * 0.92;
      final recent = now - (lastBoard[id] ?? 0) < 350;
      final show = landed.contains(id) && (pend > 0 || recent);
      children.add(Positioned(
        key: ValueKey('bg$id'),
        left: cx - g.slotSize * 0.36,
        top: stand.dy - g.slotSize * 0.11,
        width: g.slotSize * 0.72,
        height: g.slotSize * 0.22,
        child: IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: show ? 1.0 : 0.0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kColors[u.spec.color].withAlpha(170),
                    kColors[u.spec.color].withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
      children.add(Positioned(
        key: ValueKey('b$id'),
        left: cx - beamW / 2,
        width: beamW,
        top: beamTop,
        height: max(8.0, beamBottom - beamTop),
        child: IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: show ? 0.85 : 0.0,
            // beam.webp yukarısı dar, aşağısı geniş: UFO'dan yuvaya doğru açılır (döndürmeye gerek yok).
            child: Image.asset('assets/img/beam.webp', fit: BoxFit.fill),
          ),
        ),
      ));
    }

    // Işınlanan uzaylılar: halkadan yuvaya iner, ışında yukarı UFO'ya çıkar.
    // UFO'lardan ÖNCE çizilir: UFO'nun altına girerken gövdenin arkasında kaybolur.
    for (final f in flies) {
      children.add(_flyWidget(f, g.alien));
    }

    // Bantlar: bant UFO'nun altında, yan eksende uzanan konveyör (görsel; çarpışma gövdesi ev konumunda).
    for (final u in game.ufos) {
      if (!u.belt || !u.inGrid || !u.spawned) continue;
      final c = _ufoCenter(g, u.spec);
      final bw = g.unit * 2.8;
      final bh = bw / 3.0;
      children.add(Positioned(
        key: ValueKey('belt${u.spec.id}'),
        left: c.dx - bw / 2,
        top: c.dy - bh / 2,
        width: bw,
        height: bh,
        child: IgnorePointer(
          child: Transform.rotate(
            angle: u.spec.angle,
            child: Image.asset('assets/img/belt.webp', fit: BoxFit.fill),
          ),
        ),
      ));
    }

    // Işınlama kapıları: üst üste doğan UFO'ların çıktığı nokta (portal). Öndeki gidince arkadaki kapıdan belirir.
    game.groups.forEach((gid, members) {
      if (members.length < 2) return;
      if (level.layerOfUfo(members.first) != game.curLayer) return;
      int left = 0;
      int waiting = 0;
      int bigSeats = 4;
      for (final id in members) {
        final mu = game.ufos[id];
        bigSeats = max(bigSeats, mu.spec.seats);
        if (mu.inGrid) {
          left++;
          if (!mu.spawned) waiting++;
        }
      }
      if (left == 0) return;
      final c = _ufoCenter(g, game.ufos[members.first].spec);
      final d = g.unit * ufoDiameter(bigSeats) * g.ufoScale * 1.3;
      children.add(Positioned(
        key: ValueKey('portal$gid'),
        left: c.dx - d / 2,
        top: c.dy - d / 2,
        width: d,
        height: d,
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) {
              final pulse = 0.5 + 0.5 * sin(_clock.value * 2 * pi);
              final fl = portalFlash[gid];
              final fe = fl == null ? 1.0 : ((DateTime.now().millisecondsSinceEpoch - fl) / 700.0).clamp(0.0, 1.0);
              return Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        const Color(0xFF7C4DFF).withAlpha((60 + 50 * pulse).round()),
                        const Color(0xFF39E6FF).withAlpha((70 + 40 * pulse).round()),
                        const Color(0x0039E6FF),
                      ], stops: const [0.0, 0.62, 1.0]),
                      border: Border.all(
                        color: const Color(0xFF39E6FF).withAlpha((150 + 80 * pulse).round()),
                        width: 2,
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                  if (fe < 1.0)
                    Transform.scale(
                      scale: 1.0 + 0.7 * fe,
                      child: Container(
                        width: d,
                        height: d,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withAlpha((220 * (1 - fe)).round()),
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  if (waiting > 0)
                    Positioned(
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5E35B1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: Text('+$waiting',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10, height: 1.2, fontWeight: FontWeight.w900)),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ));
    });

    // UFO'lar
    for (final u in game.ufos) {
      final id = u.spec.id;
      final pend = pending[id] ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final flyAway = u.departed &&
          pend == 0 &&
          nowMs - (lastBoard[id] ?? 0) >= _flyMs + _departWaitMs;
      if (flyAway && !departStart.containsKey(id)) {
        departStart[id] = nowMs;
        Audio.play(Sfx.ufoDepart);
      }
      double size;
      double boxH = 0;
      double box = 0; // dokunma kutusu (sahadaki küçük UFO'lar için size'dan büyük olabilir)
      double left;
      double top;
      double opacity = 1.0;
      if (u.inGrid) {
        if (!u.spawned) continue; // üst üste doğan araçlardan henüz sırası gelmeyen
        size = _gridUfoPx(g, u.spec);
        box = max(size, _minTap);
        boxH = box;
        // Büyütülen düzenlerde dokunma kutusu yassı UFO'ya göre kısaltılır: komşunun kutusuyla çakışıp dokunuşu çalmasın.
        if (_fitFor(g, id) > 1.0) boxH = max(size * _spriteH(u.spec.seats) + 4, _minTap * 0.8);
        final c = _ufoCenter(g, u.spec);
        left = c.dx - box / 2;
        top = c.dy - boxH / 2;
      } else {
        // Yuvaya KONMAZ: yuvanın üstünde havada durur (ışın altından iner).
        final k = max(0, u.lastSlot);
        size = _hoverSize(g, u.spec.seats);
        left = _hoverCx(g, k) - size / 2;
        top = _hoverCy(g, size) - size / 2;
        // Dolan UFO yerinde kalır; çıkış hareketi (önce yukarı, sonra sağa) aşağıda kare kare hesaplanır.
      }
      final double homeLeft = left;
      final double homeSize = size;
      final blocked = u.inGrid && !game.canLaunch(id);
      final hidden = u.spec.mystery && blocked;
      final Widget img = _ufoBody(u, size, blocked, hidden);
      Widget body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTapUfo(id),
        // Sahadaki küçük UFO'larda dokunma alanı görselden geniştir (_minTap).
        child: u.inGrid
            ? SizedBox(
                width: box,
                height: boxH,
                child: OverflowBox(
                  // HATA DÜZELTMESİ: dokunma kutusu _minTap (34) iken size < 34 olunca min > max kısıtı çıkıyor,
                  // 4 koltuklu (küçük) UFO'lar hiç çizilmiyordu. Min kısıtı sıfırlanır.
                  minWidth: 0,
                  minHeight: 0,
                  maxWidth: size,
                  maxHeight: size,
                  child: SizedBox(width: size, height: size, child: img),
                ),
              )
            : img,
      );
      if (u.inGrid) {
        // Kapalı UFO: ok yönünde önündeki araca kadar gidip çarpar, geri döner.
        final unitPx = g.unit;
        final unitPxX = g.unitX;
        final fdx = u.cur.dirX;
        final fdy = u.cur.dirY;
        body = AnimatedBuilder(
          animation: _clock,
          child: body,
          builder: (context, child) {
            final b = bumps[id];
            if (b == null) return child!;
            final el = DateTime.now().millisecondsSinceEpoch - b.startMs;
            if (el >= _bumpMs) return child!;
            final t = el / _bumpMs;
            final f = t < 0.42
                ? Curves.easeOut.transform(t / 0.42)
                : 1.0 - Curves.easeIn.transform((t - 0.42) / 0.58);
            final dist = b.dist * unitPx + unitPx * 0.12;
            return Transform.translate(
              offset: Offset(fdx * (b.dist * unitPxX + unitPx * 0.12) * f, fdy * dist * f),
              child: child,
            );
          },
        );
      }
      if (u.inGrid && u.belt) {
        // Bant UFO bant üstünde yana doğru kayar (bant ekseni = UFO yönüne dik).
        final bu = u;
        final ax = cos(u.spec.angle);
        final ay = sin(u.spec.angle);
        final ampPx = g.unit * 0.9;
        body = AnimatedBuilder(
          animation: _clock,
          child: body,
          builder: (context, child) {
            final p = game.beltPos(bu);
            return Transform.translate(offset: Offset(ax * p * ampPx, ay * p * ampPx), child: child);
          },
        );
      }
      if (!u.inGrid) {
        // Yolcu binerken UFO titrer (biniş bitince titreme yavaşça söner).
        body = AnimatedBuilder(
          animation: _clock,
          child: body,
          builder: (context, child) {
            final t = DateTime.now().millisecondsSinceEpoch;
            double amp = 0.0;
            if (landed.contains(id)) {
              if ((pending[id] ?? 0) > 0) {
                amp = 1.0;
              } else {
                final last = lastBoard[id];
                if (last != null) amp = max(0.0, 1.0 - (t - last) / 320.0);
              }
            }
            final sec = t / 1000.0;
            // Havada süzülme: yuvanın üstünde yavaşça aşağı yukarı sallanır (kalkışa başlayınca durur).
            final hovering = landed.contains(id) && !departStart.containsKey(id);
            final bob = hovering ? sin(sec * 2.4 + id * 1.3) * 2.2 : 0.0;
            if (amp <= 0) {
              return bob == 0.0 ? child! : Transform.translate(offset: Offset(0, bob), child: child);
            }
            return Transform.translate(
              offset: Offset(sin(sec * 62) * 2.6 * amp, cos(sec * 77) * 2.0 * amp + bob),
              child: Transform.rotate(
                angle: sin(sec * 48) * 0.055 * amp,
                child: child,
              ),
            );
          },
        );
      }
      // Topaç gibi kendi etrafında dönüş: kalkışta 1 tur (yavaş), çıkışta 2 tur. Park yerinde sabit durur.
      if (!u.inGrid) {
        body = AnimatedBuilder(
          animation: _clock,
          child: body,
          builder: (context, child) {
            final t = DateTime.now().millisecondsSinceEpoch;
            double ang = 0.0;
            double fade = 0.0;
            final ds = departStart[id];
            final ls = spinStart[id];
            if (ds != null) {
              final f = ((t - ds) / _departMs).clamp(0.0, 1.0);
              if (f < 1.0) {
                ang = 2 * pi * 2 * Curves.easeInOut.transform(f);
                fade = _spinFade(f);
              }
            } else if (ls != null) {
              final f = ((t - ls) / _landMs).clamp(0.0, 1.0);
              if (f < 1.0) {
                ang = 2 * pi * Curves.easeInOut.transform(f);
                fade = _spinFade(f);
              }
            }
            // Çıkış yolu: önce yuvanın üstüne doğru yükselir (komşu UFO'lara çarpmasın), sonra sağa süzülüp çıkar.
            Offset shift = Offset.zero;
            if (ds != null) {
              final f = ((t - ds) / _departMs).clamp(0.0, 1.0);
              final rise = _departRise * homeSize;
              if (f < _departSplit) {
                shift = Offset(0, -rise * Curves.easeOutCubic.transform(f / _departSplit));
              } else {
                final q = ((f - _departSplit) / (1 - _departSplit)).clamp(0.0, 1.0);
                final dx = (g.W + homeSize * 1.5) - homeLeft;
                shift = Offset(dx * Curves.easeInCubic.transform(q), -rise - homeSize * 0.15 * q);
              }
            }
            if (fade <= 0.0) {
              return shift == Offset.zero ? child! : Transform.translate(offset: shift, child: child);
            }
            // Topaç hissi: gövde dönerken hafif daralıp genişler ve sprite şeklinde kesilmiş bir parlama şeridi
            // üzerinden tekrar tekrar geçer (ayrı çizilmiş ışık/kare yok; parlama sadece UFO'nun piksellerinde görünür).
            final p = (ang / (2 * pi) * 3) % 1.0; // tur başına 3 parlama
            final sx = 1.0 - 0.07 * fade * (1 - cos(ang * 3)) / 2;
            final cxp = -1.7 + 3.4 * p;
            return Transform.translate(
              offset: shift,
              child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..scale(sx, 1.0),
              child: ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (b) => LinearGradient(
                  begin: Alignment(cxp - 0.6, -0.5),
                  end: Alignment(cxp + 0.6, 0.5),
                  colors: [
                    const Color(0x00FFFFFF),
                    Colors.white.withAlpha((150 * fade).round()),
                    const Color(0x00FFFFFF),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ).createShader(b),
                child: child,
              ),
            ));
          },
        );
      }
      children.add(AnimatedPositioned(
        key: ValueKey('u$id'),
        duration: Duration(milliseconds: flyAway ? _departMs : (beaming.contains(id) ? _beamMs : _landMs)),
        curve: flyAway ? Curves.easeInCubic : Curves.easeInOutCubic,
        left: left,
        top: top,
        width: u.inGrid ? box : size,
        height: u.inGrid ? boxH : size,
        child: IgnorePointer(
          ignoring: !u.inGrid,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 450),
            opacity: opacity,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 120),
              scale: bouncing.contains(id) ? 1.12 : 1.0,
              // Sahaya ilk kez çıkan (ya da üst üste doğan) UFO küçükten büyüyerek belirir.
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                builder: (context, v, child) => Transform.scale(scale: v, child: child),
                child: body,
              ),
            ),
          ),
        ),
      ));
    }

    // Park yerinin ALTINDA kalan kapasite sayacı (referans gibi): UFO yuvaya yerleşince 16/24/40 yazar,
    // yolcu bindikçe azalır, 0 olunca UFO kalkar. UFO'nun üzerinde sayı yazmaz.
    for (final u in game.ufos) {
      final id = u.spec.id;
      if (u.inGrid || !landed.contains(id)) continue;
      final pend = pending[id] ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final gone = u.departed && pend == 0 && nowMs - (lastBoard[id] ?? 0) >= _flyMs + _departWaitMs;
      if (gone) continue;
      final k = max(0, u.lastSlot);
      final remain = max(0, u.spec.seats - max(0, u.boarded - pend)) * kCapPerPassenger;
      final capFull = u.spec.capacity.toDouble();
      children.add(Positioned(
        key: ValueKey('c$id'),
        left: g.slotsLeft + k * g.slotSize,
        top: g.padTop + g.slotSize - 6,
        width: g.slotSize,
        height: _counterBox - 2,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 0),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(185),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: kColors[u.spec.color], width: 1.5),
              ),
              child: AnimatedBuilder(
                animation: _clock,
                builder: (context, _) => Text(
                  '${(_cnt[id] ?? capFull).ceil().clamp(remain, u.spec.capacity)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
    }

    // Işınla efekti: UFO'nun bulunduğu yerde ve VIP yuvada ışın + parıltı.
    for (final id in beaming) {
      final from = beamFrom[id];
      if (from != null) {
        children.add(Positioned(
          key: ValueKey('bf$id'),
          left: from.dx - 24,
          top: from.dy - 52,
          width: 48,
          height: 78,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.9,
              child: Image.asset('assets/img/beam.webp', fit: BoxFit.fill),
            ),
          ),
        ));
        children.add(Positioned(
          key: ValueKey('bs$id'),
          left: from.dx - 12,
          top: from.dy - 14,
          child: const IgnorePointer(child: Text('✨', style: TextStyle(fontSize: 24))),
        ));
      }
      children.add(Positioned(
        key: ValueKey('bt$id'),
        left: g.slotsLeft + g.slotSize / 2 - g.slotSize * 0.46,
        top: g.slotsTop + g.hoverH * 0.25,
        width: g.slotSize * 0.92,
        height: g.hoverH * 0.75 + g.slotSize * 0.5,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.9,
            child: Image.asset('assets/img/beam.webp', fit: BoxFit.fill),
          ),
        ),
      ));
    }

    // Kaldır seçili: ne yapılacağını göster.
    if (vipArmed) {
      children.add(Positioned(
        left: 0,
        right: 0,
        top: g.slotsTop + g.slotsH + 4,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xEEFFA000),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(L.t('Bir UFO seç → VIP yuvaya ışınlansın', 'Pick a UFO → teleport it to the VIP slot'),
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
          ),
        ),
      ));
    }

    // HUD okunaklı kalsın: üstte hafif koyu degrade
    children.add(Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: g.topInset + g.hudH + 14,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withAlpha(150), Colors.black.withAlpha(0)],
            ),
          ),
        ),
      ),
    ));

    // HUD
    children.add(Positioned(
      left: 0,
      right: 0,
      top: g.topInset,
      height: g.hudH,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  L.t('Seviye ${level.number}${level.isHard ? '  •  ZOR' : ''}',
                      'Level ${level.number}${level.isHard ? '  •  HARD' : ''}'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: level.isHard ? const Color(0xFFFFC400) : Colors.white,
                    fontSize: 20,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (_rulesLine().isNotEmpty)
                  Text(
                    _rulesLine(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: (level.rules.moveBudget > 0 && game.movesLeft <= 3)
                          ? const Color(0xFFFF8A80)
                          : Colors.white70,
                      fontSize: 11.5,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
          Image.asset('assets/img/coin.webp', width: 24, height: 24),
          const SizedBox(width: 4),
          Text(
            '${Progress.coins}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () => setState(() => _load(level.number)),
          ),
        ],
      ),
    ));

    // Mesaj
    if (message != null) {
      children.add(Positioned(
        left: 0,
        right: 0,
        top: g.slotsTop + g.slotsH + 4,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xEE37474F),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              message!,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ));
    }

    // Booster'lar
    children.add(Positioned(
      left: 0,
      right: 0,
      bottom: 6,
      height: g.boostH - 6,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          KeyedSubtree(
            key: _boostKeys[0],
            child: _boosterBtn('assets/img/booster_board.webp', L.t('Hemen Bin', 'Board Now'), _unlockBoard,
                !ended, () {
              if (_newBoost == 0) setState(() => _newBoost = -1);
              _useBoard();
            }, 0, () => _askBooster(0, L.t('Hemen Bin', 'Board Now'))),
          ),
          KeyedSubtree(
            key: _boostKeys[1],
            child: _boosterBtn('assets/img/booster_shuffle.webp', L.t('Karıştır', 'Shuffle'),
                _unlockShuffle, !ended, () {
              if (_newBoost == 1) setState(() => _newBoost = -1);
              _useShuffle();
            }, 1, () => _askBooster(1, L.t('Karıştır', 'Shuffle'))),
          ),
          KeyedSubtree(
            key: _boostKeys[2],
            child: _boosterBtn('assets/img/booster_vip.webp', vipArmed ? L.t('Seç…', 'Pick…') : L.t('Işınla', 'Teleport'),
                _unlockVip, !ended, () {
              if (_newBoost == 2) setState(() => _newBoost = -1);
              _useVip();
            }, 2, () => _askBooster(2, L.t('Işınla', 'Teleport'))),
          ),
        ],
      ),
    ));

    children.add(_tutLayer(g, W, H));

    return SizedBox(
      key: _boardKey,
      width: W,
      height: H,
      child: Stack(children: children),
    );
  }

  /// Halka yolu, beslenme yolu, kapılar ve üzerinde dönen/bekleyen uzaylılar.
  Widget _ringLayer(_G g) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final n = game.slots.length;
    final gateColors = List<Color?>.filled(n, null);
    final gateGlow = List<double>.filled(n, 0.0);
    for (int k = 0; k < n; k++) {
      final id = game.slots[k];
      if (id >= 0 && !game.ufos[id].departed) gateColors[k] = kColors[game.ufos[id].spec.color];
      final ft = gateFlash[k];
      if (ft != null) gateGlow[k] = max(0.0, 1.0 - (now - ft) / 350.0);
    }

    final kids = <Widget>[
      Positioned.fill(
        child: CustomPaint(
          painter: _RingPainter(
            g: g,
            phase: game.phase,
            gates: gateColors,
            glow: gateGlow,
          ),
        ),
      ),
    ];

    // Yolcular "mısır tanesi" gibi sık dizilir: her yolcu birimi (1 hücre) ardışık küçük uzaylılardan oluşur,
    // aynı renkli birimler yan yana blok olur. Hepsi tek CustomPaint ile çizilir (hızlı).
    final dots = <_Dot>[];
    final ks = g.alien * (_kernelSize / 20.0);

    // Kollarda bekleyen yolcular: sol kol çift sıralı, sağ kol tek sıralı yolcuları taşır.
    // Sıranın başı halkaya giriş noktasına yakındır; biri girince kol yumuşakça ilerler.
    for (int a = 0; a < 2; a++) {
      final taken = _armTaken(a);
      final totalLen = g.armCum[a].last;
      final armDots = <_Dot>[];
      for (int j = 0; j < _armRows * _armLanes + 3; j++) {
        if (taken + j >= game.armQ[a].length) break;
        final pos = j + (taken - _armVis[a]);
        final q = g.armWait + (pos / _armLanes) * _armGap * g.k;
        if (q > totalLen) break;
        final lane = (taken + j) % _armLanes;
        final off = (lane - (_armLanes - 1) / 2) * _armLaneGap * g.k;
        final color = game.armQ[a][taken + j];
        for (int k = 0; k < _kernels; k++) {
          final dq = (k - (_kernels - 1) / 2) * (_armGap * g.k / (_kernels * 2.0));
          final pt = _armPoint(g, a, q + dq, off);
          armDots.add(_Dot(pt.dx, pt.dy, ks * 0.9, color, 1.0));
        }
      }
      // Uzaktan yakına (girişe doğru) çiz.
      dots.addAll(armDots.reversed);
    }

    // Halkadaki yolcular (arkadakiler önce çizilsin: y'ye göre sırala).
    final ringDots = <_Dot>[];
    final cols = game.ringCols;
    for (int i = 0; i < game.cells.length; i++) {
      final p = game.cells[i];
      if (p == null) continue;
      final born = birth.putIfAbsent(p.id, () => now);
      final age = now - born;
      final fade = (age / 250.0).clamp(0.0, 1.0);
      for (int k = 0; k < _kernels; k++) {
        final ds = (k - (_kernels - 1) / 2) * (0.5 / cols);
        final pp = _pathAt(g, game.cellS(i) + ds);
        final lo = ((i % kRingLanes) - (kRingLanes - 1) / 2) * max(pp.gap, 4.0);
        Offset pt = Offset(pp.x + pp.nx * lo, pp.y + pp.ny * lo);
        if (age < 260) {
          // Yeni giren yolcu, kolda beklediği yerden halkadaki hücresine atlar.
          final from = _armPoint(g, p.id % 2, g.armWait, 0);
          final e = Curves.easeOut.transform(age / 260.0);
          pt = Offset(from.dx + (pt.dx - from.dx) * e, from.dy + (pt.dy - from.dy) * e);
        }
        // Perspektif: öndeki (aşağıdaki) uzaylı biraz büyük.
        final depth = ((pt.dy - (g.cy - g.r)) / (2 * g.r)).clamp(0.0, 1.0);
        ringDots.add(_Dot(pt.dx, pt.dy, ks * (0.92 + 0.16 * depth) * (0.6 + 0.4 * fade), p.color, 1.0));
      }
    }
    ringDots.sort((a, b) => a.y.compareTo(b.y));
    dots.addAll(ringDots);
    kids.add(Positioned.fill(
      child: IgnorePointer(child: CustomPaint(painter: _PaxPainter(dots, _alienImgs))),
    ));
    return Stack(children: kids);
  }

  /// Biniş: yolcu birimi (2 küçük uzaylı) kapıdan park yerine KOŞAR (zıplayarak, hafif yalpalayarak),
  /// sonra ışına girip UFO'ya çıkar.
  Widget _flyWidget(_Fly f, double alien) {
    final mini = alien * (_kernelSize / 20.0) * 1.1;
    return Positioned.fill(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          key: ValueKey('fly${f.id}'),
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: _flyMs),
          builder: (context, t, _) {
            final kids = <Widget>[];
            for (int k = _kernels - 1; k >= 0; k--) {
              final delay = 0.16 * k;
              final tt = ((t - delay) / (1.0 - delay)).clamp(0.0, 1.0);
              final lat = (k - (_kernels - 1) / 2) * 9.0;
              double x, y, size, op, tilt = 0.0;
              if (tt < _walkFrac) {
                // 1) Kapıdan park yerine koşar.
                final w = Curves.easeIn.transform(tt / _walkFrac) * 0.35 + (tt / _walkFrac) * 0.65;
                final side = f.fx <= f.px ? -1.0 : 1.0;
                final step = sin(w * pi * 7);
                x = f.fx + (f.px - f.fx) * w + side * sin(w * pi) * 6 + lat * (1.0 - 0.6 * w);
                y = f.fy + (f.py - f.fy) * w - step.abs() * 4.0;
                tilt = step * 0.2;
                size = mini * (1.0 - 0.06 * w);
                op = 1.0;
              } else {
                // 2) Yuvada ışına girer ve ışınlanarak UFO'nun altına yükselir.
                final b = Curves.easeIn.transform((tt - _walkFrac) / (1.0 - _walkFrac));
                x = f.px + lat * 0.4 * (1.0 - b) + (f.tx - f.px) * b;
                y = f.py + (f.ty - f.py) * b;
                size = max(7.0, mini * 0.95 * (1.0 - 0.5 * b));
                op = 1.0 - 0.3 * b;
              }
              kids.add(Positioned(
                left: x - size / 2,
                top: y - size * 0.62,
                width: size,
                height: size,
                child: Opacity(
                  opacity: op,
                  child: Transform.rotate(
                    angle: tilt,
                    child: Image.asset(
                      'assets/img/alien_${kColorNames[f.color]}.webp',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ));
            }
            return Stack(children: kids);
          },
        ),
      ),
    );
  }

  /// UFO görseli. Üzerinde kapasite YAZMAZ (referans gibi): sayaç park yerine inince yuvanın altında görünür.
  /// Sahadayken yön oku, UFO'nun baktığı tarafta durur.
  /// Dönen UFO'nun oku/halkası her karede güncellenir; diğerleri sadece setState ile.
  Widget _ufoBody(UfoState u, double size, bool blocked, bool hidden) {
    if ((u.rotor || u.belt) && u.inGrid) {
      return AnimatedBuilder(
        animation: _clock,
        builder: (context, _) => _ufoBodyInner(u, size, blocked, hidden),
      );
    }
    return _ufoBodyInner(u, size, blocked, hidden);
  }

  Widget _ufoBodyInner(UfoState u, double size, bool blocked, bool hidden) {
    final name = kColorNames[u.spec.color];
    final arrowSize = max(13.0, size * (hidden ? 0.3 : 0.44));
    Widget img = Image.asset(
      'assets/img/ufo${_ufoClass(u.spec.seats)}_$name.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
    if (hidden) {
      // Gizemli UFO (önü kapalıyken): koyu/siyah, ortada büyük beyaz "?" (referans gibi).
      img = ColorFiltered(colorFilter: _mysteryFilter, child: img);
    }
    double a = u.cur.angle;
    if (u.rotor) {
      // Yön değişince ok yarım tur yumuşakça döner.
      final since = game.clock - u.flipClock;
      if (since >= 0 && since < 0.35) {
        a = u.cur.angle - pi * (1 - Curves.easeOut.transform(since / 0.35));
      }
    }
    final warn = u.rotor && u.inGrid && game.rotTimeLeft(u) < 0.7;
    final blink = warn && sin(game.clock * 20) > 0;
    // Yön oku: normalde UFO'nun üstünde, gizemlide küçük ve kenarda (ortadaki "?" kapanmasın).
    final arrowAt = hidden ? 0.72 : 0.5;
    return Stack(
      alignment: Alignment.center,
      children: [
        img,
        if (u.rotor && u.inGrid)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: blink ? const Color(0xFFFFC400) : const Color(0xFF40C4FF),
                width: 2.5,
              ),
            ),
          ),
        if (u.belt && u.inGrid)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: game.beltOpen(u) ? const Color(0xFF69F0AE) : const Color(0x66FFFFFF),
                width: game.beltOpen(u) ? 3.0 : 1.5,
              ),
            ),
          ),
        if (u.inGrid)
          Align(
            alignment: Alignment(sin(a) * arrowAt, -cos(a) * arrowAt),
            child: Container(
              width: arrowSize,
              height: arrowSize,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(235),
                shape: BoxShape.circle,
                border: Border.all(
                  color: hidden ? Colors.grey : kColors[u.spec.color],
                  width: 2,
                ),
              ),
              child: Transform.rotate(
                angle: a,
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: arrowSize * 0.74,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        if (u.faulty && u.inGrid)
          Align(
            alignment: const Alignment(0.85, -0.9),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
              decoration: BoxDecoration(
                color: u.fault <= 3 ? const Color(0xFFD32F2F) : const Color(0xFFEF6C00),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              child: Text(
                '🔧${u.fault}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: max(9.0, size * 0.27),
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        // "?" en üstte çizilir (ok kapatmasın).
        if (hidden)
          Align(
            alignment: const Alignment(0, -0.1),
            child: Text(
              '?',
              style: TextStyle(
                color: Colors.white,
                fontSize: max(18.0, size * 0.62),
                height: 1.0,
                fontWeight: FontWeight.w900,
                shadows: const [
                  Shadow(blurRadius: 4, color: Colors.black),
                  Shadow(blurRadius: 10, color: Colors.black),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _boosterBtn(String asset, String label, int unlockLevel, bool enabled,
      VoidCallback onTap, int stockIdx, [VoidCallback? onPlus]) {
    final locked = level.number < unlockLevel;
    final stock = Progress.boostStock[stockIdx];
    final glow = _newBoost == stockIdx && !locked;
    final pulse = 0.5 + 0.5 * sin(_clock.value * 2 * pi);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: (enabled && !locked) ? 1.0 : 0.4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 58,
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: glow
                        ? BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withAlpha((140 + 100 * pulse).round()),
                                blurRadius: 12 + 10 * pulse,
                                spreadRadius: 2 + 3 * pulse,
                              ),
                            ],
                          )
                        : null,
                    child: Image.asset(asset, width: 46, height: 46),
                  ),
                  if (locked)
                    const Icon(Icons.lock_rounded, color: Colors.white, size: 22),
                  if (!locked)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: stock > 0
                          ? Container(
                              constraints: const BoxConstraints(minWidth: 20),
                              height: 20,
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE53935),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: Text('$stock',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900)),
                            )
                          : const SizedBox.shrink(),
                    ),
                  // "+": stok kaç olursa olsun reklam / coin ile al penceresini açar.
                  if (!locked && onPlus != null)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onPlus,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E9E4F),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 17),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              locked ? L.t('Sv $unlockLevel', 'Lv $unlockLevel') : label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Çizilecek tek bir küçük uzaylı (halka / kol).
class _Dot {
  final double x;
  final double y;
  final double size;
  final int color;
  final double op;
  const _Dot(this.x, this.y, this.size, this.color, this.op);
}

/// Tüm bekleyen yolcuları tek geçişte çizer (yüzlerce Image widget'ı yerine).
class _PaxPainter extends CustomPainter {
  final List<_Dot> dots;
  final Map<int, ui.Image> imgs;
  _PaxPainter(this.dots, this.imgs);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final d in dots) {
      final im = imgs[d.color];
      if (im == null) continue;
      final src = Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble());
      final dst = Rect.fromLTWH(d.x - d.size / 2, d.y - d.size * 0.62, d.size, d.size);
      paint.color = Color.fromRGBO(255, 255, 255, d.op);
      canvas.drawImageRect(im, src, dst, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaxPainter old) => true;
}

/// Stadyum yolu: koyu zemin, neon kenarlar, akış okları, beslenme yolu,
/// park yerlerinin kapıları ve giriş kapısı.
class _RingPainter extends CustomPainter {
  final _G g;
  final double phase;
  final List<Color?> gates;
  final List<double> glow;

  _RingPainter({
    required this.g,
    required this.phase,
    required this.gates,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Halka, kollar ve yol görseli arka planda hazır (ring_shapes.dart); burada sadece park yeri kapıları çizilir.
    final half = g.roadW / 2 + 2;

    // Park yeri kapıları: yolcu bu çizgiden geçerken UFO'ya biner.
    final n = gates.length;
    for (int k = 0; k < n; k++) {
      final p = _pathAt(g, gateS(k, n));
      final a = Offset(p.x - p.nx * half, p.y - p.ny * half);
      final b = Offset(p.x + p.nx * half, p.y + p.ny * half);
      final c = gates[k];
      final f = glow[k];
      if (c != null && f > 0) {
        canvas.drawLine(
          a,
          b,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9 + 6 * f
            ..strokeCap = StrokeCap.round
            ..color = c.withAlpha((90 * f).round())
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
      canvas.drawLine(
        a,
        b,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = c != null ? 3.5 : 2
          ..strokeCap = StrokeCap.round
          ..color = c != null ? c.withAlpha(235) : const Color(0x44FFFFFF),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => true;
}
