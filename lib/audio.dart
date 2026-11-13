import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import 'settings.dart';

/// Arka plan müzikleri (assets/audio/bgm_main.mp3, kesintisiz döngü).
/// Menü ve oyun aynı dosyayı paylaşır: ekran değişince müzik baştan başlamaz, devam eder.
enum MusicTrack { menu, game }

/// Ses efektleri (assets/audio/*.mp3 / *.wav).
enum Sfx {
  ufoCall, // geçerli dokunuş: UFO yuvaya uçar
  beam1, // yolcu ışınlandı (3 ton, sırayla değişir)
  beam2,
  beam3,
  ufoBlocked, // önü kapalı UFO'ya dokunuldu
  ufoFull, // UFO doldu
  ufoDepart, // dolan UFO sağdan uçup gider
  vipTeleport, // Işınla (VIP yuva)
  shuffle, // Karıştır
  boosterBoard, // Hemen Bin
  layerUp, // katman asansörü
  ufoBreak, // arızalı UFO bozuldu
  ufoRepair, // tamir edildi
  win,
  lose,
  click,
  coin,
  portalSpawn, // ışınlama kapısından yeni UFO
  levelStart,
  warn,
}

class _Def {
  final String file;
  final int pool; // aynı anda üst üste çalabilecek kopya sayısı
  final bool low; // kısa sesler: düşük gecikmeli mod
  final int gapMs; // arka arkaya çalmayı sınırlar
  final double vol;
  const _Def(this.file, {this.pool = 2, this.low = true, this.gapMs = 0, this.vol = 1.0});
}

const Map<Sfx, _Def> _defs = <Sfx, _Def>{
  Sfx.ufoCall: _Def('ufo_swoosh.mp3', pool: 3, vol: 0.9),
  Sfx.beam1: _Def('beam_pop_1.mp3', pool: 5, vol: 0.85),
  Sfx.beam2: _Def('beam_pop_2.mp3', pool: 5, vol: 0.85),
  Sfx.beam3: _Def('beam_pop_3.mp3', pool: 5, vol: 0.85),
  Sfx.ufoBlocked: _Def('error_buzz.mp3', gapMs: 120, vol: 0.75),
  Sfx.ufoFull: _Def('ufo_full.wav', vol: 0.9),
  Sfx.ufoDepart: _Def('ufo_fly.mp3', pool: 4, vol: 1.0),
  Sfx.vipTeleport: _Def('teleport.mp3', low: false, vol: 1.0),
  Sfx.shuffle: _Def('shuffle.wav'),
  Sfx.boosterBoard: _Def('booster_board.wav'),
  Sfx.layerUp: _Def('layer_up.wav', low: false),
  Sfx.ufoBreak: _Def('ufo_break.wav'),
  Sfx.ufoRepair: _Def('ufo_repair.wav'),
  Sfx.win: _Def('level_complete.mp3', pool: 1, low: false, vol: 1.0),
  Sfx.lose: _Def('lose.wav', pool: 1, low: false, vol: 0.95),
  Sfx.click: _Def('ui_button.mp3', pool: 2, gapMs: 40, vol: 1.0),
  Sfx.coin: _Def('coin.mp3', pool: 2, gapMs: 60, vol: 0.9),
  Sfx.portalSpawn: _Def('teleport.mp3', low: false, gapMs: 150, vol: 0.6),
  Sfx.levelStart: _Def('level_start.wav', pool: 1, low: false, vol: 0.85),
  Sfx.warn: _Def('warn.wav', gapMs: 150, vol: 0.8),
};

const Map<MusicTrack, String> _musicFiles = <MusicTrack, String>{
  MusicTrack.menu: 'bgm_main.mp3',
  MusicTrack.game: 'bgm_main.mp3',
};

/// Müzik ve ses efekti sistemi. Ayarlardaki Müzik / Ses Efektleri anahtarlarına bağlıdır.
///
/// Kullanım:
///   await Audio.init();                 // main()'de bir kez
///   Audio.music(MusicTrack.game);       // müziği değiştir (null = sustur)
///   Audio.play(Sfx.ufoCall);            // efekt çal
///   Audio.refresh();                    // Ayarlar'da anahtar değişince
class Audio with WidgetsBindingObserver {
  Audio._();
  static final Audio _i = Audio._();

