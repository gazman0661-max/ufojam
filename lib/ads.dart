import 'package:flutter/material.dart';

/// Booster'ı coinle almanın bedeli.
const int kBoosterCoinPrice = 250;

/// Ödüllü reklamların tek giriş noktası. Her ödüllü reklam önce "İzle / Vazgeç" onayından geçer.
class Ads {
  /// Onay penceresini gösterir; "İzle" denirse reklamı oynatır. true = reklam izlendi, ödül verilebilir.
  static Future<bool> watch(
    BuildContext context, {
    required String title,
    required String message,
    String watchLabel = 'İzle ▶',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1F4B),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text(message, style: const TextStyle(color: Colors.white70, fontSize: 15)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(watchLabel)),
        ],
      ),
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
