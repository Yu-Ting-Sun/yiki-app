import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';
import '../core/maps_launcher.dart';
import '../core/photo_exif.dart';
import '../models/spot.dart';
import '../providers/photo_provider.dart';
import '../providers/spots_provider.dart';
import '../providers/tracking_provider.dart';
import '../providers/trips_provider.dart';

/// GPS 記錄頁：開始行程 → 即時地圖跟隨 + 距離/時間 → 結束跳詳情。
class TrackingPage extends ConsumerStatefulWidget {
  const TrackingPage({super.key});

  @override
  ConsumerState<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends ConsumerState<TrackingPage> {
  final MapController _mapController = MapController();
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// 拍照（相機）或選相簿照片，附上座標後上傳到目前的行程。
  /// 相機照片用目前 GPS；相簿照片優先用 EXIF 座標，沒有才用目前位置。
  Future<void> _addPhoto(ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    final tripId = ref.read(trackingProvider).tripId;
    if (tripId == null) return;

    XFile? shot;
    try {
      // 相簿不壓縮：image_picker 帶壓縮參數會把 EXIF（含 GPS）剝掉
      shot = await _picker.pickImage(
        source: source,
        imageQuality: source == ImageSource.camera ? 85 : null,
        maxWidth: source == ImageSource.camera ? 1920 : null,
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(source == ImageSource.camera ? '無法開啟相機' : '無法開啟相簿'),
      ));
      return;
    }
    if (shot == null) return; // 使用者取消

    final bytes = await shot.readAsBytes();
    double? lat;
    double? lng;
    if (source == ImageSource.gallery) {
      final gps = await exifLatLng(bytes);
      lat = gps?.lat;
      lng = gps?.lng;
    }
    final current = ref.read(trackingProvider).lastLatLng;
    lat ??= current?.latitude;
    lng ??= current?.longitude;

    await _uploadPhoto(
      tripId: tripId,
      bytes: bytes,
      filename: shot.name,
      lat: lat,
      lng: lng,
    );
  }

  Future<void> _uploadPhoto({
    required int tripId,
    required Uint8List bytes,
    required String filename,
    double? lat,
    double? lng,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await uploadTripPhoto(
        dio: ref.read(dioProvider),
        tripId: tripId,
        bytes: bytes,
        filename: filename,
        lat: lat,
        lng: lng,
        timestamp: DateTime.now(),
      );
      messenger.showSnackBar(const SnackBar(content: Text('照片已上傳 📷')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('照片上傳失敗：${friendlyError(e)}'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '重試',
          onPressed: () => _uploadPhoto(
            tripId: tripId,
            bytes: bytes,
            filename: filename,
            lat: lat,
            lng: lng,
          ),
        ),
      ));
    }
  }