  // Müzik efektleri bastırmasın diye kısık.
  static const double _volMenu = 0.30;
  static const double _volGame = 0.26;
  static const int _duckFadeOutMs = 160; // jingle başlarken müzik hızla söner
  static const int _duckFadeInMs = 900; // jingle bitince müzik yumuşakça geri gelir

  /// MEDYA ses kanalı: eskiden respectSilence:true idi, Android'de bu 'bildirim zili' kanalına düşüp
  /// sesleri bildirim ses seviyesinden çaldırıyordu. false = medya (müzik) kanalı + diğer seslerle karışır.
  static final AudioContext _ctx = AudioContextConfig(
    respectSilence: false,
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  bool _ready = false;
  bool _bg = false; // uygulama arka planda
  AudioPlayer? _music;
  MusicTrack? _wanted;
  MusicTrack? _loaded;
  String? _loadedFile; // menü ve oyun aynı dosyayı kullanınca parça değişiminde müzik kesilmesin
  bool _running = false;
  bool _syncing = false;
  bool _dirty = false;
  Timer? _duckTimer;
  Timer? _fadeTimer;
  bool _ducked = false; // kazanma/kaybetme jingle'ı sürerken müzik tamamen susar
  double _curVol = 0.0;

  final Map<Sfx, List<AudioPlayer>> _pools = <Sfx, List<AudioPlayer>>{};
  final Map<Sfx, int> _next = <Sfx, int>{};
  final Map<Sfx, int> _last = <Sfx, int>{};
  int _beamIdx = 0;
  int _beamLast = 0;

  // ------------------------------------------------------------ genel arayüz

  static Future<void> init() async {
    if (_i._ready) return;
    _i._ready = true;
    WidgetsBinding.instance.addObserver(_i);
    try {
      await AudioPlayer.global.setAudioContext(_ctx);
    } catch (_) {}
    final m = AudioPlayer();
    _i._music = m;
    try {
      await m.setAudioContext(_ctx);
    } catch (_) {}
    unawaited(_i._buildAll());
  }

  /// Çalacak müziği seçer (null: müziği durdur). Ayar kapalıysa çalmaz.
  static void music(MusicTrack? t) {
    _i._wanted = t;
    unawaited(_i._sync());
  }

  /// Ayarlar'da Müzik / Ses Efektleri değişince çağır.
  static void refresh() {
    unawaited(_i._sync());
  }

  static void play(Sfx s) => _i._playSfx(s);

  /// Yolcu ışınlanma sesi: 3 tonu sırayla çalar (art arda binişte melodik duyulur).
  static void beam() {
    if (!Settings.sfx) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // 1 sn'den uzun aradan sonra diziyi başa al.
    if (now - _i._beamLast > 1000) _i._beamIdx = 0;
    _i._beamLast = now;
    const seq = <Sfx>[Sfx.beam1, Sfx.beam2, Sfx.beam3, Sfx.beam2];
    _i._playSfx(seq[_i._beamIdx % seq.length]);
    _i._beamIdx++;
  }

  /// Kazanma/kaybetme jingle'ı çalarken arka plan müziğini TAMAMEN susturur, [ms] sonra yumuşakça geri getirir.
  /// Jingle'ı çalmadan ÖNCE çağır (müzik sönerken jingle başlasın).
  static void duckMusic(int ms) {
    _i._ducked = true;
    _i._duckTimer?.cancel();
    _i._fadeMusic(0.0, _duckFadeOutMs);
    _i._duckTimer = Timer(Duration(milliseconds: ms), () {
      _i._ducked = false;
      _i._fadeMusic(_i._volFor(_i._loaded), _duckFadeInMs);
    });
  }

  // ------------------------------------------------------------ yaşam döngüsü

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bg = state != AppLifecycleState.resumed;
    if (bg == _bg) return;
    _bg = bg;
    unawaited(_sync());
  }

  // ------------------------------------------------------------ iç işler

  /// Tüm efekt havuzlarını (hazır yüklenmiş oynatıcılar) arka planda sırayla kurar.
  Future<void> _buildAll() async {
    for (final s in Sfx.values) {
      await _ensurePool(s);
    }
  }

