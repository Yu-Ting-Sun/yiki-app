import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import 'frame_provider.dart';

/// 相框傳回的按讚事件：長輩對相框比讚（板端手勢辨識）→ 後端 → App 輪詢。
class LikeEvent {
  final int id;
  final int? tripId;
  final int? photoId;
  final String tripTitle;
  final String user;

  const LikeEvent({
    required this.id,
    this.tripId,
    this.photoId,
    this.tripTitle = '',
    this.user = '',
  });
}

/// 每 3 秒輪詢 GET `/frames/{id}/likes?after=<lastId>`；
/// state = 最新一筆新按讚（HomePage listen 到就跳通知橫幅）。
/// 第一次輪詢只記基準線，App 啟動前的舊讚不會跳通知。
class LikeFeedNotifier extends Notifier<LikeEvent?> {
  Timer? _timer;
  int _lastId = -1; // -1 = 還沒取得基準線

  @override
  LikeEvent? build() {
    // 只看 frameId：頁面刷新換 FrameState 物件時不重置輪詢狀態。
    final frameId = ref.watch(frameProvider.select((f) => f.frameId));

    _timer?.cancel();
    _lastId = -1;
    if (frameId != null) {
      _timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _poll(frameId),
      );
    }
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  Future<void> _poll(int frameId) async {
    try {
      final res = await ref.read(dioProvider).get(
        '/frames/$frameId/likes',
        queryParameters: {'after': _lastId < 0 ? 0 : _lastId},
      );
      final likes = (res.data['likes'] as List?) ?? const [];
      final lastId = res.data['last_id'] as int? ?? 0;

      if (_lastId < 0) {
        _lastId = lastId; // 基準線
        return;
      }
      if (likes.isEmpty) return;

      _lastId = lastId;
      final m = likes.last as Map;
      state = LikeEvent(
        id: m['id'] as int,
        tripId: m['trip_id'] as int?,
        photoId: m['photo_id'] as int?,
        tripTitle: m['trip_title'] as String? ?? '',
        user: m['user'] as String? ?? '',
      );
    } catch (_) {
      // 後端連不上就靜默跳過，下一輪再試。
    }
  }
}

final likeFeedProvider =
    NotifierProvider<LikeFeedNotifier, LikeEvent?>(LikeFeedNotifier.new);
