import 'package:flutter/material.dart';

import 'ui/game_popup.dart';

/// Booster'ı coinle almanın bedeli.
const int kBoosterCoinPrice = 250;

/// Ödüllü reklamların tek giriş noktası. Her ödüllü reklam önce "İzle / Vazgeç" onayından geçer.
class Ads {
  /// Onay penceresini gösterir; "İzle" denirse reklamı oynatır. true = reklam izlendi, ödül verilebilir.
  static Future<bool> watch(
    BuildContext context, {
    required String title,
    required String message,
    String watchLabel = 'İzle',
    String? emoji,
  }) async {
    // Ödüllü reklam isteğe bağlıdır: önce açıkça sorulur, "İzle" denmeden reklam açılmaz.
    final ok = await showGamePopup<bool>(
      context,
      emoji: emoji,
      icon: emoji == null ? Icons.ondemand_video_rounded : null,
      title: title,
      message: message,
      accent: const Color(0xFF2ECC8F),
      dismissible: true,
      buttons: [
        const PopupBtn<bool>('Vazgeç', kind: PopupKind.ghost, value: false),
        PopupBtn<bool>(watchLabel, icon: Icons.play_arrow_rounded, kind: PopupKind.reward, value: true),
      ],
    );
    if (ok != true || !context.mounted) return false;
    return play(context);
  }

  /// Reklamı oynatır (onay alındıktan sonra). TODO: gerçek reklam SDK'sı (ör. google_mobile_ads) burada çağrılacak.
  /// Şimdilik demo: reklam hemen "izlenmiş" sayılır.
  static Future<bool> play(BuildContext context) async {
    return true;
  }
}
