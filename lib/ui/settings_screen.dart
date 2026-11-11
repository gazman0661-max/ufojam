import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio.dart';
import '../settings.dart';
import '../legal.dart';
import 'panel_ui.dart';

/// Seçenekler sayfası.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Yayınlanmış adres varsa tarayıcıda açar; yoksa/açılamazsa uygulama içi metni gösterir.
  Future<void> _openDoc(String title, String url, List<String> sections) async {
    Audio.play(Sfx.click);
    final ok = await Legal.openUrl(url);
    if (ok || !mounted) return;
    _push(InfoScreen(title: title, sections: sections));
  }

  void _toggle(bool current, void Function(bool) set) {
    setState(() => set(!current));
    Settings.save();
    Audio.refresh();
    Audio.play(Sfx.click);
    // Titreşim açıksa (veya şimdi açıldıysa) küçük bir geri bildirim.
    Settings.vibe(HapticFeedback.selectionClick);
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return PanelScaffold(
      title: 'Seçenekler',
      children: [
        GlossyButton(
          label: 'Oyunlarımız ve\nUygulamalarımız',
          icon: Icons.grid_view_rounded,
          color: GlossyColor.orange,
          height: 86,
          onTap: () => _push(const OurGamesScreen()),
        ),
        const PanelSection('SES'),
        GlossyButton(label: 'Müzik', checked: Settings.music, onTap: () => _toggle(Settings.music, (v) => Settings.music = v)),
        const PanelGap(),
        GlossyButton(label: 'Ses Efektleri', checked: Settings.sfx, onTap: () => _toggle(Settings.sfx, (v) => Settings.sfx = v)),
        const PanelSection('CİHAZ'),
        GlossyButton(label: 'Titreşim', checked: Settings.vibration, onTap: () => _toggle(Settings.vibration, (v) => Settings.vibration = v)),
        const PanelGap(),
        GlossyButton(label: 'Ekran Efektleri', checked: Settings.screenFx, onTap: () => _toggle(Settings.screenFx, (v) => Settings.screenFx = v)),
        const PanelSection('DİL'),
        GlossyButton(label: 'TÜRKÇE', icon: Icons.language_rounded, onTap: _languageDialog),
        const PanelSection('YARDIM'),
        GlossyButton(label: 'Nasıl Oynanır?', icon: Icons.help_outline_rounded, onTap: () => _push(const HowToPlayScreen())),
        const PanelSection('GİZLİLİK'),
        GlossyButton(label: 'Reklam Rızasını Yönet', icon: Icons.shield_outlined, onTap: _consentDialog),
        const PanelSection('HAKKINDA'),
        GlossyButton(
          label: 'Kullanım Şartları',
          onTap: () => _openDoc('Kullanım Şartları', kTermsUrl, kTermsText),
        ),
        const PanelGap(),
        GlossyButton(
          label: 'Gizlilik Politikası',
          onTap: () => _openDoc('Gizlilik Politikası', kPrivacyUrl, kPrivacyText),
        ),
        const SizedBox(height: 26),
        const Center(
          child: Text(
            'UFO Bus Jam  •  v$kAppVersion',
            style: TextStyle(color: kSectionColor, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
        ),
      ],
    );
  }

  void _languageDialog() {
    showPanelDialog(
      context,
      title: 'Dil',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF7CE38B)),
            SizedBox(width: 10),
            Text('Türkçe', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
          SizedBox(height: 12),
          Row(children: [
            Icon(Icons.radio_button_unchecked_rounded, color: Colors.white38),
            SizedBox(width: 10),
            Text('English  (yakında)', style: TextStyle(color: Colors.white38, fontSize: 17, fontWeight: FontWeight.w700)),
          ]),
        ],
      ),
    );
  }

  void _consentDialog() {
    showPanelDialog(
      context,
      title: 'Reklam Rızası',
      content: const Text(
        'Oyunda şu an reklam bulunmuyor. Reklam eklendiğinde rıza tercihlerini buradan yönetebileceksin.',
        style: TextStyle(color: Colors.white70, fontSize: 15.5, height: 1.4),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Oyunlarımız ve Uygulamalarımız
// ---------------------------------------------------------------------------

/// Oyunlarımız listesi. İçini doldurmak için buraya yeni kayıt eklemek yeterli.
/// [asset] boşsa "yakında" simgesi çıkar; [current] true ise "Şu an oynuyorsun" etiketi.
class OurApp {
  final String title;
  final String subtitle;
  final String? asset;
  final bool current;
  const OurApp({required this.title, required this.subtitle, this.asset, this.current = false});
}

const List<OurApp> kOurApps = [
  OurApp(
    title: 'UFO Bus Jam',
    subtitle: 'Yolcuları doğru UFO\'ya bindir!',
    asset: 'assets/img/ufo10_blue.webp',
    current: true,
  ),
  OurApp(title: 'Yeni oyun', subtitle: 'Çok yakında...'),
  OurApp(title: 'Yeni uygulama', subtitle: 'Çok yakında...'),
];

class OurGamesScreen extends StatelessWidget {
  const OurGamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PanelScaffold(
      title: 'Oyunlarımız',
      children: [
        const PanelText('Daha fazlası yolda! Buradan diğer oyun ve uygulamalarımıza göz atabileceksin.'),
        const PanelGap(14),
        for (final a in kOurApps) ...[
          _AppCard(app: a),
          const PanelGap(14),
        ],
      ],
    );
  }
}

class _AppCard extends StatelessWidget {
  final OurApp app;
  const _AppCard({required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withAlpha(26), Colors.white.withAlpha(10)],
        ),
        border: Border.all(color: Colors.white.withAlpha(app.current ? 140 : 55), width: app.current ? 2 : 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.black.withAlpha(70),
              border: Border.all(color: Colors.white.withAlpha(40)),
            ),
            padding: const EdgeInsets.all(6),
            child: app.asset != null
                ? Image.asset(app.asset!, fit: BoxFit.contain)
                : const Icon(Icons.help_outline_rounded, color: Colors.white38, size: 40),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.title,
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  app.subtitle,
                  style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (app.current) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: const Color(0xFF7C4DFF),
                    ),
                    child: const Text(
                      'Şu an oynuyorsun',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nasıl oynanır / bilgi sayfaları
// ---------------------------------------------------------------------------

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PanelScaffold(
      title: 'Nasıl Oynanır?',
      children: [
        PanelText('1. UFO\'ya dokun', heading: true),
        PanelText('Izgaradaki bir UFO\'ya dokununca UFO, alttaki park yerlerinden birine süzülür.'),
        PanelText('2. Yolcular biner', heading: true),
        PanelText('Halkada dönen yolcular, rengi uyan park etmiş UFO\'ya ışınla biner.'),
        PanelText('3. UFO dolunca uçar', heading: true),
        PanelText('Bir UFO\'nun tüm koltukları dolunca yolcularıyla uçup gider ve park yeri boşalır.'),
        PanelText('4. Yerin bitmesin', heading: true),
        PanelText('Park yerlerin dolmadan tüm yolcuları bindirmeye çalış. Kazanınca coin kazanır, sonraki seviyeye geçersin.'),
        PanelText('Takılınca', heading: true),
        PanelText('Hemen Bin, Karıştır ve Işınla güçlendiricileri sıkıştığın anda işe yarar. Stok bitince yenisini kazanabilirsin.'),
      ],
    );
  }
}

/// Başlık + paragraf listesinden oluşan düz bilgi sayfası.
/// sections: [başlık, metin, başlık, metin, ...] sırasıyla.
class InfoScreen extends StatelessWidget {
  final String title;
  final List<String> sections;
  const InfoScreen({super.key, required this.title, required this.sections});

  @override
  Widget build(BuildContext context) {
    final kids = <Widget>[];
    for (int i = 0; i + 1 < sections.length; i += 2) {
      kids.add(PanelText(sections[i], heading: true));
      kids.add(PanelText(sections[i + 1]));
    }
    return PanelScaffold(title: title, children: kids);
  }
}
