import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../providers/faces_provider.dart';
import '../providers/frame_provider.dart';

/// 相框同步頁：未配對 → 輸入 6 位配對碼；已配對 → 顯示相框狀態。
/// 推播在旅程詳情頁的「推播到相框」。
class FramePage extends ConsumerStatefulWidget {
  const FramePage({super.key});

  @override
  ConsumerState<FramePage> createState() => _FramePageState();
}

class _FramePageState extends ConsumerState<FramePage> {
  final TextEditingController _codeController = TextEditingController();
  bool _pairing = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final code = _codeController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (code.length != 6) {
      messenger.showSnackBar(const SnackBar(content: Text('配對碼是 6 位數字')));
      return;
    }
    setState(() => _pairing = true);
    try {
      await ref.read(frameProvider.notifier).pair(code);
      _codeController.clear();
      messenger.showSnackBar(const SnackBar(content: Text('配對成功 🎉')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final frame = ref.watch(frameProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('智慧相框')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: frame.paired
              ? _buildPaired(theme, frame)
              : _buildUnpaired(theme),
        ),
      ),
    );
  }

  Widget _buildUnpaired(ThemeData theme) {
    return Column(
      children: [
        Icon(Icons.filter_frames, size: 96, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Text('配對你的相框', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '輸入相框螢幕上顯示的 6 位配對碼',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: 220,
          child: TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, letterSpacing: 8),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              counterText: '',
              hintText: '______',
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _pairing ? null : _pair,
          icon: _pairing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link),
          label: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(_pairing ? '配對中…' : '配對相框'),
          ),
        ),
      ],
    );
  }

  Widget _buildPaired(ThemeData theme, FrameState frame) {
    final lastSync = frame.lastSync?.toLocal();
    return Column(
      children: [
        Icon(Icons.filter_frames, size: 96, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(frame.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Chip(
          avatar: const Icon(Icons.check_circle, color: Colors.green, size: 18),
          label: const Text('已配對'),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _StatusRow(
                  label: '最後同步',
                  value: lastSync != null
                      ? DateFormat('yyyy/M/d HH:mm').format(lastSync)
                      : '還沒同步過',
                ),
                const Divider(),
                _StatusRow(label: '可同步旅程', value: '${frame.tripCount} 趟'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SyncNowButton(frame: frame),
        const SizedBox(height: 8),
        Text(
          '按下同步後，相框會在幾秒內開始\n下載你的旅程（遊記＋照片）到記憶卡',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref.read(frameProvider.notifier).refresh();
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(friendlyError(e))),
                  );
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重新整理'),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () => ref.read(frameProvider.notifier).unpair(),
              icon: const Icon(Icons.link_off),
              label: const Text('解除配對'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _FacesSection(),
      ],
    );
  }
}

/// 立即同步：通知後端立旗，相框的門鈴輪詢（每 10 秒）看到就開始下載。
class _SyncNowButton extends ConsumerStatefulWidget {
  final FrameState frame;

  const _SyncNowButton({required this.frame});

  @override
  ConsumerState<_SyncNowButton> createState() => _SyncNowButtonState();
}

class _SyncNowButtonState extends ConsumerState<_SyncNowButton> {
  bool _busy = false;

  Future<void> _sync() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(frameProvider.notifier).requestSync();
      messenger.showSnackBar(SnackBar(
        content: Text('已通知「${widget.frame.name}」，'
            '相框幾秒內會開始同步 📡'),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _busy ? null : _sync,
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
      label: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(_busy ? '通知中…' : '立即同步'),
      ),
    );
  }
}

/// 新增家人 dialog：自己持有 TextEditingController（在這裡 dispose，
/// 避免外層在關閉動畫還沒跑完時就把 controller 釋放掉）。
/// 回傳 (名字, 自拍來源)；取消回 null。
class _AddFaceDialog extends StatefulWidget {
  const _AddFaceDialog();

  @override
  State<_AddFaceDialog> createState() => _AddFaceDialogState();
}

class _AddFaceDialogState extends State<_AddFaceDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(ImageSource source) {
    Navigator.pop(context, (_controller.text.trim(), source));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新增家人'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: '名字（英數字）',
          hintText: '例：dad',
          helperText: '要跟旅程「參加者」用同一個名字\n（相框檔名限制：英數字、_、-）',
          helperMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        OutlinedButton.icon(
          onPressed: () => _submit(ImageSource.gallery),
          icon: const Icon(Icons.photo_library, size: 18),
          label: const Text('選自拍'),
        ),
        FilledButton.icon(
          onPressed: () => _submit(ImageSource.camera),
          icon: const Icon(Icons.camera_alt, size: 18),
          label: const Text('拍自拍'),
        ),
      ],
    );
  }
}

