import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/gps_point.dart';
import 'frame_provider.dart';

/// GPS 記錄狀態機：idle → starting（要權限、建旅程）→ tracking → ending → idle。
enum TrackingStatus { idle, starting, tracking, ending }

/// 權限或定位服務的問題，頁面收到後顯示引導（開啟設定）。
class TrackingException implements Exception {
  final String message;

  /// true = 要去系統「App 權限」頁；false = 要開手機的定位服務。
  final bool needAppSettings;

  const TrackingException(this.message, {this.needAppSettings = false});

  @override
  String toString() => message;
}

class TrackingState {
  final TrackingStatus status;
  final int? tripId;

  /// 本次行程的全部點（畫即時軌跡用）；上傳另有批次緩衝。
  final List<GpsPoint> points;
  final double distanceM;
  final Duration elapsed;

  const TrackingState({
    this.status = TrackingStatus.idle,
    this.tripId,
    this.points = const [],
    this.distanceM = 0,
    this.elapsed = Duration.zero,
  });

  bool get isTracking => status == TrackingStatus.tracking;

  LatLng? get lastLatLng =>
      points.isEmpty ? null : LatLng(points.last.lat, points.last.lng);

  String get distanceLabel => distanceM < 1000
      ? '${distanceM.round()} 公尺'
      : '${(distanceM / 1000).toStringAsFixed(2)} 公里';

  TrackingState copyWith({
    TrackingStatus? status,
    int? tripId,
    List<GpsPoint>? points,
    double? distanceM,
    Duration? elapsed,
  }) =>
      TrackingState(
        status: status ?? this.status,
        tripId: tripId ?? this.tripId,
        points: points ?? this.points,
        distanceM: distanceM ?? this.distanceM,
        elapsed: elapsed ?? this.elapsed,
      );
}

class TrackingNotifier extends Notifier<TrackingState> {
  StreamSubscription<Position>? _positionSub;
  Timer? _ticker;
  DateTime? _startedAt;

  /// 待上傳緩衝：每滿 gpsBatchSize 批次 POST 一次，失敗塞回等下一批重試。
  final List<GpsPoint> _pending = [];

  static const _distance = Distance();

  @override
  TrackingState build() => const TrackingState();

  /// 權限 OK 才建旅程、開串流。權限問題丟 TrackingException 給頁面引導；
  /// 網路問題丟 DioException（頁面用 friendlyError 顯示）。
  Future<void> start() async {
    if (state.status != TrackingStatus.idle) return;
    state = state.copyWith(status: TrackingStatus.starting);
    try {
      await _ensurePermission();

      // 標題在這裡就定好（手機本地時間），避免後端用 UTC 日期
      // 產生錯一天的預設標題，也讓同一天的多趟行程分得出來。
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final title =
          '${now.month}月${now.day}日 ${two(now.hour)}:${two(now.minute)} 出發';

      final dio = ref.read(dioProvider);
      // 旅程歸屬到目前配對的相框（沒配對＝不限相框，所有相框都同步得到）
      final frameId = ref.read(frameProvider).frameId;
      final res = await dio.post('/trips/start', data: {
        'title': title,
        'frame_id': ?frameId,
      });
      final tripId = res.data['trip_id'] as int;

      _startedAt = DateTime.now();
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: AppConstants.gpsDistanceFilterM,
        ),
      ).listen(_onPosition, onError: (_) {});
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_startedAt != null) {
          state = state.copyWith(
            elapsed: DateTime.now().difference(_startedAt!),
          );
        }
      });

      state = TrackingState(status: TrackingStatus.tracking, tripId: tripId);
    } catch (_) {
      _cleanup();
      state = const TrackingState();
      rethrow;
    }
  }

  /// 結束行程：停串流、補上傳剩餘點、POST /end。回傳 trip_id 供跳轉詳情頁。
  Future<int> stop() async {
    final tripId = state.tripId;
    if (tripId == null || state.status != TrackingStatus.tracking) {
      throw StateError('not tracking');
    }
    state = state.copyWith(status: TrackingStatus.ending);
    await _positionSub?.cancel();
    _ticker?.cancel();

    await _flush();
    if (_pending.isNotEmpty) await _flush(); // 失敗再試一次

    try {
      await ref.read(dioProvider).post('/trips/$tripId/end');
    } finally {
      // 就算 /end 失敗也重置：旅程與點都已在伺服器上，之後可從清單進入。
      _cleanup();
      state = const TrackingState();
    }
    return tripId;
  }

  Future<void> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const TrackingException('手機的定位服務沒開，請先開啟定位');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      throw const TrackingException(
        '定位權限被永久拒絕，請到系統設定開啟「憶起」的位置權限',
        needAppSettings: true,
      );
    }
    if (perm == LocationPermission.denied) {
      throw const TrackingException('沒有定位權限，無法記錄行程');
    }
  }

  void _onPosition(Position pos) {
    if (!state.isTracking) return;
    final pt = GpsPoint(
      lat: pos.latitude,
      lng: pos.longitude,
      timestamp: pos.timestamp,
    );
    double added = 0;
    if (state.points.isNotEmpty) {
      final last = state.points.last;
      added = _distance.as(
        LengthUnit.Meter,
        LatLng(last.lat, last.lng),
        LatLng(pt.lat, pt.lng),
      );
    }
    _pending.add(pt);
    state = state.copyWith(
      points: [...state.points, pt],
      distanceM: state.distanceM + added,
    );
    if (_pending.length >= AppConstants.gpsBatchSize) {
      _flush(); // fire-and-forget，失敗會塞回 _pending
    }
  }

  Future<void> _flush() async {
    if (_pending.isEmpty || state.tripId == null) return;
    final batch = List<GpsPoint>.from(_pending);
    _pending.clear();
    try {
      await ref.read(dioProvider).post(
        '/trips/${state.tripId}/points',
        data: {'points': [for (final p in batch) p.toJson()]},
      );
    } catch (_) {
      _pending.insertAll(0, batch);
    }
  }

  void _cleanup() {
    _positionSub?.cancel();
    _positionSub = null;
    _ticker?.cancel();
    _ticker = null;
    _startedAt = null;
    _pending.clear();
  }
}

final trackingProvider =
    NotifierProvider<TrackingNotifier, TrackingState>(TrackingNotifier.new);
