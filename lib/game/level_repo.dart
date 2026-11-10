import 'dart:math';

import 'models.dart';
import 'ref_levels.dart';
import 'ref_rings.dart';
import 'late_order.dart';
import 'rules.dart';
import 'stage_extras.dart';

/// Seviye sırası (v0.10):
///  - 1..25   : APK'daki yerleşik (bus_escape_a) yumuşak başlangıç seviyeleri (anahtar 1001..1025)
///  - 26..123 : referans canlı set (remote_prd 1.6.0), seviye n = anahtar n
///  - 124+    : referanstaki gibi sonsuz akış: canlı setin 157 düzenlik havuzu, her turda yeniden
///              karıştırılır (referansta 5000 sıralık, is_repeat=1 karışık tablo; başa/kolaya dönüş yok).
const int kEasyCount = 25;
const int kStoryEnd = 123;

final List<int> _pool = (() {
  final s = <int>{};
  for (int i = kStoryEnd; i < kRefOrder.length; i++) {
    s.add(kRefOrder[i]);
  }
  final l = s.toList()..sort();
  return l;
})();

final Map<int, List<int>> _cycleCache = <int, List<int>>{};

/// Tur numarasına göre deterministik karıştırılmış havuz (önceki turun sonuyla aynı düzenle başlamaz).
List<int> _cycle(int c) {
  final cached = _cycleCache[c];
  if (cached != null) return cached;
  final prevLast = c == 0 ? kRefOrder[kStoryEnd - 1] : _cycle(c - 1).last;
  final l = List<int>.from(_pool);
  int s = (c * 7919 + 13) & 0x7fffffff;
  int next() {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    return s >> 8;
  }

  for (int i = l.length - 1; i > 0; i--) {
    final j = next() % (i + 1);
    final t = l[i];
    l[i] = l[j];
    l[j] = t;
  }
  if (l.first == prevLast) {
    final t = l[0];
    l[0] = l[1];
    l[1] = t;
  }
  _cycleCache[c] = l;
  return l;
}

/// Seviye numarası (1..) -> kRefStages anahtarı.
int stageKeyFor(int n) {
  if (n < 1) n = 1;
  if (n <= kEasyCount) return 1000 + n;
  if (n <= kStoryEnd) return kRefOrder[n - 1];
  final k = n - kStoryEnd - 1;
  if (k < kLateOrder.length) return kLateOrder[k];
  return _cycle(k ~/ _pool.length)[k % _pool.length];
}

/// Referans APK'daki seviye düzenlerini (serbest konum + serbest açı) LevelData'ya çevirir.
class LevelRepo {
  static final Map<int, LevelData> _cache = <int, LevelData>{};

  static LevelData get(int number) {
    return _cache.putIfAbsent(number, () => _build(number));
  }

  static LevelData _build(int number) {
    final stage = stageKeyFor(number);
    final st = kRefStages[stage]!;
    final layers = kStageLayers[stage] ?? const <int>[];
    final ufos = <UfoSpec>[];
    int maxColor = 0;
    double minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    final nl = layers.isEmpty ? 0 : layers.fold<int>(0, (m, v) => v > m ? v : m) + 1;
    final lMinX = List<double>.filled(nl, 1e9);
    final lMinY = List<double>.filled(nl, 1e9);
    final lMaxX = List<double>.filled(nl, -1e9);
    final lMaxY = List<double>.filled(nl, -1e9);
    for (final row in st[0].split(';')) {
      final f = row.split(',');
      final seats = const [0, 4, 6, 10][int.parse(f[4])];
      final color = int.parse(f[3]);
      final x = double.parse(f[0]);
      final y = double.parse(f[1]);
      final deg = double.parse(f[2]);
      final id = ufos.length;
      ufos.add(UfoSpec(
        id: id,
        x: x,
        y: y,
        angle: deg * pi / 180.0,
        color: color,
        seats: seats,
        mystery: f[5] == '1',
        group: int.parse(f[6]),
      ));
      maxColor = max(maxColor, color);
      final r = ufoLength(seats) / 2;
      minX = min(minX, x - r);
      maxX = max(maxX, x + r);
      minY = min(minY, y - r);
      maxY = max(maxY, y + r);
      if (nl > 0) {
        final l = layers[id];
        lMinX[l] = min(lMinX[l], x - r);
        lMaxX[l] = max(lMaxX[l], x + r);
        lMinY[l] = min(lMinY[l], y - r);
        lMaxY[l] = max(lMaxY[l], y + r);
      }
    }
    List<int> arm(String s) => s.isEmpty ? <int>[] : s.split(' ').map(int.parse).toList();
    // Katmanlı düzende yolcu sırası katman sırasına göre yeniden dizilmiştir (tools/solve_layers.py).
    final armRows = kStageArms[stage];
    const pad = 0.12; // UFO gövde yarıçapı zaten uzunluk/2; fazladan boşluk tahtayı küçültüyordu
    final base = LevelData(
      number: number,
      stage: stage,
      slots: 4,
      colorCount: maxColor + 1,
      ufos: ufos,
      arms: armRows != null ? [arm(armRows[0]), arm(armRows[1])] : [arm(st[1]), arm(st[2])],
      ringCap: ringCapFor(stage), // referans: halka+kol uzunluğuna göre seviye başına
      hint: hintFor(number),
      minX: minX - pad,
      minY: minY - pad,
      maxX: maxX + pad,
      maxY: maxY + pad,
      layerOf: layers,
      layerBounds: [
        for (int l = 0; l < nl; l++) <double>[lMinX[l] - pad, lMinY[l] - pad, lMaxX[l] + pad, lMaxY[l] + pad],
      ],
      armCut: kStageArmCut[stage] ?? const <int>[],
    );
    // Özgün mekanikler: hamle bütçesi, dönen UFO, arızalı UFO.
    return base.withRules(rulesFor(number, stage, base.ufos));
  }
}

String hintFor(int level) {
  switch (level) {
    case 1:
      return 'Önü açık bir UFO\'ya dokun: park yerine uçar. Yolcular kapıdan geçerken kendi renkli UFO\'ya biner.';
    case 2:
      return 'UFO ok yönünde çıkar. Önünde başka UFO varsa çarpıp geri döner. Sıkışırsan ⚡ Hemen Bin!';
    case 3:
      return 'Kollardaki renk sırasına bak: halkaya girecek rengin UFO\'sunu önceden park et!';
    case 10:
      return 'Gri "?" UFO\'nun rengi önü açılınca belli olur. Altın VIP yuvaya sadece Işınla ile UFO konur.';
    case 26:
      return 'Zor seviye! Park yerlerini boşa harcama.';
    default:
      return '';
  }
}
