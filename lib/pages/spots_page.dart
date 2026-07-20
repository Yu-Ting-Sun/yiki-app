import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';
import '../core/maps_launcher.dart';
import '../models/spot.dart';
import '../providers/spots_provider.dart';

/// 這趟收藏的景點：記錄行程時在「附近景點」按 ⭐ 加進來的清單。
/// 上半地圖（編號標記）+ 下半卡片；點卡片開 Google 地圖、可移除收藏。
class SpotsPage extends ConsumerWidget {
  final int tripId;

  const SpotsPage({super.key, required this.tripId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spots = ref.watch(savedSpotsProvider(tripId));

    return Scaffold(
      appBar: AppBar(title: const Text('收藏的景點')),
      body: spots.when(
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
                  onPressed: () => ref.invalidate(savedSpotsProvider(tripId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重試'),
                ),
              ],
            ),
          ),
        ),
        data: (list) => list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    '這趟還沒有收藏的景點\n\n'
                    '下次記錄行程時，打開「附近景點」\n按 ⭐ 把喜歡的地方加進來',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : _SavedSpotsBody(tripId: tripId, spots: list),
      ),
    );
  }
}

class _SavedSpotsBody extends ConsumerWidget {
  final int tripId;
  final List<Spot> spots;

  const _SavedSpotsBody({required this.tripId, required this.spots});

  Future<void> _remove(BuildContext context, WidgetRef ref, Spot s) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除收藏？'),
        content: Text('把「${s.name}」從這趟旅程移除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || s.id == null) return;
    try {
      await removeSavedSpot(ref.read(dioProvider), tripId, s.id!);
      messenger.showSnackBar(SnackBar(content: Text('已移除「${s.name}」')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      ref.invalidate(savedSpotsProvider(tripId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final coords = [for (final s in spots) LatLng(s.lat, s.lng)];

    return Column(
      children: [
        SizedBox(
          height: 240,
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.coordinates(
                coordinates: coords,
                padding: const EdgeInsets.all(48),
                maxZoom: 17,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.yiki.yiki_app',
              ),
              MarkerLayer(
                markers: [
                  for (final (i, s) in spots.indexed)
                    Marker(
                      point: LatLng(s.lat, s.lng),
                      width: 30,
                      height: 30,
                      child: GestureDetector(
                        onTap: () => openSpotInMaps(context, s),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: s.isFood
                                ? Colors.deepOrange
                                : theme.colorScheme.primary,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
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
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: spots.length,
            itemBuilder: (context, i) {
              final s = spots[i];
              final tint =
                  s.isFood ? Colors.deepOrange : theme.colorScheme.primary;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: tint.withValues(alpha: 0.15),
                    child: Icon(
                      s.isFood ? Icons.restaurant : Icons.place,
                      color: tint,
                    ),
                  ),
                  title: Row(
                    children: [
                      Flexible(child: Text(s.name)),
                      const SizedBox(width: 8),
                      if (s.category.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: tint.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            s.category,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: tint),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s.description.isNotEmpty) Text(s.description),
                      Text(s.distanceLabel, style: theme.textTheme.bodySmall),
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: '移除收藏',
                    icon: const Icon(Icons.bookmark_remove_outlined),
                    onPressed: () => _remove(context, ref, s),
                  ),
                  onTap: () => openSpotInMaps(context, s),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
