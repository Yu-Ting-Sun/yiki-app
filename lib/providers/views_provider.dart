import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import 'frame_provider.dart';

/// 一筆觀看紀錄：相框認出誰站在前面，他正在看哪本相簿。
class FrameView {
  final int id;
  final String user; // 相框人臉辨識的名字
  final int? tripId;
  final String tripTitle;
  final DateTime? createdAt;

  const FrameView({
    required this.id,
    required this.user,
    this.tripId,
    this.tripTitle = '',
    this.createdAt,
  });

  factory FrameView.fromJson(Map j) => FrameView(
        id: j['id'] as int,
        user: j['user'] as String? ?? '',
        tripId: j['trip_id'] as int?,
        tripTitle: j['trip_title'] as String? ?? '',
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
      );
}

/// 相框最近的觀看紀錄（新的在前）；沒配對回空清單。
final viewsProvider = FutureProvider.autoDispose<List<FrameView>>((ref) async {
  final frameId = ref.watch(frameProvider.select((f) => f.frameId));
  if (frameId == null) return const [];
  final dio = ref.watch(dioProvider);
  final res = await dio.get(
    '/frames/$frameId/views',
    queryParameters: {'newest': true, 'limit': 20},
  );
  return (res.data['views'] as List? ?? [])
      .map((j) => FrameView.fromJson(j as Map))
      .toList();
});