  final Map<Sfx, Future<List<AudioPlayer>>> _building = <Sfx, Future<List<AudioPlayer>>>{};

  Future<List<AudioPlayer>> _ensurePool(Sfx s) {
    return _building.putIfAbsent(s, () async {
      final d = _defs[s]!;
      final list = <AudioPlayer>[];
      for (int i = 0; i < d.pool; i++) {
        final p = AudioPlayer();
        try {
          await p.setPlayerMode(PlayerMode.mediaPlayer);
          await p.setReleaseMode(ReleaseMode.stop); // bitince kaynak yüklü kalır, tekrar çalınabilir
          await p.setAudioContext(_ctx);
          await p.setVolume(d.vol);
          await p.setSource(AssetSource('audio/${d.file}'));
        } catch (_) {}
        list.add(p);
      }
      _pools[s] = list;
      return list;
    });
  }

  double _volFor(MusicTrack? t) => t == MusicTrack.game ? _volGame : _volMenu;

  double _musicVolNow(MusicTrack? t) => _ducked ? 0.0 : _volFor(t);

  /// Müzik ses seviyesini [to] değerine [ms] içinde doğrusal olarak götürür.
  void _fadeMusic(double to, int ms) {
    _fadeTimer?.cancel();
    final m = _music;
    if (m == null || !_running) {
      _curVol = to; // çalmıyorsa devam edince _sync doğru seviyeyi uygular
      return;
    }
    final from = _curVol;
    const stepMs = 40;
    final steps = (ms / stepMs).ceil().clamp(1, 100);
    int k = 0;
    _fadeTimer = Timer.periodic(const Duration(milliseconds: stepMs), (t) {
      k++;
      final v = k >= steps ? to : from + (to - from) * (k / steps);
      _curVol = v;
      m.setVolume(v.clamp(0.0, 1.0)).catchError((Object _) {});
      if (k >= steps) t.cancel();
    });
  }

  /// İstenen müzik durumunu (çal / duraklat / parça değiştir) gerçeğe uygular.
  Future<void> _sync() async {
    if (_music == null) return;
    if (_syncing) {
      _dirty = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _dirty = false;
        final m = _music!;
        final want = (Settings.music && !_bg) ? _wanted : null;
        try {
          if (want == null) {
            if (_running) {
              await m.pause();
              _running = false;
            }
          } else if (_musicFiles[want] == _loadedFile) {
            if (!_running) {
              _fadeTimer?.cancel();
              await m.resume();
              _running = true;
              _curVol = _musicVolNow(want); // jingle sırasında arka plandan dönülürse müzik sessiz kalsın
              await m.setVolume(_curVol);
            }
            if (want != _loaded) {
              _loaded = want; // aynı dosya, sadece seviyeyi güncelle
              _curVol = _musicVolNow(want);
              await m.setVolume(_curVol);
            }
          } else {
            await m.stop();
            await m.setReleaseMode(ReleaseMode.loop);
            _fadeTimer?.cancel();
            _curVol = _musicVolNow(want);
            await m.play(AssetSource('audio/${_musicFiles[want]}'), volume: _curVol);
            _loaded = want;
            _loadedFile = _musicFiles[want];
            _running = true;
          }
        } catch (_) {}
      } while (_dirty);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _fire(AudioPlayer p) async {
    try {
      await p.seek(Duration.zero);
      await p.resume();
    } catch (_) {
      // Oynatıcı bozulduysa kaynağı yeniden yükleyip bir kez daha dene.
    }
  }

  void _playSfx(Sfx s) {
    if (!Settings.sfx || !_ready) return;
    final d = _defs[s];
    if (d == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (d.gapMs > 0 && now - (_last[s] ?? 0) < d.gapMs) return;
    _last[s] = now;
    final list = _pools[s];
    if (list == null || list.isEmpty) {
      _ensurePool(s); // henüz hazır değil (uygulama yeni açıldı): hazırlanmaya başlasın
      return;
    }
    final idx = (_next[s] ?? 0) % list.length;
    _next[s] = idx + 1;
    unawaited(_fire(list[idx]));
  }
}
