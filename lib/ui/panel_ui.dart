import 'package:flutter/material.dart';

import '../audio.dart';
import 'game_popup.dart';

/// Seçenekler / alt sayfalar için ortak arayüz parçaları (UFO teması):
/// kurdele başlık, geri düğmesi, koyu cam panel, parlak düğmeler, bölüm başlıkları.

const Color kPanelBg = Color(0xFF1A1040);
const Color kSectionColor = Color(0xFFC9B3FF);

/// Uzay arka planı + üstte kurdele başlık + altta yuvarlak köşeli koyu panel.
class PanelScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const PanelScaffold({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0620),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/img/bg_station.webp', fit: BoxFit.cover),
          DecoratedBox(decoration: BoxDecoration(color: Colors.black.withAlpha(140))),
          SafeArea(
            child: Column(
              children: [
                SizedBox(
                  height: 88,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(padding: const EdgeInsets.only(left: 14), child: _BackButton()),
                      ),
                      _Ribbon(title: title),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: kPanelBg.withAlpha(238),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
                      border: Border.all(color: Colors.white.withAlpha(45), width: 1.5),
                      boxShadow: const [BoxShadow(color: Color(0x887C4DFF), blurRadius: 24, spreadRadius: -4)],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
                        children: children,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF2A1466).withAlpha(230),
          border: Border.all(color: Colors.white.withAlpha(170), width: 2.5),
          boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 3))],
        ),
        child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}

class _Ribbon extends StatelessWidget {
  final String title;
  const _Ribbon({required this.title});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: CustomPaint(painter: _RibbonPainter())),
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 34, right: 34),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  shadows: [
                    Shadow(blurRadius: 0, color: Color(0xFF2A1466), offset: Offset(0, 2)),
                    Shadow(blurRadius: 6, color: Color(0xAA000000), offset: Offset(0, 3)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final tailW = w * 0.18;
    final tailTop = h * 0.20;
    final tailBot = h * 0.98;
    final bodyTop = h * 0.03;
    final bodyBot = h * 0.82;

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withAlpha(215);

    // Kuyruklar (kurdelenin kıvrılan uçları, gövdeden koyu).
    final tailFill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF5B2FD6), Color(0xFF34188F)],
      ).createShader(Rect.fromLTWH(0, tailTop, w, tailBot - tailTop));
    final left = Path()
      ..moveTo(0, tailTop)
      ..lineTo(tailW + 6, tailTop)
      ..lineTo(tailW + 6, tailBot)
      ..lineTo(0, tailBot)
      ..lineTo(tailW * 0.38, (tailTop + tailBot) / 2)
      ..close();
    final right = Path()
      ..moveTo(w, tailTop)
      ..lineTo(w - tailW - 6, tailTop)
      ..lineTo(w - tailW - 6, tailBot)
      ..lineTo(w, tailBot)
      ..lineTo(w - tailW * 0.38, (tailTop + tailBot) / 2)
      ..close();
    canvas.drawPath(left, tailFill);
    canvas.drawPath(left, edge);
    canvas.drawPath(right, tailFill);
    canvas.drawPath(right, edge);

    // Gövde.
    final body = RRect.fromLTRBR(tailW * 0.75, bodyTop, w - tailW * 0.75, bodyBot, const Radius.circular(14));
    final bodyFill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFB089FF), Color(0xFF7C4DFF), Color(0xFF5A2BD6)],
        stops: [0.0, 0.5, 1.0],
      ).createShader(body.outerRect);
    canvas.drawShadow(Path()..addRRect(body), Colors.black, 6, true);
    canvas.drawRRect(body, bodyFill);
    // Üst parlama.
    canvas.save();
    canvas.clipRRect(body);
    canvas.drawRect(
      Rect.fromLTWH(body.left, body.top, body.width, body.height * 0.45),
      Paint()..color = Colors.white.withAlpha(55),
    );
    canvas.restore();
    canvas.drawRRect(body, edge);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bölüm başlığı (SES, CİHAZ ...).
class PanelSection extends StatelessWidget {
  final String text;
  const PanelSection(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: kSectionColor,
          fontSize: 15,
          fontWeight: FontWeight.w900,
          letterSpacing: 3,
        ),
      ),
    );
  }
}

enum GlossyColor { purple, orange }

/// Parlak, kalın kenarlı oyun düğmesi. [checked] verilirse solunda onay kutusu çıkar (aç/kapa).
class GlossyButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool? checked;
  final VoidCallback onTap;
  final GlossyColor color;
  final double height;

  const GlossyButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.checked,
    this.color = GlossyColor.purple,
    this.height = 62,
  });

  @override
  State<GlossyButton> createState() => _GlossyButtonState();
}

class _GlossyButtonState extends State<GlossyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final colors = widget.color == GlossyColor.orange
        ? const [Color(0xFFFFC15E), Color(0xFFFF9100), Color(0xFFE86A00)]
        : const [Color(0xFFB794FF), Color(0xFF7C4DFF), Color(0xFF5A2BD6)];
    const lead = 54.0;
    final hasLead = widget.checked != null || widget.icon != null;

    Widget leading() {
      if (widget.checked != null) {
        return Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFF3B2A8F).withAlpha(120), width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(0, 2))],
          ),
          child: widget.checked == true
              ? const Icon(Icons.check_rounded, color: Color(0xFF2DBE3A), size: 28)
              : null,
        );
      }
      return Icon(widget.icon, color: Colors.white, size: 32);
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        Audio.play(Sfx.click);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: Container(
          height: h,
          padding: const EdgeInsets.all(4.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(h / 2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0xFFB9BDD6)],
            ),
            boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 4))],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(h / 2 - 4),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors,
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(h / 2 - 4),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: FractionallySizedBox(
                      heightFactor: 0.46,
                      widthFactor: 1.0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.white.withAlpha(95), Colors.white.withAlpha(8)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      SizedBox(width: lead, child: hasLead ? Center(child: leading()) : null),
                      Expanded(
                        child: Text(
                          widget.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            height: 1.1,
                            shadows: [Shadow(blurRadius: 3, color: Color(0x99000000), offset: Offset(0, 2))],
                          ),
                        ),
                      ),
                      const SizedBox(width: lead),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel içi boşluk için küçük yardımcı.
class PanelGap extends StatelessWidget {
  final double h;
  const PanelGap([this.h = 12, Key? key]) : super(key: key);

  @override
  Widget build(BuildContext context) => SizedBox(height: h);
}

/// Panel içi düz yazı bloğu (nasıl oynanır, şartlar vb.).
class PanelText extends StatelessWidget {
  final String text;
  final bool heading;
  const PanelText(this.text, {super.key, this.heading = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: heading ? 14 : 4, bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: heading ? Colors.white : Colors.white.withAlpha(215),
          fontSize: heading ? 18 : 15.5,
          fontWeight: heading ? FontWeight.w900 : FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }
}

/// Tema ile uyumlu bilgi penceresi (v0.16.5: özel oyun penceresi).
Future<void> showPanelDialog(BuildContext context, {required String title, required Widget content}) {
  return showGamePopup<void>(
    context,
    icon: Icons.info_outline_rounded,
    title: title,
    body: content,
    dismissible: true,
    buttons: const [PopupBtn<void>('Tamam')],
  );
}
