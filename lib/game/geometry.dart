import 'dart:math';

import 'models.dart';

/// Araç `m` ileri giderken `o` aracına çarpar mı?
///
/// `m`nin ön kenarından başlayıp sonsuza giden, genişliği `ufoWidth(seats) * kStripFactor` olan şerit
/// (aracın kendi yönünde) ile `o`nun (küçültülmüş) dikdörtgen gövdesi kesişiyorsa çarpar.
/// Döner: çarpışma varsa, m'nin ön kenarından çarpılan noktaya kadar mesafe (tahta birimi, >= 0),
/// yoksa null. tools/convert_levels.py'deki `sat()` ile aynı sonucu verir.
double? sweepHit(UfoSpec m, UfoSpec o) {
  final fx = m.dirX;
  final fy = m.dirY;
  final sx = cos(m.angle); // yan eksen (sağ)
  final sy = sin(m.angle);
  final hl = ufoLength(m.seats) / 2;
  final hw = ufoWidth(m.seats) / 2 * kStripFactor;
  final ohl = ufoLength(o.seats) / 2 * kBodyShrink;
  final ohw = ufoWidth(o.seats) / 2 * kBodyShrink;
  final ofx = o.dirX;
  final ofy = o.dirY;
  final osx = cos(o.angle);
  final osy = sin(o.angle);

  // o'nun 4 köşesi m'nin yerel eksenlerinde: u = ileri (ön kenardan), v = yan.
  final us = List<double>.filled(4, 0.0);
  final vs = List<double>.filled(4, 0.0);
  const sa = [1.0, 1.0, -1.0, -1.0];
  const sb = [1.0, -1.0, -1.0, 1.0];
  for (int i = 0; i < 4; i++) {
    final px = o.x + ofx * ohl * sa[i] + osx * ohw * sb[i];
    final py = o.y + ofy * ohl * sa[i] + osy * ohw * sb[i];
    final dx = px - m.x;
    final dy = py - m.y;
    us[i] = dx * fx + dy * fy - hl;
    vs[i] = dx * sx + dy * sy;
  }

  // u >= 0 yarım düzlemine kırp (Sutherland-Hodgman).
  final cu = <double>[];
  final cv = <double>[];
  for (int i = 0; i < 4; i++) {
    final j = (i + 1) % 4;
    final inI = us[i] >= 0;
    final inJ = us[j] >= 0;
    if (inI) {
      cu.add(us[i]);
      cv.add(vs[i]);
    }
    if (inI != inJ) {
      final t = us[i] / (us[i] - us[j]);
      cu.add(0.0);
      cv.add(vs[i] + (vs[j] - vs[i]) * t);
    }
  }
  if (cu.isEmpty) return null;
  double minV = cv[0], maxV = cv[0], minU = cu[0];
  for (int i = 1; i < cu.length; i++) {
    minV = min(minV, cv[i]);
    maxV = max(maxV, cv[i]);
    minU = min(minU, cu[i]);
  }
  if (maxV <= -hw + 1e-9 || minV >= hw - 1e-9) return null;
  return max(0.0, minU);
}
