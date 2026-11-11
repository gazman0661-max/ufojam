import 'dart:math';

import 'package:flutter/material.dart';

import '../audio.dart';

/// Oyun temalı özel pencereler (v0.16.5): neon çerçeveli uzay paneli, üstte taşan rozet, parlak 3B düğmeler.
/// Eski AlertDialog'ların hepsinin yerine geçer. Kullanım: [showGamePopup].

enum PopupKind { primary, reward, gold, ghost, danger }

/// Pencere düğmesi. [onTap] verilirse pencere kendiliğinden kapanmaz (içeride işlem yapılır, gerekirse
/// `Navigator.pop(ctx, değer)` çağrılır); verilmezse [value] ile kapanır.
class PopupBtn<T> {
  final String label;
  final IconData? icon;
  final Widget? leading;
  final PopupKind kind;
  final T? value;
  final Future<void> Function(BuildContext ctx)? onTap;
  final bool enabled;

  const PopupBtn(
    this.label, {
    this.icon,
    this.leading,
    this.kind = PopupKind.primary,
    this.value,
    this.onTap,
    this.enabled = true,
  });
}

/// Küçük bilgi hapı (örn. stok / coin göstergesi).
class PopupChip extends StatelessWidget {
  final Widget leading;
  final String text;
  const PopupChip({super.key, required this.leading, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(90),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(50), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Temalı pencere göster. [emoji] / [icon] / [badge] rozetin içeriği (öncelik: badge, emoji, icon).
Future<T?> showGamePopup<T>(
  BuildContext context, {
  String? emoji,
  IconData? icon,
  Widget? badge,
  required String title,
  String? message,
  Widget? body,
  required List<PopupBtn<T>> buttons,
  bool dismissible = false,
  Color accent = const Color(0xFF7C4DFF),
  bool stacked = false,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'popup',
    barrierColor: Colors.black.withAlpha(175),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, a1, a2) => PopScope(
      canPop: dismissible,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                type: MaterialType.transparency,
                child: _GamePopup<T>(
                  emoji: emoji,
                  icon: icon,
                  badge: badge,
                  title: title,
                  message: message,
                  body: body,
                  buttons: buttons,
                  accent: accent,
                  stacked: stacked,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, a1, a2, child) {
      final c = CurvedAnimation(parent: a1, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: a1,
        child: ScaleTransition(scale: Tween<double>(begin: 0.82, end: 1.0).animate(c), child: child),
      );
    },
  );
}

class _GamePopup<T> extends StatelessWidget {
  final String? emoji;
  final IconData? icon;
  final Widget? badge;
  final String title;
  final String? message;
  final Widget? body;
  final List<PopupBtn<T>> buttons;
  final Color accent;
  final bool stacked;

  const _GamePopup({
    required this.emoji,
    required this.icon,
    required this.badge,
    required this.title,
    required this.message,
    required this.body,
    required this.buttons,
    required this.accent,
    required this.stacked,
  });

  Color get _light => Color.lerp(accent, Colors.white, 0.45)!;

  Widget _badge() {
    Widget inner;
    if (badge != null) {
      inner = badge!;
    } else if (emoji != null) {
      inner = Text(emoji!, style: const TextStyle(fontSize: 36));
    } else {
      inner = Icon(icon ?? Icons.rocket_launch_rounded, color: Colors.white, size: 38);
    }
    return Container(
      width: 78,
      height: 78,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [_light, accent, Color.lerp(accent, Colors.black, 0.45)!],
          stops: const [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: accent.withAlpha(200), blurRadius: 22, spreadRadius: 2),
          const BoxShadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: inner,
    );
  }

  Widget _buttons() {
    final list = buttons.map((b) => _PopupButton<T>(btn: b)).toList();
    if (list.length == 2 && !stacked) {
      return Row(
        children: [
          Expanded(child: list[0]),
          const SizedBox(width: 10),
          Expanded(child: list[1]),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < list.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          list[i],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: const EdgeInsets.only(top: 39),
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF6FE7FF), accent, const Color(0xFFB388FF)],
        ),
        boxShadow: [
          BoxShadow(color: accent.withAlpha(120), blurRadius: 30, spreadRadius: 1),
          const BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27.5),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF2B1670), Color(0xFF140B3A)],
                  ),
                ),
              ),
            ),
            Positioned.fill(child: CustomPaint(painter: _StarsPainter(accent))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      height: 1.15,
                      shadows: [
                        Shadow(color: Color(0xFF2A1466), offset: Offset(0, 2)),
                        Shadow(color: Color(0xAA000000), blurRadius: 8, offset: Offset(0, 3)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 36),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.transparent, _light, Colors.transparent]),
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withAlpha(220),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (body != null) ...[
                    const SizedBox(height: 14),
                    body!,
                  ],
                  const SizedBox(height: 20),
                  _buttons(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        card,
        Positioned(top: 0, child: _badge()),
      ],
    );
  }
}

