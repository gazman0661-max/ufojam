import 'package:flutter_test/flutter_test.dart';
import 'package:ufo_bus_jam/game/engine.dart';
import 'package:ufo_bus_jam/game/level_repo.dart';
import 'package:ufo_bus_jam/game/models.dart';
import 'package:ufo_bus_jam/game/level_data.dart';
import 'package:ufo_bus_jam/game/early_order.dart';
import 'package:ufo_bus_jam/game/ring_data.dart';
import 'package:ufo_bus_jam/game/stage_extras.dart';

/// Park yeri sınırı olmadan, önü açık araçları çıkara çıkara sahayı boşaltır.
bool _clearsField(LevelData lv) {
  final g = GameState(lv);
  bool progress = true;
  while (progress) {
    progress = false;
    for (final id in g.launchable()) {
      if (g.canLaunch(id)) {
        g.removeFromField(id);
        progress = true;
      }
    }
  }
  return g.ufos.every((u) => !u.inGrid);
}

/// Basit "akıllı" bot: 1 sn'de bir, halkada rengi en çok olan, önü açık UFO'yu park eder.
bool _playSmart(LevelData lv, {double maxSec = 600}) {
  final g = GameState(lv);
  double nextTap = 1.5;
  double t = 0;
  final departAt = <int, double>{};
  while (t < maxSec) {
    g.step(0.05);
    t += 0.05;
    if (g.won) return true;
    if (g.lost) return false;
    // Ekrandaki çıkış uçuşunun yerine: dolan UFO ~2 sn sonra yuvayı boşaltır.
    for (final id in List<int>.from(g.slots)) {
      if (id >= 0 && g.ufos[id].departed) {
        departAt.putIfAbsent(id, () => t + 2.0);
        if (t >= departAt[id]!) g.releaseSlot(id);
      }
    }
    if (t >= nextTap) {
      nextTap = t + 1.0;
      if (g.freeSlot() >= 0) {
        final opts = g.launchable();
        if (opts.isNotEmpty) {
          int score(int id) {
            int n = 0;
            for (final p in g.cells) {
              if (p != null && p.color == g.ufos[id].spec.color) n++;
            }
            return n;
          }

          opts.sort((a, b) => score(b).compareTo(score(a)));
          g.tap(opts.first);
        }
      }
    }
  }
  return false;
}

/// Bu stage anahtarının oyunda ilk göründüğü seviye numarası (yoksa -1: ör. havuza girmeyen eski L1-25 canlı düzenleri).
int _levelOfKey(int key) {
  for (int n = 1; n <= 400; n++) {
    if (stageKeyFor(n) == key) return n;
  }
  return -1;
}

