import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../legal.dart';
import 'home_screen.dart';
import 'legal_dialog.dart';

/// 3 saniyelik açılış ekranı. Geçilemez: dokunma yok, atlama düğmesi yok;
/// süre dolunca kendiliğinden HomeScreen'e yumuşakça geçer.
///
/// Sahne: başlık iner -> büyük UFO yukarıdan süzülür -> ışın açılır ->
/// renkli yolcular sırayla ışında yukarı çekilip UFO'ya biner -> yükleme çubuğu dolar.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const Duration _total = Duration(milliseconds: 3000);

  /// Işığa binen yolcuların renkleri (sırayla).
  static const List<String> _aliens = ['green', 'pink', 'orange', 'yellow', 'lightblue', 'purple'];

  static const String _bg = 'assets/img/bg_station.webp';
  static const String _mainUfo = 'assets/img/ufo10_blue.webp';
  static const String _beam = 'assets/img/beam.webp';

  late final AnimationController _c;
  bool _precached = false;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _total)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _goHome();
      })
      ..forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    final paths = <String>[
      _bg,
      _mainUfo,
      _beam,
      'assets/img/ufo4_pink.webp',
      'assets/img/ufo4_yellow.webp',
      for (final a in _aliens) 'assets/img/alien_$a.webp',
    ];
    for (final p in paths) {
      precacheImage(AssetImage(p), context).catchError((Object _) {});
    }
  }

  Future<void> _goHome() async {
    if (_left || !mounted) return;
    _left = true;
    // İlk açılış: Kullanım Şartları + Gizlilik onayı. Kabul edilmeden oyuna girilmez; reddedilirse oyun kapanır.
    if (!Legal.accepted) {
      final ok = await showLegalConsent(context);
      if (!ok || !mounted) return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// [a,b] aralığında 0..1 ilerleme (eğri uygulanmış).
  static double _seg(double t, double a, double b, [Curve curve = Curves.linear]) {
    final x = ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();
    return curve.transform(x);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0620),
      // Hiçbir dokunma/hareket sahneye ulaşmaz: ekran geçilemez.
      body: AbsorbPointer(
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final h = box.maxHeight;
            return AnimatedBuilder(
              animation: _c,
              builder: (context, _) => _scene(w, h, _c.value),
            );
          },
        ),
      ),
    );
  }

  Widget _scene(double W, double H, double t) {
    // ---- yerleşim ----
    final ufoW = W * 0.62;
    final ufoH = ufoW * 233 / 256;
    final ufoRestTop = H * 0.20;

    // UFO girişi (üstten süzülür, hafif geri tepme).
    final enter = _seg(t, 0.0, 0.30, Curves.easeOutBack);
    final bobAmp = H * 0.008 * _seg(t, 0.30, 0.42);
    final ufoTop = _lerp(-ufoH, ufoRestTop, enter) + math.sin(t * math.pi * 2 * 3) * bobAmp;
    final ufoTilt = math.sin(t * math.pi * 2 * 2.5) * 0.035 * _seg(t, 0.2, 0.35);

    // Yolcu biniş vuruşları: UFO her yolcuda hafifçe şişer.
    final aw0 = H * 0.085 * 203 / 256;
    final ah0 = H * 0.085;
    final floorY = H * 0.80; // yolcuların ayak hizası
    final targetX = W / 2;
    final targetY = ufoRestTop + ufoH * 0.55;
    var pulse = 0.0;
    for (int i = 0; i < _aliens.length; i++) {
      final rs = 0.38 + 0.065 * i;
      pulse += math.sin(_seg(t, rs + 0.15, rs + 0.21) * math.pi) * 0.022;
    }

    // Işın.
    final beamOp = _seg(t, 0.30, 0.46) * (0.82 + 0.10 * math.sin(t * math.pi * 2 * 5));
    final beamTop = ufoRestTop + ufoH * 0.74;
    final beamH = floorY - beamTop + H * 0.02;
    final beamW = W * 0.62;

    // Başlık.
    final titleOp = _seg(t, 0.12, 0.32);
    final titleSc = _lerp(0.65, 1.0, _seg(t, 0.12, 0.40, Curves.easeOutBack));

    final children = <Widget>[
      // Arka plan + karartma.
      Positioned.fill(child: Image.asset(_bg, fit: BoxFit.cover)),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withAlpha(120),
                Colors.black.withAlpha(30),
                Colors.black.withAlpha(130),
              ],
            ),
          ),
        ),
      ),

      // Arkada uçan küçük UFO'lar.
      _flyer('assets/img/ufo4_pink.webp', W, H, t, w: W * 0.20, y: H * 0.47, leftToRight: true, phase: 0.0),
      _flyer('assets/img/ufo4_yellow.webp', W, H, t, w: W * 0.15, y: H * 0.585, leftToRight: false, phase: 1.7),

      // Başlık.
      Positioned(
        left: 0,
        right: 0,
        top: H * 0.075,
        child: Opacity(
          opacity: titleOp,
          child: Transform.scale(
            scale: titleSc,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'UFO BUS JAM',
                    style: TextStyle(
                      fontSize: math.min(W * 0.105, 46.0),
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 2,
                      shadows: const [
                        Shadow(blurRadius: 18, color: Color(0xFF7C4DFF)),
                        Shadow(blurRadius: 4, color: Color(0xAA000000), offset: Offset(0, 3)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),

      // Işın (UFO'nun altından yere doğru açılır).
      Positioned(
        left: (W - beamW) / 2,
        top: beamTop,
        width: beamW,
        height: beamH,
        child: Opacity(opacity: beamOp.clamp(0.0, 1.0).toDouble(), child: Image.asset(_beam, fit: BoxFit.fill)),
      ),

      // Yerdeki ve yükselen yolcular.
      for (int i = 0; i < _aliens.length; i++) _alien(i, W, t, aw0, ah0, floorY, targetX, targetY),

      // Ana UFO.
      Positioned(
        left: (W - ufoW) / 2,
        top: ufoTop,
        width: ufoW,
        height: ufoH,
        child: Transform.rotate(
          angle: ufoTilt,
          child: Transform.scale(scale: 1.0 + pulse, child: Image.asset(_mainUfo, fit: BoxFit.contain)),
        ),
      ),

      // Yükleme çubuğu.
      Positioned(
        left: 0,
        right: 0,
        bottom: H * 0.07,
        child: Opacity(opacity: _seg(t, 0.05, 0.2), child: _progress(W, t)),
      ),
    ];

    return Stack(fit: StackFit.expand, children: children);
  }

  /// Arka planda yatay süzülen küçük UFO.
  Widget _flyer(String asset, double W, double H, double t,
      {required double w, required double y, required bool leftToRight, required double phase}) {
    final h = w * 170 / 256; // ufo4 oranı
    final p = _seg(t, 0.0, 1.0);
    final x = leftToRight ? _lerp(-w, W + w * 0.2, p) : _lerp(W + w * 0.2, -w, p);
    final bob = math.sin(t * math.pi * 2 * 2 + phase) * H * 0.01;
    return Positioned(
      left: x,
      top: y + bob,
      width: w,
      height: h,
      child: Opacity(opacity: 0.92, child: Image.asset(asset, fit: BoxFit.contain)),
    );
  }

  /// i'inci yolcu: yerde belirir, zıplar, sırası gelince ışında UFO'ya çekilir.
  Widget _alien(int i, double W, double t, double aw0, double ah0, double floorY, double targetX, double targetY) {
    final n = _aliens.length;
    final slotX = W * (0.14 + (0.72 / (n - 1)) * i);
    final popAt = 0.20 + 0.03 * i;
    final pop = _seg(t, popAt, popAt + 0.08, Curves.easeOutBack);
    final rs = 0.38 + 0.065 * i;
    final rise = _seg(t, rs, rs + 0.19);

    double cx = slotX;
    double cy = floorY - ah0 / 2;
    double scale = pop;
    double opacity = _seg(t, popAt, popAt + 0.04);
    double angle = 0;

    if (rise <= 0) {
      // Bekleme: hafif zıplama.
      final hop = (math.sin((t * 7 + i * 0.9) * math.pi)).abs() * ah0 * 0.10 * pop;
      cy -= hop;
    } else {
      final side = (slotX < W / 2) ? 1.0 : -1.0;
      final e = Curves.easeInOut.transform(rise);
      cx = _lerp(slotX, targetX, e) + math.sin(rise * math.pi) * W * 0.05 * -side;
      cy = _lerp(floorY - ah0 / 2, targetY, Curves.easeIn.transform(rise));
      scale = _lerp(1.0, 0.25, Curves.easeIn.transform(rise));
      opacity = 1.0 - _seg(rise, 0.82, 1.0);
      angle = math.sin(rise * math.pi * 3) * 0.28;
    }

    return Positioned(
      left: cx - aw0 / 2,
      top: cy - ah0 / 2,
      width: aw0,
      height: ah0,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0).toDouble(),
        child: Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: scale.clamp(0.0, 2.0).toDouble(),
            child: Image.asset('assets/img/alien_${_aliens[i]}.webp', fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Widget _progress(double W, double t) {
    final barW = W * 0.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Yükleniyor...',
          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        Container(
          width: barW,
          height: 9,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(40),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withAlpha(60)),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: t.clamp(0.0, 1.0).toDouble(),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF18FFFF)]),
                boxShadow: const [BoxShadow(color: Color(0xFF7C4DFF), blurRadius: 8)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