/// 家人臉譜：上傳自拍讓相框認得家人。
/// 名字要跟旅程「參加者」一致——相框認出誰，就播誰參加過的旅程。
class _FacesSection extends ConsumerStatefulWidget {
  const _FacesSection();

  @override
  ConsumerState<_FacesSection> createState() => _FacesSectionState();
}

class _FacesSectionState extends ConsumerState<_FacesSection> {
  bool _uploading = false;

  Future<void> _addFace() async {
    final messenger = ScaffoldMessenger.of(context);

    // 1. 問名字 + 選來源（controller 生命週期由 dialog widget 自己管）
    final result = await showDialog<(String, ImageSource)>(
      context: context,
      builder: (_) => const _AddFaceDialog(),
    );
    if (result == null) return;
    final (label, source) = result;
    if (!faceLabelRe.hasMatch(label)) {
      messenger.showSnackBar(const SnackBar(
        content: Text('名字只能用英數字、底線、連字號（1-23 字元）'),
      ));
      return;
    }

    // 2. 拍/選自拍（相簿可多張，最多 8）
    final picker = ImagePicker();
    List<XFile> photos;
    try {
      if (source == ImageSource.camera) {
        final shot = await picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.front,
        );
        photos = shot == null ? [] : [shot];
      } else {
        photos = await picker.pickMultiImage(limit: 8);
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('無法開啟相機/相簿')));
      return;
    }
    if (photos.isEmpty) return;
    if (photos.length > 8) photos = photos.sublist(0, 8);

    // 3. 上傳（後端轉 raw，相框同步 + 重開機後生效）
    setState(() => _uploading = true);
    try {
      await enrollFace(ref.read(dioProvider), label, photos);
      ref.invalidate(facesProvider);
      messenger.showSnackBar(SnackBar(
        content: Text('已註冊「$label」（${photos.length} 張自拍）。'
            '相框下次同步並重開機後就認得了 👀'),
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeFace(FaceInfo face) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除家人臉譜？'),
        content: Text('相框將不再辨識「${face.label}」。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await deleteFace(ref.read(dioProvider), face.label);
      messenger.showSnackBar(SnackBar(content: Text('已刪除「${face.label}」')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      ref.invalidate(facesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faces = ref.watch(facesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('家人臉譜', style: theme.textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: _uploading ? null : _addFace,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add, size: 20),
              label: Text(_uploading ? '上傳中…' : '新增家人'),
            ),
          ],
        ),
        faces.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text(
            friendlyError(e),
            style: theme.textTheme.bodySmall,
          ),
          data: (list) => list.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '還沒有註冊家人。\n上傳自拍後，相框就認得誰站在面前，'
                    '自動播他參加過的旅程回憶。',
                  ),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final f in list)
                      InputChip(
                        avatar: const Icon(Icons.face, size: 18),
                        label: Text('${f.label}（${f.photoCount} 張）'),
                        onDeleted: () => _removeFace(f),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 4),
        Text(
          '名字需與旅程「參加者」一致；新增或刪除後，相框同步＋重開機才生效',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatusRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}