void main() {
  test('referans seviyelerde her renkte koltuk = yolcu', () {
    for (final key in kStages.keys) {
      final n = _levelOfKey(key);
      if (n < 0) continue;
      final lv = LevelRepo.get(n);
      final seats = <int, int>{};
      for (final u in lv.ufos) {
        seats[u.color] = (seats[u.color] ?? 0) + u.seats;
      }
      final pax = <int, int>{};
      for (final a in lv.arms) {
        for (final c in a) {
          pax[c] = (pax[c] ?? 0) + 1;
        }
      }
      expect(seats, pax, reason: 'sahne $key');
    }
  });

  test('tüm referans seviyelerinde saha boşaltılabilir', () {
    for (final key in kStages.keys) {
      final n = _levelOfKey(key);
      if (n < 0) continue;
      expect(_clearsField(LevelRepo.get(n)), isTrue, reason: 'seviye $n');
    }
  });

  test('seviye sırası: 1-7 yumuşak set, 8-70 kademeli sıra, 71-123 hikâye, 124+ karışık havuz', () {
    for (int n = 1; n <= 7; n++) {
      expect(stageKeyFor(n), 1000 + n);
    }
    // v0.16.9: 8-70 kademeli zorluk sırası (early_order.dart); sabit çapalar: L10 gizemli UFO, L16 doğan UFO.
    expect(kEarly8To70.length, 63);
    expect(kEarly8To70.toSet().length, 63);
    expect(stageKeyFor(8), kEarly8To70.first);
    expect(stageKeyFor(70), kEarly8To70.last);
    expect(stageKeyFor(10), 1010);
    expect(stageKeyFor(16), 1016);
    final story = <int>{for (int n = 71; n <= 123; n++) stageKeyFor(n)};
    for (final k in kEarly8To70) {
      expect(kStages.containsKey(k), isTrue, reason: 'anahtar $k');
      expect(story.contains(k), isFalse, reason: 'anahtar $k hikâyede de var');
    }
    expect(stageKeyFor(123), 123);
    // 124+: her turda havuzun tamamı bir kez, ardışık aynı düzen yok
    final seen = <int>{};
    int prev = -1;
    for (int n = 124; n < 124 + 157; n++) {
      final k = stageKeyFor(n);
      expect(k >= 1 && k <= 292, isTrue, reason: 'seviye $n anahtar $k');
      expect(k != prev, isTrue);
      prev = k;
      seen.add(k);
    }
    expect(seen.length, 157);
    expect(stageKeyFor(124 + 157) != stageKeyFor(124) || stageKeyFor(125 + 157) != stageKeyFor(125), isTrue);
    expect(LevelRepo.get(5000).ufos.isNotEmpty, isTrue);
  });

  test('üst üste doğan araç: öndeki gidince sıradaki belirir', () {
    final lv = LevelRepo.get(16);
    final g = GameState(lv);
    final hidden = g.ufos.where((u) => !u.spawned).toList();
    expect(hidden.isNotEmpty, isTrue);
    final head = g.groups.values.first.first;
    g.removeFromField(head);
    expect(g.ufos[g.groups.values.first[1]].spawned, isTrue);
  });

  test('zor/rahat ritmi ve ödül', () {
    for (final n in [8, 11, 15, 20]) {
      expect(isHardLevel(n), isTrue, reason: 'erken zor seviye $n');
      expect(LevelRepo.get(n).reward, 40);
      expect(isReliefLevel(n + 1), isTrue);
      expect(LevelRepo.get(n + 1).reward, 20);
    }
    expect(isHardLevel(9), isFalse);
    expect(isHardLevel(26), isTrue);
    expect(isReliefLevel(27), isTrue);
    expect(LevelRepo.get(26).reward, 40);
    expect(LevelRepo.get(27).reward, 20);
  });

  test('park yeri ve VIP', () {
    expect(GameState(LevelRepo.get(9)).slots.length, kOpenSlots);
    expect(GameState(LevelRepo.get(10)).slots.length, kOpenSlots + 1);
  });

  test('1. seviye akıllı botla kazanılır', () {
    expect(_playSmart(LevelRepo.get(1)), isTrue);
  });

  test('halka kapasitesi seviyeye göre (referans), 3 şeritin katı', () {
    final seen = <int>{};
    for (int n = 1; n <= 300; n++) {
      final lv = LevelRepo.get(n);
      expect(lv.ringCap % kRingLanes, 0, reason: 'seviye $n');
      expect(lv.ringCap >= 63 && lv.ringCap <= 96, isTrue, reason: 'seviye $n ringCap ${lv.ringCap}');
      seen.add(lv.ringCap);
      expect(GameState(lv).cells.length, lv.ringCap);
    }
    expect(seen.length > 1, isTrue); // sabit 48 değil, seviyeye göre değişiyor
    expect(kRingData.containsKey(27), isTrue);
  });

  test('ogretici: kapali UFO\'nun ilk engeli sahada ve gercekten onunde', () {
    for (final n in [1, 2, 5, 10, 16, 25]) {
      final g = GameState(LevelRepo.get(n));
      for (final u in g.ufos) {
        final id = u.spec.id;
        if (!g.isOnField(id)) continue;
        final b = g.firstBlocker(id);
        expect(b == null, g.canLaunch(id), reason: 'seviye $n ufo $id');
        if (b != null) expect(g.isOnField(b), isTrue);
      }
    }
  });

  test('hamle butcesi: tanitim L16 (ZOR degil), oncesinde yok, RAHAT seviyede yok, bütçe >= UFO + 3', () {
    for (int n = 1; n < 16; n++) {
      expect(LevelRepo.get(n).rules.isEmpty, isTrue, reason: 'seviye $n');
    }
    final intro = LevelRepo.get(16).rules;
    expect(intro.mechs, [Mech.budget]);
    expect(isHardLevel(16), isFalse);
    int withBudget = 0;
    int total = 0;
    for (int n = 17; n <= 400; n++) {
      final lv = LevelRepo.get(n);
      final r = lv.rules;
      total++;
      if (isReliefLevel(n) && !kMechUnlock.values.contains(n)) {
        expect(r.isEmpty, isTrue, reason: 'rahat seviye $n');
      }
      if (r.moveBudget > 0) {
        withBudget++;
        expect(r.moveBudget >= lv.ufos.length + 3, isTrue, reason: 'seviye $n hamle');
      }
    }
    // Normal ~%25, ZOR ~%50: toplamda yaklaşık %20-35.
    expect(withBudget > total * 0.15 && withBudget < total * 0.4, isTrue,
        reason: 'hamle bütçeli seviye oranı $withBudget/$total');
  });

  test('hamle butcesi: ayni seviye hep ayni, sayac ve reklam hamlesi', () {
    for (final n in [16, 40, 77, 150, 321]) {
      expect(LevelRepo.get(n).rules.moveBudget, LevelRepo.get(n).rules.moveBudget);
    }
    final lv = LevelRepo.get(16);
    final g = GameState(lv);
    expect(g.movesLeft, lv.rules.moveBudget);
    g.noteWastedTap();
    expect(g.movesUsed, 1);
    expect(g.movesLeft, lv.rules.moveBudget - 1);
    g.grantMoves(5);
    expect(g.movesUsed, 0);
  });

  test('katman asansörü: sadece 0. katman görünür, bitince 1. katman çıkar, kollar katman sırasında', () {
    expect(kStageLayers.keys.isNotEmpty, isTrue);
    for (final key in kStageLayers.keys) {
      final n = _levelOfKey(key);
      if (n < 0) continue;
      final lv = LevelRepo.get(n);
      expect(lv.layerCount, 2, reason: 'sahne $key');
      final g = GameState(lv);
      for (final u in g.ufos) {
        if (lv.layerOfUfo(u.spec.id) == 1) expect(u.spawned, isFalse, reason: 'sahne $key');
      }
      expect(g.curLayer, 0);
      expect(_clearsField(lv), isTrue, reason: 'sahne $key');
      final g2 = GameState(lv);
      for (int guard = 0; guard < 400 && g2.ufos.any((u) => u.inGrid); guard++) {
        final l = g2.launchable();
        if (l.isEmpty) break;
        g2.removeFromField(l.first);
      }
      expect(g2.curLayer, 1);
      expect(g2.layerEvents, 1);
      // Karıştır katman sınırını geçmez: 1. katman yolcuları 1. katmanda kalır.
      final g3 = GameState(lv);
      final before = <int, int>{};
      for (int a = 0; a < 2; a++) {
        for (int m = g3.armHead[a]; m < lv.armCut[a] && m < g3.armQ[a].length; m++) {
          before[g3.armQ[a][m]] = (before[g3.armQ[a][m]] ?? 0) + 1;
        }
      }
      g3.shuffleQueue(7);
      final after = <int, int>{};
      for (int a = 0; a < 2; a++) {
        for (int m = g3.armHead[a]; m < lv.armCut[a] && m < g3.armQ[a].length; m++) {
          after[g3.armQ[a][m]] = (after[g3.armQ[a][m]] ?? 0) + 1;
        }
      }
      expect(after, before, reason: 'sahne $key karıştır');
    }
  });

  test('dönen UFO: başkasının yolunu değiştirmez, özgün yön geri gelir; RAHAT seviyede yok', () {
    int found = 0;
    for (int n = 21; n <= 400 && found < 6; n++) {
      final lv = LevelRepo.get(n);
      if (isReliefLevel(n) && !kMechUnlock.values.contains(n)) {
        expect(lv.rules.rotors.isEmpty && lv.rules.faulty.isEmpty, isTrue, reason: 'rahat seviye $n');
      }
      if (lv.rules.rotors.isEmpty) continue;
      found++;
      final g = GameState(lv);
      final blocked0 = <int, bool>{
        for (final u in g.ufos) u.spec.id: g.canLaunch(u.spec.id),
      };
      bool sawFlip = false;
      for (int i = 0; i < 400; i++) {
        g.step(0.05);
        if (g.ufos.any((u) => u.rotor && u.flipped)) sawFlip = true;
        for (final u in g.ufos) {
          if (u.rotor) continue;
          expect(g.canLaunch(u.spec.id), blocked0[u.spec.id], reason: 'seviye $n ufo ${u.spec.id}');
        }
      }
      expect(sawFlip, isTrue, reason: 'seviye $n');
    }
    expect(found > 0, isTrue);
  });

  test('arızalı UFO: sayaç hamlede düşer, 0 olunca bırakılan UFO geri gelir', () {
    int n = 32;
    while (n < 400 && LevelRepo.get(n).rules.faulty.isEmpty) {
      n++;
    }
    final lv = LevelRepo.get(n);
    expect(lv.rules.faulty.isNotEmpty, isTrue);
    final g = GameState(lv);
    final fid = lv.rules.faulty.keys.first;
    final c0 = g.ufos[fid].fault;
    expect(c0 > 0, isTrue);
    g.ufos[fid].fault = 1;
    int other = -1;
    for (final id in g.launchable()) {
      if (id != fid && g.ufos[id].spec.group < 0) {
        other = id;
        break;
      }
    }
    expect(other >= 0, isTrue);
    g.tap(other);
    expect(g.breakQueue.contains(fid), isTrue);
    g.breakUfo(fid);
    expect(g.ufos[fid].away || g.ufos[fid].spawned, isTrue);
    for (int i = 0; i < 6; i++) {
      final l = g.launchable().where((id) => id != fid).toList();
      if (l.isEmpty || g.freeSlot() < 0) break;
      g.tap(l.first);
    }
    expect(g.ufos[fid].away, isFalse);
    expect(g.ufos[fid].fault > 0 || !g.ufos[fid].inGrid, isTrue);
  });

  test('bant UFO: sadece pencerede çağrılır, başkasının yolunu değiştirmez, RAHAT seviyede yok', () {
    int found = 0;
    for (int n = 45; n <= 500 && found < 6; n++) {
      final lv = LevelRepo.get(n);
      if (isReliefLevel(n) && !kMechUnlock.values.contains(n)) expect(lv.rules.belts.isEmpty, isTrue, reason: 'rahat seviye $n');
      if (lv.rules.belts.isEmpty) continue;
      found++;
      final g = GameState(lv);
      bool sawOpen = false;
      bool sawClosed = false;
      for (int i = 0; i < 300; i++) {
        g.step(0.05);
        for (final id in lv.rules.belts) {
          final u = g.ufos[id];
          if (g.beltOpen(u)) {
            sawOpen = true;
          } else {
            sawClosed = true;
            expect(g.canLaunch(id), isFalse, reason: 'seviye $n');
          }
        }
      }
      expect(sawOpen && sawClosed, isTrue, reason: 'seviye $n');
    }
    expect(found > 0, isTrue);
    expect(LevelRepo.get(45).rules.mechs.contains(Mech.belt) || (kStageBelts[stageKeyFor(45)] ?? const <int>[]).isEmpty, isTrue);
  });

  test('testere disi: ZOR seviye cevresindeki normallerin >=%80 inden agir, RAHAT seviye >=%80 inden hafif (L27-400)', () {
    double pct(int n, int Function(LevelData) f) {
      int total = 0;
      int lower = 0;
      final o = f(LevelRepo.get(n));
      for (int m = n - 4; m <= n + 4; m++) {
        if (m == n || m < 26 || isHardLevel(m) || isReliefLevel(m)) continue;
        total++;
        if (f(LevelRepo.get(m)) < o) lower++;
      }
      return total == 0 ? 0.5 : lower / total;
    }

    for (int n = 27; n <= 400; n++) {
      if (!isHardLevel(n) && !isReliefLevel(n)) continue;
      final p = (pct(n, (l) => l.totalPassengers) + pct(n, (l) => l.ufos.length)) / 2;
      if (isHardLevel(n)) {
        expect(p >= 0.8, isTrue, reason: 'ZOR seviye $n zayif (yuzdelik $p)');
      } else {
        expect(p <= 0.2, isTrue, reason: 'RAHAT seviye $n agir (yuzdelik $p)');
      }
    }
  });

  test('tanıtım seviyeleri rahat düşse de tanıtımı alır (L16, L21)', () {
    expect(isReliefLevel(16), isTrue);
    expect(LevelRepo.get(16).rules.mechs, [Mech.budget]);
    expect(isReliefLevel(21), isTrue);
    expect(LevelRepo.get(21).rules.mechs.contains(Mech.rotor) || (kStageRotors[stageKeyFor(21)] ?? const <int>[]).isEmpty, isTrue);
  });

  test('hikâye 71-122 yeniden dizildi: aynı düzenler, L123 sabit', () {
    final a = <int>[for (int n = 71; n <= 122; n++) stageKeyFor(n)]..sort();
    final b = <int>[for (int n = 71; n <= 122; n++) kStageOrder[n - 1]]..sort();
    expect(a, b);
    expect(stageKeyFor(123), 123);
  });

  test('erken sıra (v0.16.9): ilk gizemli UFO L10, ilk doğan UFO L16, tanıtım seviyeleri aday taşır', () {
    for (int n = 1; n < 10; n++) {
      expect(LevelRepo.get(n).ufos.any((u) => u.mystery), isFalse, reason: 'seviye $n');
    }
    expect(LevelRepo.get(10).ufos.any((u) => u.mystery), isTrue);
    for (int n = 1; n < 16; n++) {
      expect(LevelRepo.get(n).ufos.any((u) => u.group >= 0), isFalse, reason: 'seviye $n');
    }
    expect(LevelRepo.get(16).ufos.any((u) => u.group >= 0), isTrue);
    for (int n = 1; n < 26; n++) {
      expect(LevelRepo.get(n).layerCount <= 1, isTrue, reason: 'katmanlı düzen L$n çok erken');
    }
    expect((kStageRotors[stageKeyFor(21)] ?? const <int>[]).isNotEmpty, isTrue);
    expect((kStageFaulty[stageKeyFor(32)] ?? const <int>[]).isNotEmpty, isTrue);
    expect((kStageBelts[stageKeyFor(45)] ?? const <int>[]).isNotEmpty, isTrue);
  });

  test('erken ZOR/RAHAT ritmi (L8-26): ZOR seviye normallerden ağır, RAHAT hafif', () {
    double pct(int n, int Function(LevelData) f) {
      int total = 0;
      int lower = 0;
      final o = f(LevelRepo.get(n));
      for (int m = n - 4; m <= n + 4; m++) {
        if (m == n || m < 8 || isHardLevel(m) || isReliefLevel(m)) continue;
        total++;
        if (f(LevelRepo.get(m)) < o) lower++;
      }
      return total == 0 ? 0.5 : lower / total;
    }

    for (int n = 8; n <= 26; n++) {
      if (!isHardLevel(n) && !isReliefLevel(n)) continue;
      final p = (pct(n, (l) => l.totalPassengers) + pct(n, (l) => l.ufos.length)) / 2;
      if (isHardLevel(n)) {
        expect(p >= 0.8, isTrue, reason: 'erken ZOR seviye $n zayif (yuzdelik $p)');
      } else {
        expect(p <= 0.2, isTrue, reason: 'erken RAHAT seviye $n agir (yuzdelik $p)');
      }
    }
  });

  test('erken sıra boyut rampası: 8-25 ortalama UFO sayısı < 26-45 < 46-70', () {
    double avg(int a, int b) {
      int s = 0;
      for (int n = a; n <= b; n++) {
        s += LevelRepo.get(n).ufos.length;
      }
      return s / (b - a + 1);
    }

    expect(avg(8, 25) < avg(26, 45), isTrue);
    expect(avg(26, 45) < avg(46, 70), isTrue);
  });
}
