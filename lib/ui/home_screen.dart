import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio.dart';
import '../progress.dart';
import 'game_popup.dart';
import 'game_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  static const double _tau = 2 * math.pi;

  /// Ana ekran UFO'sunun rengi seviyeye göre değişir (ufo10_* görselleri).
  static const List<String> _ufoNames = [
    'blue', 'pink', 'green', 'orange', 'purple', 'yellow', 'red', 'teal',
    'lightblue', 'lime', 'navy', 'brown', 'maroon', 'white', 'black',
  ];

  late final AnimationController _loop; // 6 sn'lik kesintisiz döngü (süzülme, zıplama, parıltı)
  late final AnimationController _intro; // açılışta bir kez: öğeler sırayla belirir
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    Audio.music(MusicTrack.menu);
    _loop = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
  }

  @override
  void dispose() {
    _loop.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameScreen(level: Progress.level)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _confirmReset() async {
    final ok = await showGamePopup<bool>(
      context,
      emoji: '⚠️',
      title: 'İlerleme sıfırlansın mı?',
      message: 'Seviyen ve coinlerin baştan başlar. Bu işlem geri alınamaz.',
      accent: const Color(0xFFFF5252),
      dismissible: true,
      buttons: const [
        PopupBtn<bool>('Vazgeç', kind: PopupKind.ghost, value: false),
        PopupBtn<bool>('Sıfırla', kind: PopupKind.danger, value: true),
      ],
    );
    if (ok == true) {
      await Progress.reset();
      if (mounted) setState(() {});
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0620),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/img/bg_station.webp', fit: BoxFit.cover),
          // Kenarlara doğru koyulaşan perde: öğeler öne çıksın.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withAlpha(130),
                  Colors.black.withAlpha(20),
                  Colors.black.withAlpha(150),
                ],
              ),
            ),
          ),
          // Parıldayan yıldızlar.
          AnimatedBuilder(
            animation: _loop,
            builder: (_, __) => CustomPaint(painter: _StarsPainter(_loop.value)),
          ),
          SafeArea(
            child: AnimatedBuilder(
              animation: Listenable.merge([_loop, _intro]),
              builder: (context, _) => _content(),
            ),
          ),
        ],
      ),
    );
  }

  /// [a,b] aralığında yumuşakça belirip yukarı kayarak yerine oturur.
  Widget _in(double a, double b, Widget child, {double dy = 26}) {
    final p = Interval(a, b, curve: Curves.easeOutCubic).transform(_intro.value);
    return Opacity(
      opacity: p.clamp(0.0, 1.0).toDouble(),
      child: Transform.translate(offset: Offset(0, (1 - p) * dy), child: child),
    );
  }

  Widget _content() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: _in(
            0.0,
            0.4,
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_settingsButton(), _coinPill()]),
            dy: -14,
          ),
        ),
        const SizedBox(height: 6),
        _in(0.05, 0.5, _logo()),
        const SizedBox(height: 6),
        _in(0.2, 0.6, const Text(
          'Yolcuları doğru UFO\'ya bindir!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            shadows: [Shadow(blurRadius: 6, color: Colors.black)],
          ),
        )),
        Expanded(
          child: _in(
            0.25,
            0.8,
            LayoutBuilder(builder: (context, box) => _hero(box.maxWidth, box.maxHeight)),
            dy: 40,
          ),
        ),
        _in(0.5, 0.9, _levelPill()),
        const SizedBox(height: 12),
        _in(0.55, 1.0, _playButton()),
        const SizedBox(height: 6),
        _in(
          0.7,
          1.0,
          TextButton(
            onPressed: _confirmReset,
            child: const Text('İlerlemeyi sıfırla', style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  // ---------------------------------------------------------------- parçalar

  Widget _settingsButton() {
    return GestureDetector(
      onTap: () async {
        Audio.play(Sfx.click);
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
        if (mounted) setState(() {});
      },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withAlpha(110),
          border: Border.all(color: Colors.white.withAlpha(70), width: 1.5),
        ),
        child: const Icon(Icons.settings_rounded, color: Colors.white, size: 26),
      ),
    );
  }

  Widget _coinPill() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 16, 5),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(110),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withAlpha(70), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/img/coin.webp', width: 26, height: 26),
          const SizedBox(width: 8),
          Text(
            '${Progress.coins}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// Logo: kalın koyu kenar + degrade dolgu + mor parıltı.
  Widget _logo() {
    Widget line(String s, double size) {
      final base = TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: 2, height: 1.0);
      return Stack(
        alignment: Alignment.center,
        children: [
          Text(
            s,
            style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = size * 0.18
                ..strokeJoin = StrokeJoin.round
                ..color = const Color(0xFF2A1466),
              shadows: const [Shadow(blurRadius: 24, color: Color(0xCC7C4DFF))],
            ),
          ),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0xFFBFA2FF)],
            ).createShader(r),
            child: Text(s, style: base.copyWith(color: Colors.white)),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            line('UFO BUS', 50),
            const SizedBox(height: 2),
            line('JAM', 72),
          ],
        ),
      ),
    );
  }

  /// Orta sahne: yan yana 3 farklı renk UFO. Her UFO'nun altındaki yolcular sırayla ışınla yukarı çekilip
  /// UFO'ya biner (süzülür, küçülür, kaybolur), UFO bir "bip" gibi hafifçe sarsılır.
  Widget _hero(double w, double h) {
    final t = _loop.value;
    final ufoW = math.min(w * 0.31, h * 0.34 * 256 / 233);
    final ufoH = ufoW * 233 / 256;
    final top = h * 0.10;
    final floor = h * 0.97;
    final beamTop = top + ufoH * 0.74;
    final beamH = math.max(10.0, floor - beamTop);
    final ah = math.min(h * 0.17, w * 0.11);
    final aw = ah * 203 / 256;
    // Seviyeye göre 3 ardışık renk.
    final names = [for (int i = 0; i < 3; i++) _ufoNames[(Progress.level + i * 5) % _ufoNames.length]];
    final beamOp = 0.62 + 0.14 * math.sin(t * _tau * 4);
    final children = <Widget>[];
    for (int u = 0; u < 3; u++) {
      final cx = w * (0.18 + 0.32 * u);
      final bob = math.sin(t * _tau * 2 + u * 2.1) * h * 0.012;
      final tilt = math.sin(t * _tau + u * 1.3) * 0.03;
      // Işın.
      children.add(Positioned(
        left: cx - ufoW * 0.5,
        top: beamTop + bob,
        width: ufoW,
        height: beamH,
        child: Opacity(
          opacity: beamOp.clamp(0.0, 1.0).toDouble(),
          child: Image.asset('assets/img/beam.webp', fit: BoxFit.fill),
        ),
      ));
      // Işınlanan yolcular: her UFO'da 2 yolcu, farklı fazlarda yukarı çekilir.
      for (int k = 0; k < 2; k++) {
        final p = ((t * 2 + u * 0.31 + k * 0.5) % 1.0); // 0..1
        const wait = 0.28; // ilk %28: yerde zıplayarak bekler
        final lift = p < wait ? 0.0 : Curves.easeIn.transform((p - wait) / (1 - wait));
        final y = floor - ah - (floor - ah - (top + ufoH * 0.55)) * lift
            - (p < wait ? math.max(0.0, math.sin(t * _tau * 6 + k)) * ah * 0.12 : 0.0);
        final scale = 1.0 - 0.65 * lift;
        final op = lift > 0.9 ? (1 - lift) * 10 : 1.0;
        final dx = (k == 0 ? -1 : 1) * aw * 0.8 * (1 - lift);
        children.add(Positioned(
          left: cx + dx - aw / 2,
          top: y,
          width: aw,
          height: ah,
          child: Opacity(
            opacity: op.clamp(0.0, 1.0).toDouble(),
            child: Transform.scale(
              scale: scale,
              child: Image.asset('assets/img/alien_${names[u]}.webp', fit: BoxFit.contain),
            ),
          ),
        ));
      }
      // UFO.
      children.add(Positioned(
        left: cx - ufoW / 2,
        top: top + bob,
        width: ufoW,
        height: ufoH,
        child: Transform.rotate(
          angle: tilt,
          child: Image.asset('assets/img/ufo10_${names[u]}.webp', fit: BoxFit.contain),
        ),
      ));
    }
    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _levelPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(110),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withAlpha(70), width: 1.5),
      ),
      child: Text(
        'SEVİYE ${Progress.level}',
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2.5),
      ),
    );
  }

  Widget _playButton() {
    final glow = 0.5 + 0.5 * math.sin(_loop.value * _tau * 3);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        Audio.play(Sfx.click);
        _play();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: Container(
          width: 280,
          height: 70,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(35),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFA67CFF), Color(0xFF6A3BFF)],
            ),
            border: Border.all(color: Colors.white.withAlpha(160), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C4DFF).withAlpha((90 + 110 * glow).round()),
                blurRadius: 18 + 14 * glow,
                spreadRadius: 1,
              ),
              const BoxShadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 5)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(33),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Parlak üst yarı.
                Align(
                  alignment: Alignment.topCenter,
                  child: FractionallySizedBox(
                    heightFactor: 0.48,
                    widthFactor: 1.0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white.withAlpha(90), Colors.white.withAlpha(10)],
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.play_arrow_rounded, size: 40, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'OYNA',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        color: Colors.white,
                        shadows: [Shadow(blurRadius: 4, color: Color(0x88000000), offset: Offset(0, 2))],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Arka plandaki hafif parıldayan yıldız tozu.
class _StarsPainter extends CustomPainter {
  final double t;
  const _StarsPainter(this.t);

  static final List<List<double>> _stars = _gen();

  static List<List<double>> _gen() {
    final r = math.Random(7);
    return List.generate(
      28,
      (_) => <double>[r.nextDouble(), r.nextDouble(), r.nextDouble() * math.pi * 2, 1.0 + r.nextDouble() * 1.8],
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final s in _stars) {
      final tw = 0.5 + 0.5 * math.sin(t * math.pi * 2 * 2 + s[2]);
      p.color = Colors.white.withAlpha((40 + 190 * tw).round());
      canvas.drawCircle(Offset(s[0] * size.width, s[1] * size.height), s[3] * (0.7 + 0.6 * tw), p);
    }
  }

  @override
  bool shouldRepaint(covariant _StarsPainter old) => old.t != t;
}
