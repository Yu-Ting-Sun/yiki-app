import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/trip.dart';
import '../providers/trips_provider.dart';

/// 旅程清單：GET /trips 卡片列表 + 下拉重新整理 + 左滑刪除（確認 dialog）。
class TripsPage extends ConsumerWidget {
  const TripsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(tripsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的旅程')),
      body: trips.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(tripsProvider),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(tripsProvider.future),
          child: list.isEmpty
              ? ListView(
                  // 空清單也要能下拉重新整理
                  children: const [
                    SizedBox(height: 160),
                    Center(child: Text('還沒有旅程，去「記錄」開始第一趟吧！')),
                  ],
                )
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) =>
                      _DismissibleTripCard(trip: list[i]),
                ),
        ),
      ),
    );
  }
}

class _DismissibleTripCard extends ConsumerWidget {
  final TripSummary trip;

  const _DismissibleTripCard({required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('trip-${trip.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.only(right: 24),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.delete,
          color: Theme.of(context).colorScheme.onError,
        ),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('刪除旅程？'),
          content: Text(
            '「${trip.title.isEmpty ? '未命名旅程' : trip.title}」'
            '的軌跡與照片都會一併刪除，無法復原。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('刪除'),
            ),
          ],
        ),
      ),
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await ref.read(dioProvider).delete('/trips/${trip.id}');
          messenger.showSnackBar(const SnackBar(content: Text('旅程已刪除')));
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
        } finally {
          // 成功要移掉、失敗要把卡片變回來，都靠重抓清單
          ref.invalidate(tripsProvider);
        }
      },
      child: _TripCard(trip: trip),
    );
  }
}

class _TripCard extends StatelessWidget {
  final TripSummary trip;

  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final date = trip.startTime?.toLocal() ?? trip.createdAt.toLocal();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: trip.coverPhotoId != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  '${AppConstants.apiBaseUrl}/photos/${trip.coverPhotoId}',
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) =>
                      const CircleAvatar(child: Text('📷')),
                ),
              )
            : const CircleAvatar(child: Text('🚶')),
        title: Text(trip.title.isEmpty ? '未命名旅程' : trip.title),
        subtitle: Text(
          '${DateFormat('yyyy/M/d HH:mm').format(date)} · ${trip.distanceLabel}'
          '${trip.hasStory ? ' · 已有遊記' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go('/trips/${trip.id}'),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重試'),
            ),
          ],
        ),
      ),
    );
  }
}
