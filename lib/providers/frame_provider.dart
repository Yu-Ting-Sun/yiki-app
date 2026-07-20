import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';

/// 相框配對狀態；配對結果存 shared_preferences，重開 App 不用重配。
class FrameState {
  final bool paired;
  final int? frameId;
  final String name;
  final DateTime? lastSync;

  /// 後端目前可同步的旅程數（相框會整批同步全部旅程到 SD 卡）。
  final int tripCount;

  const FrameState({
    this.paired = false,
    this.frameId,
    this.name = '',
    this.lastSync,
    this.tripCount = 0,
  });
}

class FrameNotifier extends Notifier<FrameState> {
  static const _kId = 'frame_id';
  static const _kName = 'frame_name';

  @override
  FrameState build() {
    Future(() => _restore()); // build 必須同步，開機還原丟到下一輪
    return const FrameState();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_kId);
    if (id == null) return;
    state = FrameState(
      paired: true,
      frameId: id,
      name: prefs.getString(_kName) ?? '智慧相框',
    );
    try {
      await refresh(); // 順便抓 last_sync；後端連不上就先顯示本地資料
    } catch (_) {}
  }

  /// 用 6 位配對碼配對；失敗丟 DioException（頁面用 friendlyError 顯示）。
  Future<void> pair(String code) async {
    final dio = ref.read(dioProvider);
    final res = await dio.post('/frames/pair', data: {'pair_code': code});
    final id = res.data['frame_id'] as int;
    final name = res.data['name'] as String? ?? '智慧相框';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kId, id);
    await prefs.setString(_kName, name);

    state = FrameState(
      paired: true,
      frameId: id,
      name: name,
      lastSync: _parseTime(res.data['last_sync']),
      tripCount: res.data['trip_count'] as int? ?? 0,
    );
  }

  /// 重抓相框狀態（最後同步時間、可同步旅程數）。
  Future<void> refresh() async {
    final id = state.frameId;
    if (id == null) return;
    final res = await ref.read(dioProvider).get('/frames/$id');
    state = FrameState(
      paired: true,
      frameId: id,
      name: res.data['name'] as String? ?? state.name,
      lastSync: _parseTime(res.data['last_sync']),
      tripCount: res.data['trip_count'] as int? ?? 0,
    );
  }

  Future<void> unpair() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kId);
    await prefs.remove(_kName);
    state = const FrameState();
  }

  /// 「立即同步」：後端立旗，相框十秒內的門鈴輪詢會看到並開始下載。
  Future<void> requestSync() async {
    final id = state.frameId;
    if (id == null) throw StateError('not paired');
    await ref.read(dioProvider).post('/frames/$id/request-sync');
    try {
      await refresh();
    } catch (_) {}
  }

  static DateTime? _parseTime(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}

final frameProvider =
    NotifierProvider<FrameNotifier, FrameState>(FrameNotifier.new);
