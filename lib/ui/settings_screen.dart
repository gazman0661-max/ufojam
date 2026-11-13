import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio.dart';
import '../l10n.dart';
import '../settings.dart';
import '../legal.dart';
import '../stats.dart';
import 'game_popup.dart';
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
      title: L.t('Seçenekler', 'Options'),
      children: [
        GlossyButton(
          label: L.t('Oyunlarımız ve\nUygulamalarımız', 'Our Games &\nApps'),
          icon: Icons.grid_view_rounded,
          color: GlossyColor.orange,
          height: 86,
          onTap: () => _push(const OurGamesScreen()),
        ),
        PanelSection(L.t('SES', 'SOUND')),
        GlossyButton(label: L.t('Müzik', 'Music'), checked: Settings.music, onTap: () => _toggle(Settings.music, (v) => Settings.music = v)),
        const PanelGap(),
        GlossyButton(label: L.t('Ses Efektleri', 'Sound Effects'), checked: Settings.sfx, onTap: () => _toggle(Settings.sfx, (v) => Settings.sfx = v)),
        PanelSection(L.t('CİHAZ', 'DEVICE')),
        GlossyButton(label: L.t('Titreşim', 'Vibration'), checked: Settings.vibration, onTap: () => _toggle(Settings.vibration, (v) => Settings.vibration = v)),
        const PanelGap(),
        GlossyButton(label: L.t('Ekran Efektleri', 'Screen Effects'), checked: Settings.screenFx, onTap: () => _toggle(Settings.screenFx, (v) => Settings.screenFx = v)),
        PanelSection(L.t('DİL', 'LANGUAGE')),
        GlossyButton(label: L.isTr ? 'TÜRKÇE' : 'ENGLISH', icon: Icons.language_rounded, onTap: _languageDialog),
        PanelSection(L.t('YARDIM', 'HELP')),
        GlossyButton(label: L.t('Nasıl Oynanır?', 'How to Play'), icon: Icons.help_outline_rounded, onTap: () => _push(const HowToPlayScreen())),
        PanelSection(L.t('İSTATİSTİKLER', 'STATISTICS')),
        GlossyButton(label: L.t('Seviye ve Reklam İstatistikleri', 'Level & Ad Statistics'), icon: Icons.insights_rounded, onTap: _statsDialog),
        PanelSection(L.t('GİZLİLİK', 'PRIVACY')),
        GlossyButton(label: L.t('Reklam Rızasını Yönet', 'Manage Ad Consent'), icon: Icons.shield_outlined, onTap: _consentDialog),
        PanelSection(L.t('HAKKINDA', 'ABOUT')),
        GlossyButton(
          label: L.t('Kullanım Şartları', 'Terms of Use'),
          onTap: () => _openDoc(L.t('Kullanım Şartları', 'Terms of Use'), kTermsUrl, kTermsText),
        ),
        const PanelGap(),
        GlossyButton(
          label: L.t('Gizlilik Politikası', 'Privacy Policy'),
          onTap: () => _openDoc(L.t('Gizlilik Politikası', 'Privacy Policy'), kPrivacyUrl, kPrivacyText),
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
      title: L.t('Dil', 'Language'),
      content: Builder(
        builder: (dialogCtx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _langRow(dialogCtx, AppLang.tr, 'Türkçe'),
            const SizedBox(height: 12),
            _langRow(dialogCtx, AppLang.en, 'English'),
          ],
        ),
      ),
    );
  }

  Widget _langRow(BuildContext dialogCtx, AppLang lang, String name) {
    final selected = L.lang == lang;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        Audio.play(Sfx.click);
        Navigator.of(dialogCtx).pop();
        await L.setLang(lang); // tüm ekranlar yeniden çizilir
        if (mounted) setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(
            selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: selected ? const Color(0xFF7CE38B) : Colors.white38,
          ),
          const SizedBox(width: 10),
          Text(
            name,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 17,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ]),
      ),
    );
  }

  /// Cihazdaki seviye / reklam istatistiklerini gösterir; JSON olarak kopyalanabilir.
  void _statsDialog() {
    Audio.play(Sfx.click);
    showGamePopup<void>(
      context,
      icon: Icons.insights_rounded,
      title: L.t('İstatistikler', 'Statistics'),
      dismissible: true,
      stacked: true,
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(
          child: Text(
            Stats.report(),
            style: const TextStyle(color: Colors.white70, fontSize: 14.5, height: 1.4),
          ),
        ),
      ),
      buttons: [
        PopupBtn<void>(
          L.t('Veriyi kopyala (JSON)', 'Copy data (JSON)'),
          icon: Icons.copy_rounded,
          kind: PopupKind.reward,
          onTap: (ctx) async {
            await Clipboard.setData(ClipboardData(text: Stats.toJson()));
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
        PopupBtn<void>(
          L.t('Sıfırla', 'Reset'),
          icon: Icons.delete_outline_rounded,
          kind: PopupKind.danger,
          onTap: (ctx) async {
            await Stats.reset();
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
        ),
        PopupBtn<void>(L.t('Kapat', 'Close'), kind: PopupKind.ghost),
      ],
    );
  }

  void _consentDialog() {
    showPanelDialog(
      context,
      title: L.t('Reklam Rızası', 'Ad Consent'),
      content: Text(
        L.t('Oyunda şu an reklam bulunmuyor. Reklam eklendiğinde rıza tercihlerini buradan yönetebileceksin.',
            'There are no ads in the game right now. When ads are added, you will be able to manage your consent preferences here.'),
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

List<OurApp> get kOurApps => [
  OurApp(
    title: 'UFO Bus Jam',
    subtitle: L.t('Yolcuları doğru UFO\'ya bindir!', 'Get the passengers on the right UFO!'),
    asset: 'assets/img/ufo10_blue.webp',
    current: true,
  ),
  OurApp(title: L.t('Yeni oyun', 'New game'), subtitle: L.t('Çok yakında...', 'Coming soon...')),
  OurApp(title: L.t('Yeni uygulama', 'New app'), subtitle: L.t('Çok yakında...', 'Coming soon...')),
];

class OurGamesScreen extends StatelessWidget {
  const OurGamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PanelScaffold(
      title: L.t('Oyunlarımız', 'Our Games'),
      children: [
        PanelText(L.t('Daha fazlası yolda! Buradan diğer oyun ve uygulamalarımıza göz atabileceksin.',
            'More is on the way! You will be able to check out our other games and apps here.')),
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
                    child: Text(
                      L.t('Şu an oynuyorsun', 'Playing now'),
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
    return PanelScaffold(
      title: L.t('Nasıl Oynanır?', 'How to Play'),
      children: [
        PanelText(L.t('1. UFO\'ya dokun', '1. Tap a UFO'), heading: true),
        PanelText(L.t('Izgaradaki bir UFO\'ya dokununca UFO, alttaki park yerlerinden birine süzülür.',
            'Tap a UFO on the grid and it glides down into one of the parking slots below.')),
        PanelText(L.t('2. Yolcular biner', '2. Passengers board'), heading: true),
        PanelText(L.t('Halkada dönen yolcular, rengi uyan park etmiş UFO\'ya ışınla biner.',
            'Passengers circling on the ring beam up into the parked UFO that matches their color.')),
        PanelText(L.t('3. UFO dolunca uçar', '3. A full UFO takes off'), heading: true),
        PanelText(L.t('Bir UFO\'nun tüm koltukları dolunca yolcularıyla uçup gider ve park yeri boşalır.',
            'When all the seats of a UFO are filled, it flies off with its passengers and the parking slot frees up.')),
        PanelText(L.t('4. Yerin bitmesin', '4. Don\'t run out of space'), heading: true),
        PanelText(L.t('Park yerlerin dolmadan tüm yolcuları bindirmeye çalış. Kazanınca coin kazanır, sonraki seviyeye geçersin.',
            'Try to board every passenger before your parking slots fill up. When you win, you earn coins and move on to the next level.')),
        PanelText(L.t('Takılınca', 'When you\'re stuck'), heading: true),
        PanelText(L.t('Hemen Bin, Karıştır ve Işınla güçlendiricileri sıkıştığın anda işe yarar. Stok bitince yenisini kazanabilirsin.',
            'The Board Now, Shuffle and Teleport boosters come in handy when you get stuck. When your stock runs out, you can earn more.')),
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
