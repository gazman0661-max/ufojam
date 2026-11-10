import 'dart:math';

import 'package:flutter/material.dart';

/// Öğretici adım türleri.
/// - info:   oyun durur, vurgulu bölge + kart + düğme.
/// - tapUfo: oyun durur, SADECE gösterilen UFO'ya dokunulabilir (el + parlayan halka).
/// - watch:  oyun akar, bir olay olana kadar balon gösterilir.
/// - tapBtn: oyun durur, SADECE gösterilen booster düğmesine dokunulabilir (el + parlayan çerçeve).
enum TutKind { info, tapUfo, watch, tapBtn }

class TutStep {
  final TutKind kind;
  final String title;
  final String text;
  final String button;

  /// Adım başlarken bir kez çözülür; null dönerse adım atlanır.
  final int? Function()? ufo;

  /// 0: Hemen Bin, 1: Karıştır, 2: Işınla
  final int? boost;

  /// 'ring' | 'pads' | 'counter' | 'vip' | 'hud'
  final String? region;

  /// watch adımı için bitiş koşulu ve zaman aşımı.
  final bool Function()? done;
  final int timeoutMs;

  /// tapUfo sonrası beklenecek süre (animasyon görünsün).
  final int holdMs;

  /// Adım gerçekten gösterilmeye başlarken bir kez çalışır (ör. izlenecek değerin başlangıcını kaydetmek).
  final void Function()? onEnter;

  const TutStep({
    required this.kind,
    this.title = '',
    required this.text,
    this.button = 'Devam',
    this.ufo,
    this.boost,
    this.region,
    this.done,
    this.timeoutMs = 9000,
    this.holdMs = 0,
    this.onEnter,
  });

  bool get pausesGame => kind != TutKind.watch;
}

class TutGuide {
  final String id;
  final List<TutStep> steps;
  const TutGuide(this.id, this.steps);
}

/// Vurgulanan alan (yuvarlak köşeli dikdörtgen; daire için köşe = yarıçap).
class TutHole {
  final Rect rect;
  final double radius;
  const TutHole(this.rect, this.radius);
  factory TutHole.circle(Offset c, double r) => TutHole(Rect.fromCircle(center: c, radius: r), r);
  factory TutHole.box(Rect r) => TutHole(r.inflate(6), 14);
}

/// Karartma: vurgulanan alanlar delik, çevresinde atan altın çerçeve.
class TutSpotPainter extends CustomPainter {
  final List<TutHole> holes;
  final double t; // 0..1 döngü
  final bool dim;
  TutSpotPainter(this.holes, this.t, {this.dim = true});

  @override
  void paint(Canvas canvas, Size size) {
    if (dim) {
      Path p = Path()..addRect(Offset.zero & size);
      for (final h in holes) {
        p = Path.combine(
          PathOperation.difference,
          p,
          Path()..addRRect(RRect.fromRectAndRadius(h.rect, Radius.circular(h.radius))),
        );
      }
      canvas.drawPath(p, Paint()..color = Colors.black.withAlpha(150));
    }
    final pulse = 0.5 + 0.5 * sin(t * 2 * pi);
    for (final h in holes) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(h.rect.inflate(2 + 4 * pulse), Radius.circular(h.radius + 2 + 4 * pulse)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.amber.withAlpha(220),
      );
    }
  }

  @override
  bool shouldRepaint(covariant TutSpotPainter old) => true;
}

/// Parmak ucu verilen noktada; hafifçe atar.
class TutHand extends StatelessWidget {
  final double t;
  const TutHand({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, 9 * sin(t * 2 * pi)),
      child: const Icon(
        Icons.touch_app_rounded,
        size: 46,
        color: Colors.white,
        shadows: [Shadow(blurRadius: 8, color: Colors.black)],
      ),
    );
  }
}

/// Konuşma balonu / kart.
class TutCard extends StatelessWidget {
  final String title;
  final String text;
  final String? button;
  final VoidCallback? onButton;
  final VoidCallback? onSkip;
  final int stepNo;
  final int stepCount;

  const TutCard({
    super.key,
    required this.title,
    required this.text,
    this.button,
    this.onButton,
    this.onSkip,
    this.stepNo = 0,
    this.stepCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xF22B1F6B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber, width: 1.5),
        boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black54)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.w900),
            ),
          if (title.isNotEmpty) const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w600),
          ),
          if (button != null) ...[
            const SizedBox(height: 10),
            ElevatedButton(onPressed: onButton, child: Text(button!)),
          ],
          if (onSkip != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: GestureDetector(
                onTap: onSkip,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    stepCount > 1 ? 'Öğreticiyi atla  ($stepNo/$stepCount)' : 'Öğreticiyi atla',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
