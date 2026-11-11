import 'dart:math';

import 'package:flutter/material.dart';

import '../ads.dart';
import '../audio.dart';
import '../settings.dart';

/// Bölüm bitince çıkan kutlama ekranı (referans videodaki "Great Job" ekranının UFO'lu hali):
/// karartılmış oyun, üstte ışın altında zıplayan uzaylı + UFO, "HARİKA!" afişi, coin yığını,
/// turuncu "Sonraki" düğmesi ve ekranın üst yarısında sürekli patlayan havai fişekler.
/// Havai fişek patlamaları arasından renkli UFO'lar geçer.

const List<String> _names = [
  'red', 'blue', 'green', 'yellow', 'purple', 'orange', 'pink', 'lightblue',
  'white', 'black', 'brown', 'lime', 'teal', 'maroon', 'navy',
];

const List<Color> _cols = [
  Color(0xFFE53935),
  Color(0xFF3F6FFF),
  Color(0xFF43C443),
  Color(0xFFFFD600),
  Color(0xFF9C4DFF),
  Color(0xFFFF8F00),
  Color(0xFFFF6FB0),
  Color(0xFF5CC8FF),
  Color(0xFFF2F2F2),
  Color(0xFF8D5A3C),
  Color(0xFFB4E33D),
  Color(0xFF26C6A6),
];

class WinOverlay extends StatefulWidget {
  final int levelNumber;
  final int reward;
  final VoidCallback onNext;
  final VoidCallback onMenu;
  /// Reklam izlenince ödülü bir kez daha ekler (parent coin'i günceller).
  final Future<void> Function() onDouble;
  const WinOverlay({
    super.key,
    required this.levelNumber,
    required this.reward,
    required this.onNext,
    required this.onMenu,
    required this.onDouble,
  });

  @override
  State<WinOverlay> createState() => _WinOverlayState();
}

class _Burst {
  final double t0; // saniye
  final Offset pos; // 0..1 ekran oranı
  final List<Color> palette;
  final int petals;
  final double size; // 0..1 (ekran genişliği oranı)
  final double rot;
  _Burst(this.t0, this.pos, this.palette, this.petals, this.size, this.rot);
}

class _Flyer {
  final double t0;
  final double dur;
  final double y; // 0..1
  final bool ltr;
  final int color;
  final double size; // ekran genişliği oranı
  final double wob;
  _Flyer(this.t0, this.dur, this.y, this.ltr, this.color, this.size, this.wob);
}

