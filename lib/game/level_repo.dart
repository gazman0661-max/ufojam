import 'dart:math';

import '../l10n.dart';

import 'models.dart';
import 'level_data.dart';
import 'ring_data.dart';
import 'late_order.dart';
import 'story_order.dart';
import 'early_order.dart';
import 'rules.dart';
import 'stage_extras.dart';

/// Seviye sırası (v0.10):
///  - 1..7    : yumuşak başlangıç seviyeleri (anahtar 1001..1007)
///  - 8..70   : kademeli zorlaşan sıra (early_order.dart, v0.16.9)
///  - 71..122 : yeniden dizilmiş hikâye (story_order.dart); 123: anahtar 123
///  - 124+    : sonsuz akış: ana setin 157 düzenlik havuzu, her turda yeniden
///              karıştırılır (başa/kolaya dönüş yok).
const int kEasyCount = 25;
const int kEarlyStart = 8; // 1..7 sabit yumuşak başlangıç
const int kEarlyEnd = 70;
const int kStoryEnd = 123;

final List<int> _pool = (() {
  final s = <int>{};
  for (int i = kStoryEnd; i < kStageOrder.length; i++) {
    s.add(kStageOrder[i]);
  }
  final l = s.toList()..sort();
  return l;
})();

final Map<int, List<int>> _cycleCache = <int, List<int>>{};

/// Tur numarasına göre deterministik karıştırılmış havuz (önceki turun sonuyla aynı düzenle başlamaz).
List<int> _cycle(int c) {
  final cached = _cycleCache[c];
  if (cached != null) return cached;
  final prevLast = c == 0 ? kStageOrder[kStoryEnd - 1] : _cycle(c - 1).last;
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

/// Seviye numarası (1..) -> kStages anahtarı.
int stageKeyFor(int n) {
  if (n < 1) n = 1;
  if (n < kEarlyStart) return 1000 + n;
  if (n <= kEarlyEnd) return kEarly8To70[n - kEarlyStart]; // v0.16.9: kademeli zorluk (early_order.dart)
  if (n >= 71 && n < kStoryEnd) return kStory71To122[n - 71]; // v0.16.8: yeniden dizilmiş (story_order.dart)
  if (n <= kStoryEnd) return kStageOrder[n - 1];
  final k = n - kStoryEnd - 1;
  if (k < kLateOrder.length) return kLateOrder[k];
  return _cycle(k ~/ _pool.length)[k % _pool.length];
}

/// Referans seviye düzenlerini (serbest konum + serbest açı) LevelData'ya çevirir.
class LevelRepo {
  static final Map<int, LevelData> _cache = <int, LevelData>{};

  static LevelData get(int number) {
    return _cache.putIfAbsent(number, () => _build(number));
  }

  static LevelData _build(int number) {
    final stage = stageKeyFor(number);
    final st = kStages[stage]!;
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
    const pad = 0.10; // v0.16.4: UFO gövdesi disk çapı kadar; tahta tam UFO sayısına göre sıkı
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
      return L.t('Önü açık bir UFO\'ya dokun: park yerine uçar. Yolcular kapıdan geçerken kendi renkli UFO\'ya biner.',
          'Tap a UFO with a clear path: it flies to a parking slot. Passengers board the UFO of their own color as they pass the gate.');
    case 2:
      return L.t('UFO ok yönünde çıkar. Önünde başka UFO varsa çarpıp geri döner. Sıkışırsan ⚡ Hemen Bin!',
          'A UFO leaves in the direction of its arrow. If another UFO is in the way, it bumps and comes back. If you get stuck, use ⚡ Board Now!');
    case 3:
      return L.t('Kollardaki renk sırasına bak: halkaya girecek rengin UFO\'sunu önceden park et!',
          'Check the color order on the arms: park the UFO of the color that is about to enter the ring in advance!');
    case 10:
      return L.t('Gri "?" UFO\'nun rengi önü açılınca belli olur. Altın VIP yuvaya sadece Işınla ile UFO konur.',
          'The color of the gray "?" UFO is revealed once its path is clear. Only Teleport can place a UFO in the golden VIP slot.');
    case 26:
      return L.t('Zor seviye! Park yerlerini boşa harcama.', 'Hard level! Don\'t waste your parking slots.');
    default:
      return '';
  }
}
