import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/spot.dart';

/// 用 Google 地圖開啟景點：Android 先試 geo:（跳原生地圖 App、帶名稱標籤），
/// 不行再退到 Google Maps 網頁版。
Future<void> openSpotInMaps(BuildContext context, Spot s) async {
  final messenger = ScaffoldMessenger.of(context);
  final label = Uri.encodeComponent(s.name);
  final geo = Uri.parse('geo:${s.lat},${s.lng}?q=${s.lat},${s.lng}($label)');
  final web = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${s.lat}%2C${s.lng}');
  try {
    if (await launchUrl(geo)) return;
  } catch (_) {}
  try {
    if (await launchUrl(web, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  messenger.showSnackBar(const SnackBar(content: Text('無法開啟地圖 App')));
}