  Future<void> _start() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(trackingProvider.notifier).start();
    } on TrackingException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        action: SnackBarAction(
          label: '開啟設定',
          onPressed: () => e.needAppSettings
              ? Geolocator.openAppSettings()
              : Geolocator.openLocationSettings(),
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _stop() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('結束行程？'),
        content: const Text('結束後就不能再繼續這趟記錄囉。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('再走走'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('結束'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final tripId = await ref.read(trackingProvider.notifier).stop();
      ref.invalidate(tripsProvider);
      if (mounted) context.go('/trips/$tripId');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  void _showNearbySpots() {
    final pos = ref.read(trackingProvider).lastLatLng;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('還沒定位到你的位置，再等一下下')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: _NearbySpotsSheet(lat: pos.latitude, lng: pos.longitude),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracking = ref.watch(trackingProvider);

    // 地圖跟隨最新位置
    ref.listen(trackingProvider.select((s) => s.lastLatLng), (prev, next) {
      if (next != null && ref.read(trackingProvider).isTracking) {
        try {
          _mapController.move(next, 17);
        } catch (_) {
          // 地圖還沒 attach（第一個點比地圖先到）時忽略
        }
      }
    });

    final active = tracking.status == TrackingStatus.tracking ||
        tracking.status == TrackingStatus.ending;

    return Scaffold(
      appBar: AppBar(title: const Text('記錄行程')),
      body: active ? _buildTracking(tracking) : _buildIdle(tracking),
    );
  }

  Widget _buildIdle(TrackingState tracking) {
    final starting = tracking.status == TrackingStatus.starting;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.travel_explore,
            size: 96,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text('準備好出發了嗎？',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: starting ? null : _start,
            icon: starting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Text(starting ? '正在定位…' : '開始行程',
                  style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '走到哪記到哪，回家講給家人聽',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildTracking(TrackingState tracking) {
    final ending = tracking.status == TrackingStatus.ending;
    final center = tracking.lastLatLng ?? const LatLng(23.9738, 120.9820);
    final theme = Theme.of(context);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: center, initialZoom: 17),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.yiki.yiki_app',
            ),
            if (tracking.points.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [
                      for (final p in tracking.points) LatLng(p.lat, p.lng)
                    ],
                    strokeWidth: 5,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            if (tracking.lastLatLng != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: tracking.lastLatLng!,
                    width: 20,
                    height: 20,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.primary,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
            const SimpleAttributionWidget(
              source: Text('OpenStreetMap contributors'),
            ),
          ],
        ),
        // 上方統計卡
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Stat(label: '距離', value: tracking.distanceLabel),
                  _Stat(label: '時間', value: _fmtDuration(tracking.elapsed)),
                  _Stat(label: '軌跡點', value: '${tracking.points.length}'),
                ],
              ),
            ),
          ),
        ),
        // 附近景點：走路時「現在附近有什麼？」，點了直接開 Google 地圖繞過去
        Positioned(
          bottom: 92,
          right: 24,
          child: FloatingActionButton.extended(
            heroTag: 'nearby-spots',
            onPressed: _showNearbySpots,
            icon: const Icon(Icons.place),
            label: const Text('附近景點'),
          ),
        ),
        // 下方按鈕列
        Positioned(
          bottom: 24,
          left: 24,
          right: 24,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ending ? null : () => _addPhoto(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('拍照'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: theme.colorScheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 從相簿選（用 EXIF 座標）
              IconButton.outlined(
                onPressed: ending ? null : () => _addPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surface,
                  padding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: ending ? null : _stop,
                  icon: ending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.stop),
                  label: Text(ending ? '儲存中…' : '結束行程'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _fmtDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }
}

/// 「附近有什麼」bottom sheet：以目前位置查 /spots/nearby，
/// 點任一項直接開 Google 地圖。
class _NearbySpotsSheet extends ConsumerStatefulWidget {
  final double lat;
  final double lng;

  const _NearbySpotsSheet({required this.lat, required this.lng});

  @override
  ConsumerState<_NearbySpotsSheet> createState() => _NearbySpotsSheetState();
}

class _NearbySpotsSheetState extends ConsumerState<_NearbySpotsSheet> {
  List<Spot>? _spots;
  Object? _error;
  bool _describing = false; // AI 介紹產生中（清單已可用）
  final Set<String> _saved = {}; // 這次已收藏的景點名（按過就變實心書籤）

  /// 把景點收藏進目前的行程（旅程詳情會顯示收藏清單）。
  Future<void> _saveSpot(Spot s) async {
    final messenger = ScaffoldMessenger.of(context);
    final tripId = ref.read(trackingProvider).tripId;
    if (tripId == null) return;
    setState(() => _saved.add(s.name)); // 樂觀更新，失敗再收回
    try {
      final duplicate =
          await saveSpotToTrip(ref.read(dioProvider), tripId, s);
      messenger.showSnackBar(SnackBar(
        content: Text(duplicate ? '「${s.name}」已經在旅程裡了' : '已收藏「${s.name}」到這趟旅程 ⭐'),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      if (mounted) setState(() => _saved.remove(s.name));
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 兩段式：先快拿清單顯示，再背景補 AI 介紹、回來後就地更新。
  /// refresh=true（重新推薦）：保留舊清單直到新的一組回來，後端從候選池
  /// 換組（不重打 Overpass），幾乎瞬間完成。
  Future<void> _load({bool refresh = false}) async {
    setState(() {
      if (!refresh) _spots = null;
      _error = null;
    });
    final dio = ref.read(dioProvider);
    try {
      final fast = await fetchNearbySpots(
        dio, widget.lat, widget.lng, refresh: refresh);
      if (!mounted) return;
      setState(() => _spots = fast);

      if (fast.isNotEmpty && fast.any((s) => s.description.isEmpty)) {
        setState(() => _describing = true);
        try {
          final described = await fetchNearbySpots(
            dio, widget.lat, widget.lng, describe: true);
          if (!mounted) return;
          setState(() {
            _spots = described;
            _describing = false;
          });
        } catch (_) {
          // 介紹是加分項，失敗就維持沒有介紹的清單
          if (mounted) setState(() => _describing = false);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text('附近有什麼', style: theme.textTheme.titleLarge),
              const SizedBox(width: 12),
              if (_describing)
                Expanded(
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text('AI 介紹撰寫中…',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                )
              else
                const Spacer(),
              IconButton(
                tooltip: '重新推薦',
                onPressed: (_spots == null || _describing)
                    ? null
                    : () => _load(refresh: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildBody(theme)),
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(friendlyError(_error!), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('重試'),
              ),
            ],
          ),
        ),
      );
    }
    final spots = _spots;
    if (spots == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在看看附近有什麼…'),
          ],
        ),
      );
    }
    if (spots.isEmpty) {
      return const Center(child: Text('這附近沒有找到景點或美食'));
    }
    return ListView.builder(
      itemCount: spots.length,
      itemBuilder: (context, i) {
        final s = spots[i];
        final tint = s.isFood ? Colors.deepOrange : theme.colorScheme.primary;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: tint.withValues(alpha: 0.15),
            child: Icon(
              s.isFood ? Icons.restaurant : Icons.place,
              color: tint,
            ),
          ),
          title: Text(s.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.description.isNotEmpty) Text(s.description),
              Text(
                '${s.category} · 離你約 ${s.distanceM < 1000 ? '${s.distanceM.round()} 公尺' : '${(s.distanceM / 1000).toStringAsFixed(1)} 公里'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          // ⭐ 收藏進這趟旅程；點列本身開 Google 地圖
          trailing: IconButton(
            tooltip: '收藏到這趟旅程',
            icon: Icon(
              _saved.contains(s.name)
                  ? Icons.bookmark
                  : Icons.bookmark_add_outlined,
              color: _saved.contains(s.name) ? tint : null,
            ),
            onPressed:
                _saved.contains(s.name) ? null : () => _saveSpot(s),
          ),
          onTap: () => openSpotInMaps(context, s),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
