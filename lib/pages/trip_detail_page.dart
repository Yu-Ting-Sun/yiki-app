import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';
import '../core/photo_exif.dart';
import '../models/photo.dart';
import '../models/trip.dart';
import '../providers/faces_provider.dart';
import '../providers/photo_provider.dart';
import '../providers/trips_provider.dart';

/// 旅程詳情：軌跡地圖（Polyline + 起訖 + 照片標記）、照片橫列、遊記區塊。
class TripDetailPage extends ConsumerWidget {
  final int tripId;

  const TripDetailPage({super.key, required this.tripId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(tripDetailProvider(tripId));

    return Scaffold(
      appBar: AppBar(title: const Text('旅程詳情')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(friendlyError(e), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(tripDetailProvider(tripId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重試'),
                ),
              ],
            ),
          ),
        ),
        data: (trip) => RefreshIndicator(
          onRefresh: () => ref.refresh(tripDetailProvider(tripId).future),
          child: _DetailBody(trip: trip),
        ),
      ),
    );
  }
}

void _showPhotoViewer(BuildContext context, Photo photo) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(8),
      child: Stack(
        children: [
          InteractiveViewer(
            child: Center(
              child: Image.network(
                photo.fullUrl,
                fit: BoxFit.contain,
                loadingBuilder: (c, child, p) => p == null
                    ? child
                    : const Padding(
                        padding: EdgeInsets.all(48),
                        child: CircularProgressIndicator(),
                      ),
                errorBuilder: (c, e, s) => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Text('照片載入失敗',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 參加者編輯 dialog：從「家人臉譜」已註冊的名單勾選（FilterChip），
/// 不用打字、也不會拼錯導致相框對不上。已存在但未註冊臉譜的舊名字
/// 仍會出現在選項裡（可取消勾選）。儲存回傳勾選清單。
class _MembersDialog extends ConsumerStatefulWidget {
  final List<String> initial;

  const _MembersDialog({required this.initial});

  @override
  ConsumerState<_MembersDialog> createState() => _MembersDialogState();
}

class _MembersDialogState extends ConsumerState<_MembersDialog> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faces = ref.watch(facesProvider);

    return AlertDialog(
      title: const Text('這趟旅程有誰參加？'),
      content: SizedBox(
        width: double.maxFinite,
        child: faces.when(
          loading: () => const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text(friendlyError(e)),
          data: (list) {
            // 臉譜名單 ∪ 目前參加者（涵蓋還沒註冊臉譜的舊名字）
            final options = {...list.map((f) => f.label), ...widget.initial}
                .toList()
              ..sort();
            if (options.isEmpty) {
              return const Text(
                '還沒有可選的家人。\n\n'
                '先到「相框」頁的「家人臉譜」\n上傳自拍註冊，再回來勾選。',
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final name in options)
                      FilterChip(
                        avatar: _selected.contains(name)
                            ? null
                            : const Icon(Icons.face, size: 18),
                        label: Text(name),
                        selected: _selected.contains(name),
                        onSelected: (v) => setState(() =>
                            v ? _selected.add(name) : _selected.remove(name)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '相框認出勾選的人，就會播這趟旅程',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: const Text('儲存'),
        ),
      ],
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final TripDetail trip;

  const _DetailBody({required this.trip});

  /// 編輯參加者：從已註冊的「家人臉譜」勾選 → PUT /trips/{id}/members。
  /// 名字與臉譜同源，相框認出誰就播誰參加過的旅程。
  Future<void> _editMembers(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final tripId = trip.summary.id;

    final members = await showDialog<List<String>>(
      context: context,
      builder: (_) => _MembersDialog(initial: trip.members),
    );
    if (members == null) return; // 取消
    try {
      await ref.read(dioProvider).put(
        '/trips/$tripId/members',
        data: {'members': members},
      );
      ref.invalidate(tripDetailProvider(tripId));
      messenger.showSnackBar(const SnackBar(content: Text('參加者已更新')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = trip.summary;
    final start = s.startTime?.toLocal();
    final theme = Theme.of(context);
    final track = [for (final p in trip.points) LatLng(p.lat, p.lng)];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          s.title.isEmpty ? '未命名旅程' : s.title,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        if (start != null) Text(DateFormat('yyyy/M/d HH:mm').format(start)),
        const SizedBox(height: 4),
        // 參加者：相框 label.json 的來源，人臉辨識靠它決定播誰的回憶
        Row(
          children: [
            Icon(Icons.group, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                trip.members.isEmpty
                    ? '還沒標記參加的人'
                    : trip.members.join('、'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: () => _editMembers(context, ref),
              child: const Text('編輯'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (track.isNotEmpty || trip.photos.any((p) => p.lat != null))
          SizedBox(
            height: 280,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _TrackMap(
                track: track,
                photos: trip.photos,
                color: theme.colorScheme.primary,
              ),
            ),
          )
        else
          Container(
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text('這趟旅程沒有記錄到軌跡點'),
          ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Info(label: '距離', value: s.distanceLabel),
                _Info(label: '軌跡點', value: '${s.pointCount}'),
                _Info(label: '照片', value: '${s.photoCount}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => context.push('/trips/${s.id}/spots'),
          icon: const Icon(Icons.bookmark),
          label: const Text('收藏的景點'),
        ),
        const SizedBox(height: 16),
        _PhotosSection(trip: trip),
        const SizedBox(height: 16),
        _StorySection(trip: trip),
        const SizedBox(height: 32),
      ],
    );
  }
}

/// 照片區塊：橫向縮圖列 + 「補照片」——旅程結束後也能從相簿多選補上傳，
/// 座標與拍攝時間從 EXIF 讀（沒有座標就不上地圖，仍會出現在照片列）。
class _PhotosSection extends ConsumerStatefulWidget {
  final TripDetail trip;

  const _PhotosSection({required this.trip});

  @override
  ConsumerState<_PhotosSection> createState() => _PhotosSectionState();
}

class _PhotosSectionState extends ConsumerState<_PhotosSection> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final messenger = ScaffoldMessenger.of(context);
    List<XFile> picked;
    try {
      // 不壓縮：保留 EXIF（GPS 座標、拍攝時間）
      picked = await ImagePicker().pickMultiImage();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('無法開啟相簿')));
      return;
    }
    if (picked.isEmpty) return;
    await _upload(picked);
  }

  Future<void> _upload(List<XFile> files) async {
    final messenger = ScaffoldMessenger.of(context);
    final tripId = widget.trip.summary.id;
    final dio = ref.read(dioProvider);
    setState(() => _uploading = true);

    final failed = <XFile>[];
    for (final f in files) {
      try {
        final bytes = await f.readAsBytes();
        final gps = await exifLatLng(bytes);
        final ts = await exifDateTime(bytes);
        await uploadTripPhoto(
          dio: dio,
          tripId: tripId,
          bytes: bytes,
          filename: f.name,
          lat: gps?.lat,
          lng: gps?.lng,
          timestamp: ts,
        );
      } catch (_) {
        failed.add(f);
      }
    }

    ref.invalidate(tripDetailProvider(tripId));
    ref.invalidate(tripsProvider); // 封面/張數變了
    if (!mounted) return;
    setState(() => _uploading = false);
    if (failed.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text('已補上 ${files.length} 張照片 📷')),
      );
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text('${failed.length} 張照片上傳失敗'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: '重試', onPressed: () => _upload(failed)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final photos = widget.trip.photos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('照片', style: theme.textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate, size: 20),
              label: Text(_uploading ? '上傳中…' : '新增照片'),
            ),
          ],
        ),
        if (photos.isEmpty)
          Container(
            height: 72,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('還沒有照片，從相簿新增幾張吧'),
          )
        else
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final photo = photos[i];
                return GestureDetector(
                  onTap: () => _showPhotoViewer(context, photo),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      photo.fullUrl,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, st) => Container(
                        width: 96,
                        height: 96,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// 遊記區塊：沒有遊記 → 「AI 生成遊記」；有 → 內文 + 編輯按鈕。
class _StorySection extends ConsumerStatefulWidget {
  final TripDetail trip;

  const _StorySection({required this.trip});

  @override
  ConsumerState<_StorySection> createState() => _StorySectionState();
}

class _StorySectionState extends ConsumerState<_StorySection> {
  bool _generating = false;

  Future<void> _generate() async {
    final messenger = ScaffoldMessenger.of(context);
    final tripId = widget.trip.summary.id;
    setState(() => _generating = true);
    try {
      await ref.read(dioProvider).post(
            '/trips/$tripId/story/generate',
            options: Options(
              // 看照片(vision)+查真實地點，比純文字久一些
              receiveTimeout: const Duration(seconds: 90),
            ),
          );
      ref.invalidate(tripDetailProvider(tripId));
      ref.invalidate(tripsProvider); // has_story 變了
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final story = widget.trip.storyText;
    final tripId = widget.trip.summary.id;

    if (story.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('遊記', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Center(
            child: Column(
              children: [
                FilledButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: _generating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Text(_generating ? 'AI 撰寫中…' : 'AI 生成遊記'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '用這趟旅程的軌跡與照片，讓 AI 幫你寫下回憶（約需幾秒）',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('遊記', style: theme.textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: () => context.push('/trips/$tripId/story'),
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('編輯'),
            ),
          ],
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(story, style: theme.textTheme.bodyLarge?.copyWith(height: 1.7)),
          ),
        ),
      ],
    );
  }
}

class _TrackMap extends StatelessWidget {
  final List<LatLng> track;
  final List<Photo> photos;
  final Color color;

  const _TrackMap({
    required this.track,
    required this.photos,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final located = [
      for (final p in photos)
        if (p.lat != null && p.lng != null) p
    ];
    final allPoints = [
      ...track,
      for (final p in located) LatLng(p.lat!, p.lng!),
    ];

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: allPoints,
          padding: const EdgeInsets.all(40),
          maxZoom: 17, // 單點或超短軌跡時避免縮放爆表
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.yiki.yiki_app',
        ),
        if (track.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(points: track, strokeWidth: 5, color: color),
            ],
          ),
        MarkerLayer(
          markers: [
            if (track.isNotEmpty)
              Marker(
                point: track.first,
                width: 36,
                height: 36,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.trip_origin, color: Colors.green),
              ),
            if (track.length >= 2)
              Marker(
                point: track.last,
                width: 36,
                height: 36,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.flag, color: Colors.red),
              ),
            // 照片標記：點擊看大圖
            for (final p in located)
              Marker(
                point: LatLng(p.lat!, p.lng!),
                width: 32,
                height: 32,
                child: GestureDetector(
                  onTap: () => _showPhotoViewer(context, p),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Icon(Icons.photo_camera, size: 18, color: color),
                  ),
                ),
              ),
          ],
        ),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
        ),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  final String label;
  final String value;

  const _Info({required this.label, required this.value});

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
