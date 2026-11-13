import 'package:flutter/material.dart';

import '../audio.dart';
import '../l10n.dart';
import '../legal.dart';
import 'panel_ui.dart';
import 'settings_screen.dart' show InfoScreen;

/// İlk açılışta gösterilen Kullanım Şartları + Gizlilik Politikası penceresi.
/// true: kabul edildi (kaydedildi). false: reddedildi (oyun kapatılır).
/// Pencere dışına dokunarak ya da geri tuşuyla kapatılamaz.
Future<bool> showLegalConsent(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withAlpha(175),
    builder: (_) => const _LegalDialog(),
  );
  if (r == true) {
    await Legal.accept();
    return true;
  }
  await Legal.quit();
  return false;
}

class _LegalDialog extends StatelessWidget {
  const _LegalDialog();

  Future<void> _read(BuildContext context, String title, String url, List<String> sections) async {
    Audio.play(Sfx.click);
    final ok = await Legal.openUrl(url);
    if (ok || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => InfoScreen(title: title, sections: sections)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF2A1466), kPanelBg],
                ),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withAlpha(70), width: 1.5),
                boxShadow: const [BoxShadow(color: Color(0x887C4DFF), blurRadius: 28, spreadRadius: -4)],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: Image.asset('assets/img/ufo10_blue.webp', height: 84, fit: BoxFit.contain)),
                    const SizedBox(height: 8),
                    Text(
                      L.t('Hoş Geldin!', 'Welcome!'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        shadows: [
                          Shadow(blurRadius: 0, color: Color(0xFF2A1466), offset: Offset(0, 2)),
                          Shadow(blurRadius: 6, color: Color(0xAA000000), offset: Offset(0, 3)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      L.t('Oynamaya başlamadan önce Kullanım Şartları\'nı ve Gizlilik Politikası\'nı okuyup kabul etmen gerekiyor.',
                          'Before you start playing, you need to read and accept the Terms of Use and the Privacy Policy.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withAlpha(220),
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _DocTile(
                      icon: Icons.description_rounded,
                      label: L.t('Kullanım Şartları', 'Terms of Use'),
                      onTap: () => _read(context, L.t('Kullanım Şartları', 'Terms of Use'), kTermsUrl, kTermsText),
                    ),
                    const SizedBox(height: 10),
                    _DocTile(
                      icon: Icons.shield_rounded,
                      label: L.t('Gizlilik Politikası', 'Privacy Policy'),
                      onTap: () => _read(context, L.t('Gizlilik Politikası', 'Privacy Policy'), kPrivacyUrl, kPrivacyText),
                    ),
                    const SizedBox(height: 18),
                    GlossyButton(
                      label: L.t('Kabul Et', 'Accept'),
                      height: 60,
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                    const SizedBox(height: 12),
                    _RejectButton(onTap: () => Navigator.of(context).pop(false)),
                    const SizedBox(height: 10),
                    Text(
                      L.t('Kabul Et\'e dokunarak her ikisini de kabul etmiş olursun. Reddedersen oyun kapanır.',
                          'By tapping Accept, you accept both of them. If you decline, the game will close.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 12.5, height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Oku" satırı: yarı saydam cam kart, solda simge, sağda ok.
class _DocTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DocTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withAlpha(55), width: 1.2),
          ),
          child: Row(
            children: [
              Icon(icon, color: kSectionColor, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              Text(L.t('Oku', 'Read'), style: TextStyle(color: kSectionColor.withAlpha(220), fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, color: kSectionColor, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reddet: ana düğmeden daha sönük, çerçeveli (vurgu "Kabul Et"te).
class _RejectButton extends StatefulWidget {
  final VoidCallback onTap;
  const _RejectButton({required this.onTap});

  @override
  State<_RejectButton> createState() => _RejectButtonState();
}

class _RejectButtonState extends State<_RejectButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
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
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF2A1466).withAlpha(200),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withAlpha(110), width: 2),
          ),
          child: Text(
            L.t('Reddet', 'Decline'),
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.5),
          ),
        ),
      ),
    );
  }
}