class _StarsPainter extends CustomPainter {
  final Color accent;
  const _StarsPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    // Üstte rozetin altından yayılan yumuşak ışık.
    final glow = Paint()
      ..shader = RadialGradient(colors: [accent.withAlpha(95), Colors.transparent])
          .createShader(Rect.fromCircle(center: Offset(size.width / 2, 0), radius: size.width * 0.75));
    canvas.drawRect(Offset.zero & size, glow);
    // Sabit tohumlu küçük yıldızlar (her açılışta aynı yerde).
    final r = Random(7);
    final p = Paint();
    for (int i = 0; i < 30; i++) {
      final x = r.nextDouble() * size.width;
      final y = r.nextDouble() * size.height;
      p.color = Colors.white.withAlpha(40 + r.nextInt(110));
      canvas.drawCircle(Offset(x, y), 0.6 + r.nextDouble() * 1.1, p);
    }
  }

  @override
  bool shouldRepaint(covariant _StarsPainter old) => old.accent != accent;
}

class _PopupButton<T> extends StatefulWidget {
  final PopupBtn<T> btn;
  const _PopupButton({required this.btn});

  @override
  State<_PopupButton<T>> createState() => _PopupButtonState<T>();
}

class _PopupButtonState<T> extends State<_PopupButton<T>> {
  bool _down = false;
  bool _busy = false;

  List<Color> _fill(PopupKind k) {
    switch (k) {
      case PopupKind.primary:
        return const [Color(0xFF9B6BFF), Color(0xFF5E4BFF)];
      case PopupKind.reward:
        return const [Color(0xFF45E08F), Color(0xFF12A863)];
      case PopupKind.gold:
        return const [Color(0xFFFFC53D), Color(0xFFFF8A00)];
      case PopupKind.danger:
        return const [Color(0xFFFF6B6B), Color(0xFFE02D3C)];
      case PopupKind.ghost:
        return const [Color(0x22FFFFFF), Color(0x22FFFFFF)];
    }
  }

  Color _edge(PopupKind k) {
    switch (k) {
      case PopupKind.primary:
        return const Color(0xFF2F1C9A);
      case PopupKind.reward:
        return const Color(0xFF0A6B42);
      case PopupKind.gold:
        return const Color(0xFFB35A00);
      case PopupKind.danger:
        return const Color(0xFF8F1521);
      case PopupKind.ghost:
        return Colors.transparent;
    }
  }

  Future<void> _tap() async {
    final b = widget.btn;
    if (!b.enabled || _busy) return;
    Audio.play(Sfx.click);
    if (b.onTap == null) {
      Navigator.of(context).pop(b.value);
      return;
    }
    _busy = true;
    try {
      await b.onTap!(context);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.btn;
    final ghost = b.kind == PopupKind.ghost;
    final on = b.enabled;
    final fill = on ? _fill(b.kind) : const [Color(0xFF5A5575), Color(0xFF3F3A58)];
    final edge = on ? _edge(b.kind) : const Color(0xFF2A2640);
    final txt = on ? Colors.white : Colors.white54;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (b.leading != null) ...[b.leading!, const SizedBox(width: 8)],
        if (b.leading == null && b.icon != null) ...[Icon(b.icon, color: txt, size: 22), const SizedBox(width: 8)],
        Flexible(
          child: Text(
            b.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: txt,
              fontSize: ghost ? 16 : 17,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              shadows: ghost || !on
                  ? null
                  : const [Shadow(color: Color(0x88000000), blurRadius: 3, offset: Offset(0, 2))],
            ),
          ),
        ),
      ],
    );

    return AnimatedScale(
      scale: _down ? 0.96 : 1.0,
      duration: const Duration(milliseconds: 90),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: on ? (_) => setState(() => _down = true) : null,
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: _tap,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(27),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: fill),
            border: ghost ? Border.all(color: Colors.white.withAlpha(90), width: 1.5) : null,
            boxShadow: ghost
                ? null
                : [
                    BoxShadow(color: edge, offset: const Offset(0, 4)),
                    BoxShadow(color: fill.last.withAlpha(on ? 90 : 0), blurRadius: 14, offset: const Offset(0, 6)),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(27),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!ghost && on)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 24,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white.withAlpha(95), Colors.white.withAlpha(0)],
                        ),
                      ),
                    ),
                  ),
                Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: content)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
