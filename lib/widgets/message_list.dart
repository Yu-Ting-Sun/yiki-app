import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/api_client.dart';
import '../providers/message_provider.dart';

/// 相框留言清單（相框頁看全部、旅程詳情頁看那一趟的），每則可以按播放
/// 聽長輩講那句話的原音。
class MessageList extends ConsumerStatefulWidget {
  final List<FrameMessage> messages;

  /// 顯示留言時相框在播哪本相簿（相框頁要，旅程頁就是本頁不必重複）。
  final bool showAlbum;

  const MessageList({super.key, required this.messages, this.showAlbum = true});

  @override
  ConsumerState<MessageList> createState() => _MessageListState();
}

class _MessageListState extends ConsumerState<MessageList> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _doneSub;
  int? _playingId; // 正在載入或播放的留言

  @override
  void initState() {
    super.initState();
    _doneSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
  }

  @override
  void dispose() {
    _doneSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(FrameMessage m) async {
    if (_playingId == m.id) {
      await _player.stop();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _playingId = m.id);
    try {
      await _player.stop();
      final bytes =
          await fetchMessageAudio(ref.read(dioProvider), m.frameId, m.id);
      if (!mounted || _playingId != m.id) return; // 使用者已改點別則
      await _player.play(BytesSource(bytes));
    } catch (e) {
      if (mounted) setState(() => _playingId = null);
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        for (final m in widget.messages) _tile(theme, m),
      ],
    );
  }

  Widget _tile(ThemeData theme, FrameMessage m) {
    final who = m.user.isEmpty ? '家人' : m.user;
    final when = m.createdAt != null
        ? DateFormat('M/d HH:mm').format(m.createdAt!.toLocal())
        : '';
    final where =
        widget.showAlbum && m.tripTitle.isNotEmpty ? '・看「${m.tripTitle}」時' : '';
    final playing = _playingId == m.id;

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: const Icon(Icons.record_voice_over),
        title: Text('「${m.text}」'),
        subtitle: Text('$who → ${m.to}　$when$where'),
        trailing: m.hasAudio
            ? IconButton(
                tooltip: playing ? '停止' : '聽原音',
                icon: Icon(
                  playing ? Icons.stop_circle : Icons.play_circle,
                  size: 32,
                  color: theme.colorScheme.primary,
                ),
                onPressed: () => _togglePlay(m),
              )
            : null,
      ),
    );
  }
}
