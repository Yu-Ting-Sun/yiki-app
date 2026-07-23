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

/// 問小憶。lat/lng 是目前位置；history 是最近幾輪對話（讓指代解得開）。
Future<GuideReply> askGuide(
  Dio dio,
  String message, {
  double? lat,
  double? lng,
  int? frameId,
  List<GuideMessage> history = const [],
}) async {
  // 只送最近 5 輪（10 則），讓後端有記憶又不爆 token。
  final recent =
      history.length > 10 ? history.sublist(history.length - 10) : history;
  final res = await dio.post(
    '/guide/ask',
    data: {
      'message': message,
      'lat': ?lat,
      'lng': ?lng,
      'frame_id': ?frameId, // 配對中的相框（「幫我同步相框」工具用）
      'history': [
        for (final m in recent)
          {'role': m.fromUser ? 'user' : 'guide', 'text': m.text},
      ],
    },
    options: Options(receiveTimeout: const Duration(seconds: 60)),
  );
  return GuideReply.fromJson(res.data as Map<String, dynamic>);
}
