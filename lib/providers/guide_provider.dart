import 'package:dio/dio.dart';

import '../models/spot.dart';

/// 小憶的一則對話（使用者或精靈）。
class GuideMessage {
  final bool fromUser;
  final String text;
  final List<Spot> spots;

  const GuideMessage({
    required this.fromUser,
    required this.text,
    this.spots = const [],
  });
}

/// 小憶的回覆：文字 + 動作標籤（wave/point/talk/think）+ 附帶景點。
class GuideReply {
  final String reply;
  final String action;
  final List<Spot> spots;

  const GuideReply({required this.reply, required this.action, required this.spots});

  factory GuideReply.fromJson(Map<String, dynamic> json) => GuideReply(
        reply: json['reply'] as String? ?? '',
        action: json['action'] as String? ?? 'talk',
        spots: (json['spots'] as List? ?? [])
            .map((s) => Spot.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

/// 問小憶。lat/lng 是目前位置（找附近、介紹這裡時用）。
Future<GuideReply> askGuide(
  Dio dio,
  String message, {
  double? lat,
  double? lng,
}) async {
  final res = await dio.post(
    '/guide/ask',
    data: {'message': message, 'lat': ?lat, 'lng': ?lng},
    options: Options(receiveTimeout: const Duration(seconds: 60)),
  );
  return GuideReply.fromJson(res.data as Map<String, dynamic>);
}
