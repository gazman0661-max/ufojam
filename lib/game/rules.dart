import 'models.dart';
import 'stage_extras.dart';

/// Kural katmanı: hangi seviyede hangi özel kural var. Hepsi seviye numarasından ve sabit LCG'den üretilir
/// (aynı seviye hep aynı).
///
/// TESTERE DİŞİ KORUMASI (zorluk eğrisi):
/// - RAHAT seviye (zordan sonraki) HİÇBİR özel kural almaz (nefes).
/// - Normal seviyeler seyrek ve az, ZOR seviyeler sık ve çok alır: kurallar eğriyi bozmaz, tepeleri keskinleştirir.
/// - Dönen / arızalı UFO sadece ek baskıdır: hiçbiri seviyeyi kolaylaştırmaz ve çözülebilirliği bozmaz
///   (dönen UFO: gövde simetrik + özgün yön her turda geri gelir; arızalı UFO: bozulunca belli sayıda hamle sonra
///   aynı yere geri döner. İkisi de tools/solve_layers.py'daki çözücü varsayımlarıyla uyumlu).
///
/// - Hamle bütçesi: L16 tanıtım, sonra sadece ZOR seviyelerin ~%50'si.
/// - Dönen UFO: L21 tanıtım; sonra normal ~%40, ZOR ~%90.
/// - Arızalı UFO: L32 tanıtım; sonra normal ~%30, ZOR ~%75.
/// - Bant UFO: L45 tanıtım; sonra normal ~%20, ZOR ~%60 (bant sığacak boş yeri olan düzenlerde).
const int kBudgetChanceNormal = 0; // normal seviyelerde yok: hamle sınırı sıkıcı olmasın, sadece ZOR seviyelerde
const int kBudgetChanceHard = 50;
const int kRotorChanceNormal = 40;
const int kRotorChanceHard = 90;
const int kFaultyChanceNormal = 30;
const int kFaultyChanceHard = 75;
const int kBeltChanceNormal = 20;
const int kBeltChanceHard = 60;

class _Rng {
  int s;
  _Rng(int seed) : s = seed & 0x7fffffff;
  int next() {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    return s >> 8;
  }

  int below(int n) => next() % n;
}

/// [stage]: düzen anahtarı (stage_extras.dart aday listeleri buradan), [ufoCount]: seviyedeki UFO sayısı.
LevelRules buildRules(int n, int stage, int ufoCount) {
  if (isReliefLevel(n)) return LevelRules.none;
  final hard = isHardLevel(n);
  final mechs = <Mech>[];

  // ---- hamle bütçesi
  int moveBudget = 0;
  final bUnlock = kMechUnlock[Mech.budget]!;
  if (n >= bUnlock) {
    bool on = n == bUnlock;
    if (!on) {
      final r = _Rng(n * 7919 + 17);
      on = r.below(100) < (hard ? kBudgetChanceHard : kBudgetChanceNormal);
    }
    if (on) {
      // Pay: L16'da 9, her 10 seviyede 1 azalır, en az 3; ZOR seviyede 2 daha az (en az 3).
      int slack = 9 - (n - bUnlock) ~/ 10;
      if (slack < 3) slack = 3;
      if (hard) {
        slack = slack - 2;
        if (slack < 3) slack = 3;
      }
      moveBudget = ufoCount + slack;
      mechs.add(Mech.budget);
    }
  }

  final used = <int>{};

  // ---- dönen UFO
  List<int> rotors = const <int>[];
  double rotorOn = 3.4;
  double rotorOff = 1.8;
  final rUnlock = kMechUnlock[Mech.rotor]!;
  if (n >= rUnlock) {
    final r = _Rng(n * 6271 + 5);
    final cand = kStageRotors[stage] ?? const <int>[];
    final on = n == rUnlock || r.below(100) < (hard ? kRotorChanceHard : kRotorChanceNormal);
    if (on && cand.isNotEmpty) {
      int want;
      if (n == rUnlock) {
        want = 1;
      } else if (hard) {
        final mx = 3 + (n - 26) ~/ 60; // 3..5
        want = 2 + r.below((mx > 5 ? 5 : mx) - 1);
      } else {
        final mx = 1 + (n - rUnlock) ~/ 60; // 1..3
        want = 1 + r.below(mx > 3 ? 3 : mx);
      }
      final pick = <int>[];
      for (final id in cand) {
        if (pick.length >= want) break;
        pick.add(id);
      }
      if (pick.isNotEmpty) {
        rotors = pick;
        used.addAll(pick);
        mechs.add(Mech.rotor);
        // ZOR: özgün yönde kalma süresi kısa (doğru anı yakalamak zorlaşır). Normal: rahat.
        rotorOn = hard ? 2.6 : 3.4;
        rotorOff = hard ? 2.0 : 1.8;
      }
    }
  }

  // ---- arızalı UFO
  final faulty = <int, int>{};
  int faultSlack = 6;
  final fUnlock = kMechUnlock[Mech.faulty]!;
  if (n >= fUnlock) {
    final r = _Rng(n * 4177 + 29);
    final cand = kStageFaulty[stage] ?? const <int>[];
    final on = n == fUnlock || r.below(100) < (hard ? kFaultyChanceHard : kFaultyChanceNormal);
    if (on && cand.isNotEmpty) {
      int want;
      if (n == fUnlock) {
        want = 1;
      } else if (hard) {
        want = 2 + r.below(2); // 2..3
      } else {
        want = 1 + r.below(2); // 1..2
      }
      // Pay: ilk seviyede cömert (7), zamanla 4'e iner; ZOR seviyede 4.
      int slack = 7 - (n - fUnlock) ~/ 30;
      if (slack < 4) slack = 4;
      if (hard) slack = 4;
      faultSlack = slack;
      for (int i = 0; i + 1 < cand.length && faulty.length < want; i += 2) {
        final id = cand[i];
        if (used.contains(id)) continue;
        faulty[id] = cand[i + 1] + slack; // sayaç = önündeki engel zinciri + pay
        used.add(id);
      }
      if (faulty.isNotEmpty) mechs.add(Mech.faulty);
    }
  }

  // ---- bant UFO
  List<int> belts = const <int>[];
  double beltWin = 0.3;
  final bUnlock2 = kMechUnlock[Mech.belt]!;
  if (n >= bUnlock2) {
    final r = _Rng(n * 3571 + 41);
    final cand = kStageBelts[stage] ?? const <int>[];
    final on = n == bUnlock2 || r.below(100) < (hard ? kBeltChanceHard : kBeltChanceNormal);
    if (on && cand.isNotEmpty) {
      final want = n == bUnlock2 ? 1 : (hard ? 2 + r.below(2) : 1 + r.below(2));
      final pick = <int>[];
      for (final id in cand) {
        if (pick.length >= want) break;
        if (used.contains(id)) continue;
        pick.add(id);
      }
      if (pick.isNotEmpty) {
        belts = pick;
        used.addAll(pick);
        mechs.add(Mech.belt);
        beltWin = hard ? 0.22 : 0.3; // ZOR: pencere dar
      }
    }
  }

  if (mechs.isEmpty) return LevelRules.none;
  return LevelRules(
    mechs: mechs,
    moveBudget: moveBudget,
    rotors: rotors,
    rotorOn: rotorOn,
    rotorOff: rotorOff,
    faulty: faulty,
    faultSlack: faultSlack,
    belts: belts,
    beltWin: beltWin,
  );
}

/// Seviyeye uygulanacak kurallar.
LevelRules rulesFor(int number, int stage, List<UfoSpec> ufos) => buildRules(number, stage, ufos.length);
