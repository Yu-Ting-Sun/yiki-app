import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api_client.dart';
import '../providers/trips_provider.dart';

/// 遊記全文編輯：TextField 編輯 → PUT /trips/{id}/story 儲存。
class StoryEditPage extends ConsumerStatefulWidget {
  final int tripId;

  const StoryEditPage({super.key, required this.tripId});

  @override
  ConsumerState<StoryEditPage> createState() => _StoryEditPageState();
}

class _StoryEditPageState extends ConsumerState<StoryEditPage> {
  final TextEditingController _controller = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).put(
        '/trips/${widget.tripId}/story',
        data: {'story_text': _controller.text.trim()},
      );
      ref.invalidate(tripDetailProvider(widget.tripId));
      ref.invalidate(tripsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('遊記已儲存')));
      if (mounted) context.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(tripDetailProvider(widget.tripId));

    // 詳情載入後把現有遊記帶進編輯框（只做一次，不蓋掉使用者輸入）
    detail.whenData((trip) {
      if (!_initialized) {
        _controller.text = trip.storyText;
        _initialized = true;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('編輯遊記'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('儲存'),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(friendlyError(e), textAlign: TextAlign.center),
          ),
        ),
        data: (_) => Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(height: 1.7),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '寫下這趟旅程的回憶…',
            ),
          ),
        ),
      ),
    );
  }
}