class _WinOverlayState extends State<WinOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  final Random _r = Random();
  final List<_Burst> _bursts = <_Burst>[];
  final List<_Flyer> _flyers = <_Flyer>[];
  double _nextBurst = 0.15;
  double _nextFlyer = 0.6;
  double _t = 0;
  bool _doubled = false;

  Future<void> _askDouble() async {
    if (_doubled) return;
    final ok = await Ads.watch(
      context,
      title: 'Coinleri ikiye katla',
      message: 'Reklam izleyerek bu bölümün ödülünü x2 yap (+${widget.reward} coin daha).',
    );
    if (!ok || !mounted) return;
    await widget.onDouble();
    if (mounted) setState(() => _doubled = true);
  }
  int _heroColor = 2; // ana uzaylı: yeşil (jöle uzaylı)
  int _heroUfo = 1; // ana UFO: mavi

  @override
  void initState() {
    super.initState();
    _heroColor = _r.nextInt(_cols.length);
    _heroUfo = (_heroColor + 1 + _r.nextInt(_cols.length - 1)) % _cols.length;
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 3600))
      ..addListener(_tick)
      ..forward();
    // Coin yığını belirirken para sesi.
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) Audio.play(Sfx.coin);
    });
  }

  final Stopwatch _sw = Stopwatch()..start();

  void _tick() {
    _t = _sw.elapsedMicroseconds / 1e6;
    // Havai fişek: yaklaşık her 0.3 sn'de bir, üst yarıda, bazen çift patlama.
    while (Settings.screenFx && _t >= _nextBurst) {
      final n = _r.nextDouble() < 0.3 ? 2 : 1;
      for (int i = 0; i < n; i++) {
        final base = _cols[_r.nextInt(_cols.length)];
        final pal = <Color>[
          base,
          _cols[_r.nextInt(_cols.length)],
          Colors.white,
          const Color(0xFFFFE066),
        ];
        _bursts.add(_Burst(
          _nextBurst + i * 0.08,
          Offset(0.08 + _r.nextDouble() * 0.84, 0.05 + _r.nextDouble() * 0.5),
          pal,
          10 + _r.nextInt(8),
          0.16 + _r.nextDouble() * 0.16,
          _r.nextDouble() * pi,
        ));
      }
      _nextBurst += 0.22 + _r.nextDouble() * 0.2;
    }
    // Arada bir renkli UFO ekranı yatay geçer.
    while (_t >= _nextFlyer) {
      _flyers.add(_Flyer(
        _nextFlyer,
        2.2 + _r.nextDouble() * 1.2,
        0.06 + _r.nextDouble() * 0.5,
        _r.nextBool(),
        _r.nextInt(_cols.length),
        0.13 + _r.nextDouble() * 0.07,
        _r.nextDouble() * 6.28,
      ));
      _nextFlyer += 1.1 + _r.nextDouble() * 1.4;
    }
    _bursts.removeWhere((b) => _t - b.t0 > 1.6);
    _flyers.removeWhere((f) => _t - f.t0 > f.dur + 0.2);
    setState(() {});
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _pop(double t0, double len) => ((_t - t0) / len).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    final fade = _pop(0, 0.35);
    final heroIn = Curves.elasticOut.transform(_pop(0.1, 0.9));
    final bannerIn = Curves.elasticOut.transform(_pop(0.35, 0.9));
    final coinIn = Curves.easeOutBack.transform(_pop(0.8, 0.5));
    final btnIn = Curves.easeOutBack.transform(_pop(1.1, 0.5));
    final bob = sin(_t * 2.4) * 6;
    final jump = (sin(_t * 5.0)).abs() * 14;
    final beamPulse = 0.7 + 0.3 * sin(_t * 4);
    final btnPulse = 1.0 + 0.04 * sin(_t * 5);

    final ufoW = w * 0.62;
    final ufoTop = h * 0.10;
    final alienH = w * 0.34;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Karartma
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.62 * fade)),
          ),
          // Havai fişek + geçen UFO'lar
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FireworksPainter(_bursts, _t),
              ),
            ),
          ),
          for (final f in _flyers) _buildFlyer(f, w, h),
          // Ana UFO + ışın + zıplayan uzaylı
          Positioned(
            left: (w - ufoW) / 2,
            top: ufoTop + bob,
            width: ufoW,
            child: Transform.scale(
              scale: heroIn,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/img/ufo10_${_names[_heroUfo]}.webp',
                      width: ufoW, fit: BoxFit.contain),
                  Opacity(
                    opacity: 0.85 * beamPulse,
                    child: Transform.translate(
                      offset: Offset(0, -ufoW * 0.10),
                      child: SizedBox(
                        width: ufoW * 0.62,
                        height: alienH * 1.25,
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            Positioned.fill(
                              child: Image.asset('assets/img/beam.webp', fit: BoxFit.fill),
                            ),
                            Transform.translate(
                              offset: Offset(0, -jump),
                              child: Transform.rotate(
                                angle: sin(_t * 5.0) * 0.08,
                                child: Image.asset(
                                  'assets/img/alien_${_names[_heroColor]}.webp',
                                  height: alienH,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // HARİKA! afişi
          Positioned(
            left: 0,
            right: 0,
            top: h * 0.43,
            child: Transform.scale(
              scale: bannerIn,
              child: Column(
                children: [
                  _OutlinedText(
                    'HARİKA!',
                    fontSize: min(w * 0.17, 76),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Seviye ${widget.levelNumber} tamam',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Coin yığını
          Positioned(
            left: 0,
            right: 0,
            top: h * 0.55,
            child: Transform.scale(scale: coinIn, child: _CoinPile(_doubled ? widget.reward * 2 : widget.reward, w * 0.34, _t)),
          ),
          // x2 coin (ödüllü reklam)
          if (!_doubled)
            Positioned(
              left: 0,
              right: 0,
              top: h * 0.665,
              child: Opacity(
                opacity: btnIn.clamp(0.0, 1.0),
                child: Center(child: _AdButton('x2 COIN', _askDouble)),
              ),
            ),
          // Sonraki düğmesi
          Positioned(
            left: 0,
            right: 0,
            top: h * 0.76,
            child: Transform.scale(
              scale: btnIn * btnPulse,
              child: Center(child: _OrangeButton('Sonraki', widget.onNext)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: h * 0.76 + 70,
            child: Opacity(
              opacity: btnIn.clamp(0.0, 1.0),
              child: Center(
                child: TextButton(
                  onPressed: widget.onMenu,
                  child: const Text('Menü',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlyer(_Flyer f, double w, double h) {
    final p = ((_t - f.t0) / f.dur).clamp(0.0, 1.0);
    final fw = w * f.size;
    final x = f.ltr ? -fw + (w + fw * 2) * p : w + fw - (w + fw * 2) * p;
    final y = h * f.y + sin(_t * 3 + f.wob) * 10;
    final col = _cols[f.color];
    return Positioned(
      left: x - fw / 2,
      top: y,
      width: fw,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: (f.ltr ? 1 : -1) * 0.12,
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [BoxShadow(color: col.withOpacity(0.55), blurRadius: 24, spreadRadius: 2)],
              shape: BoxShape.circle,
            ),
            child: Image.asset('assets/img/ufo4_${_names[f.color]}.webp', fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _OutlinedText extends StatelessWidget {
  final String text;
  final double fontSize;
  const _OutlinedText(this.text, {required this.fontSize});

  @override
  Widget build(BuildContext context) {
    Widget layer(Paint? stroke, Color? color, {Shader? shader}) => Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            height: 1.0,
            color: color,
            foreground: stroke ?? (shader != null ? (Paint()..shader = shader) : null),
          ),
        );
    final grad = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFFFF176), Color(0xFFFFB300)],
    ).createShader(Rect.fromLTWH(0, 0, fontSize * 5, fontSize));
    return Stack(
      alignment: Alignment.center,
      children: [
        // dış beyaz-mavi çerçeve
        layer(
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = fontSize * 0.34
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF29B6F6),
          null,
        ),
        // koyu iç çerçeve
        layer(
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = fontSize * 0.2
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF1A237E),
          null,
        ),
        layer(null, null, shader: grad),
      ],
    );
  }
}

class _CoinPile extends StatelessWidget {
  final int amount;
  final double width;
  final double t;
  const _CoinPile(this.amount, this.width, this.t);

  @override
  Widget build(BuildContext context) {
    final cw = width * 0.34;
    // Sabit dizilim: alt sıra 3, orta sıra 2, üst 1 coin; hafifçe parlar.
    final spots = <Offset>[
      Offset(-cw * 0.95, cw * 0.55),
      Offset(0, cw * 0.62),
      Offset(cw * 0.95, cw * 0.55),
      Offset(-cw * 0.5, cw * 0.18),
      Offset(cw * 0.5, cw * 0.18),
      Offset(0, -cw * 0.2),
    ];
    return SizedBox(
      height: width * 0.62,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < spots.length; i++)
            Transform.translate(
              offset: spots[i],
              child: Transform.scale(
                scale: 1.0 + 0.04 * sin(t * 4 + i),
                child: Image.asset('assets/img/coin.webp', width: cw, height: cw),
              ),
            ),
          Positioned(
            bottom: 0,
            child: Text(
              '+$amount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(color: Color(0xFF3E2723), blurRadius: 0, offset: Offset(2, 2)),
                  Shadow(color: Color(0xFF3E2723), blurRadius: 0, offset: Offset(-2, 2)),
                  Shadow(color: Color(0xFF3E2723), blurRadius: 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AdButton(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF43C443), Color(0xFF2E9E4F)],
          ),
          border: Border.all(color: const Color(0xFF1B6B33), width: 3),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 5))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.ondemand_video_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrangeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OrangeButton(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
          ),
          border: Border.all(color: const Color(0xFFE65100), width: 3),
          boxShadow: const [
            BoxShadow(color: Color(0xFFBF360C), offset: Offset(0, 5)),
            BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 8)),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: Color(0xFF8D3A00), offset: Offset(0, 2), blurRadius: 2)],
          ),
        ),
      ),
    );
  }
}

/// Patlayan havai fişekler: yuvarlak bir parlama ile başlar, renkli yaprak çizgiler dışa açılır,
/// ucunda küçük kıvılcımlar kalır ve solar.
class _FireworksPainter extends CustomPainter {
  final List<_Burst> bursts;
  final double t;
  _FireworksPainter(this.bursts, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bursts) {
      final age = t - b.t0;
      if (age < 0) continue;
      final life = (age / 1.4).clamp(0.0, 1.0);
      final center = Offset(b.pos.dx * size.width, b.pos.dy * size.height);
      final maxR = b.size * size.width;

      // Başlangıç parlaması (videodaki soluk daire)
      if (age < 0.25) {
        final f = age / 0.25;
        final p = Paint()..color = Colors.white.withOpacity(0.28 * (1 - f));
        canvas.drawCircle(center, maxR * 0.5 * (0.5 + f * 0.5), p);
      }

      final out = Curves.easeOutCubic.transform(life);
      final alpha = (1 - Curves.easeIn.transform(life)).clamp(0.0, 1.0);
      for (int i = 0; i < b.petals; i++) {
        final ang = b.rot + i * (2 * pi / b.petals);
        final col = b.palette[i % b.palette.length];
        final r0 = maxR * out * 0.55;
        final r1 = maxR * out;
        final dir = Offset(cos(ang), sin(ang));
        final a = center + dir * r0;
        final z = center + dir * r1;
        final line = Paint()
          ..color = col.withOpacity(alpha)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = (6 - 4 * life).clamp(1.5, 6.0);
        canvas.drawLine(a, z, line);
        // Uçta kıvılcım
        final sp = Paint()..color = Colors.white.withOpacity(alpha * 0.9);
        canvas.drawCircle(z, 2.4 * (1 - life) + 0.8, sp);
        // Yerçekimi ile düşen minik parçacıklar
        if (i.isEven) {
          final drop = Offset(0, life * life * maxR * 0.5);
          final sp2 = Paint()..color = col.withOpacity(alpha * 0.8);
          canvas.drawCircle(z + dir * maxR * 0.15 + drop, 1.8, sp2);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FireworksPainter old) => true;
}
