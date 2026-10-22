import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import 'frame_provider.dart';

/// 長輩對相框說「跟女兒說…」，相框小憶記下來的留言（後端 frame_messages）。
class FrameMessage {
  final int id;
  final int frameId; // 哪台相框留的（聽原音的端點要）
  final String user; // 誰留的（相框人臉辨識的名字，"" = 沒認出）
  final String to; // 給誰（女兒、全家…長輩自己的稱呼）
  final String text; // 小憶整理成長輩口吻的留言
  final bool hasAudio; // 能聽長輩講這句話的原音
  final int? tripId;
  final String tripTitle; // 留言時相框正在播的相簿
  final DateTime? createdAt;

  const FrameMessage({
    required this.id,
    required this.frameId,
    this.user = '',
    this.to = '',
    this.text = '',
    this.hasAudio = false,
    this.tripId,
    this.tripTitle = '',
    this.createdAt,
  });

  factory FrameMessage.fromJson(Map j, {int frameId = 0}) => FrameMessage(
        id: j['id'] as int,
        frameId: j['frame_id'] as int? ?? frameId,
        user: j['user'] as String? ?? '',
        to: j['to'] as String? ?? '',
        text: j['text'] as String? ?? '',
        hasAudio: j['has_audio'] as bool? ?? false,
        tripId: j['trip_id'] as int?,
        tripTitle: j['trip_title'] as String? ?? '',
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
      );
}

/// 每 3 秒輪詢 GET `/frames/{id}/messages?after=<lastId>`（跟按讚同一套）；
/// state = 最新一則新留言（HomePage listen 到就跳通知橫幅）。
/// 第一次輪詢只記基準線：App 啟動前的舊留言不跳通知，在相框頁的列表看。
class MessageFeedNotifier extends Notifier<FrameMessage?> {
  Timer? _timer;
  int _lastId = -1; // -1 = 還沒取得基準線

  @override
  FrameMessage? build() {
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
        '/frames/$frameId/messages',
        queryParameters: {'after': _lastId < 0 ? 0 : _lastId},
      );
      final messages = (res.data['messages'] as List?) ?? const [];
      final lastId = res.data['last_id'] as int? ?? 0;

      if (_lastId < 0) {
        _lastId = lastId; // 基準線
        return;
      }
      if (messages.isEmpty) return;

      _lastId = lastId;
      ref.invalidate(messagesProvider); // 相框頁的列表跟著更新
      final latest = FrameMessage.fromJson(messages.last as Map,
          frameId: frameId);
      if (latest.tripId != null) {
        ref.invalidate(tripMessagesProvider(latest.tripId!)); // 那趟的頁面也是
      }
      state = latest;
    } catch (_) {
      // 後端連不上就靜默跳過，下一輪再試。
    }
  }
}

final messageFeedProvider =
    NotifierProvider<MessageFeedNotifier, FrameMessage?>(
        MessageFeedNotifier.new);

/// 相框頁的留言列表：最近 20 則，新的在前。
final messagesProvider =
    FutureProvider.autoDispose<List<FrameMessage>>((ref) async {
  final frameId = ref.watch(frameProvider.select((f) => f.frameId));
  if (frameId == null) return const [];
  final res = await ref.watch(dioProvider).get(
    '/frames/$frameId/messages',
    queryParameters: {'newest': true, 'limit': 20},
  );
  return ((res.data['messages'] as List?) ?? const [])
      .map((j) => FrameMessage.fromJson(j as Map, frameId: frameId))
      .toList();
});

/// 一趟旅程的留言（旅程詳情頁）：長輩看著這本相簿留的話。
final tripMessagesProvider =
    FutureProvider.autoDispose.family<List<FrameMessage>, int>(
        (ref, tripId) async {
  final res = await ref.watch(dioProvider).get('/trips/$tripId/messages');
  return ((res.data['messages'] as List?) ?? const [])
      .map((j) => FrameMessage.fromJson(j as Map))
      .toList();
});

/// 長輩講這則留言的原音（後端已轉成 MP3、音量拉到正常）。
Future<Uint8List> fetchMessageAudio(Dio dio, int frameId, int messageId) async {
  final res = await dio.get(
    '/frames/$frameId/messages/$messageId/audio',
    options: Options(
      responseType: ResponseType.bytes,
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  return Uint8List.fromList(res.data as List<int>);
}
