import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../core/api_client.dart';
import '../core/maps_launcher.dart';
import '../models/spot.dart';
import '../providers/frame_provider.dart';
import '../providers/guide_provider.dart';
import '../widgets/guide_avatar.dart';

/// 「精靈」tab：跟導遊精靈小憶互動。上方是她的形象（可摸頭、會揮手、
/// 講話時嘴巴會動），下方是對話與快捷提問。
class GuidePage extends ConsumerStatefulWidget {
  const GuidePage({super.key});

  @override
  ConsumerState<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends ConsumerState<GuidePage> {
  final _avatarKey = GlobalKey<GuideAvatarState>();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<GuideMessage> _messages = [];
  bool _busy = false;
  String _bubble = '嗨～我是小憶，你的旅遊小精靈！\n想去哪走走，問我就對了 🌿';

  // 語音：對她說（STT）+ 她開口回（TTS 播放）
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _player = AudioPlayer();
  bool _speechReady = false;
  bool _listening = false;
  bool _voiceOn = true; // 小憶用說的回答（右上角可關）

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      _avatarKey.currentState?.setTalking(false);
    });
  }

  @override
  void dispose() {
    _speech.stop();
    _player.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 麥克風：點一下開始聽，講完（或再點一下）自動送出。
  Future<void> _toggleListening() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (s) {
          if ((s == 'done' || s == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!_speechReady) {
        messenger.showSnackBar(const SnackBar(
          content: Text('這支手機沒有可用的語音辨識服務，或麥克風權限被拒'),
        ));
        return;
      }
    }
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
          localeId: 'zh_TW', partialResults: true),
      onResult: (r) {
        _inputController.text = r.recognizedWords; // 即時顯示聽到什麼
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          setState(() => _listening = false);
          _send(r.recognizedWords);
        }
      },
    );
  }

  /// 小憶開口：抓 TTS 播放，嘴巴動畫跟著實際語音長度走。
  Future<void> _speak(String text) async {
    if (!_voiceOn || text.isEmpty) return;
    try {
      final bytes = await fetchSpeech(ref.read(dioProvider), text);
      if (!mounted) return;
      _avatarKey.currentState?.setTalking(true);
      await _player.play(BytesSource(bytes));
    } catch (_) {
      // 語音是加分項，失敗就安靜地只顯示文字
      _avatarKey.currentState?.setTalking(false);
    }
  }

  Future<({double? lat, double? lng})> _currentLatLng() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return (lat: null, lng: null);
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return (lat: null, lng: null);
      }
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return (lat: last.latitude, lng: last.longitude);
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return (lat: null, lng: null);
    }
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _busy) return;
    _inputController.clear();
    // 這次送出前的對話當作記憶（不含正要送的這句）
    final history = List<GuideMessage>.from(_messages);
    setState(() {
      _messages.add(GuideMessage(fromUser: true, text: text));
      _busy = true;
    });
    _avatarKey.currentState?.setThinking(true);
    _scrollToBottom();

    final loc = await _currentLatLng();
    try {
      final reply = await askGuide(
        ref.read(dioProvider), text,
        lat: loc.lat, lng: loc.lng,
        frameId: ref.read(frameProvider).frameId,
        history: history);
      if (!mounted) return;
      _avatarKey.currentState?.setThinking(false);
      _react(reply.action, reply.reply);
      setState(() {
        _bubble = reply.reply;
        _messages.add(GuideMessage(
          fromUser: false, text: reply.reply, spots: reply.spots));
      });
    } catch (e) {
      if (!mounted) return;
      _avatarKey.currentState?.setThinking(false);
      final msg = '嗚，我剛剛連不上網路… ${friendlyError(e)}';
      setState(() {
        _bubble = msg;
        _messages.add(GuideMessage(fromUser: false, text: msg));
      });
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToBottom();
    }
  }

  /// 依後端動作標籤讓小憶做反應；語音開著就真的開口說。
  void _react(String action, String reply) {
    final avatar = _avatarKey.currentState;
    if (avatar == null) return;
    if (action == 'wave') avatar.wave();
    if (_voiceOn) {
      _speak(reply); // 播放期間嘴巴動，播完自動停
    } else {
      avatar.setTalking(true);
      Future.delayed(const Duration(milliseconds: 2600), () {
        if (mounted) avatar.setTalking(false);
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('導遊精靈 小憶'),
        actions: [
          IconButton(
            tooltip: _voiceOn ? '關閉語音回答' : '開啟語音回答',
            icon: Icon(_voiceOn ? Icons.volume_up : Icons.volume_off),
            onPressed: () {
              setState(() => _voiceOn = !_voiceOn);
              if (!_voiceOn) {
                _player.stop();
                _avatarKey.currentState?.setTalking(false);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 上半：漸層背景 + 小憶 + 講話泡泡
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.14),
                  theme.colorScheme.surface,
                ],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                _SpeechBubble(text: _bubble),
                const SizedBox(height: 4),
                GuideAvatar(
                  key: _avatarKey,
                  size: 168,
                  onHeadPat: () => setState(
                      () => _bubble = _headPatLines[
                          DateTime.now().second % _headPatLines.length]),
                ),
                Text('（摸摸小憶的頭試試看 👆）',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const Divider(height: 1),
          // 中間：對話紀錄
          Expanded(
            child: _messages.isEmpty
                ? _Suggestions(onPick: _send)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _Bubble(msg: _messages[i]),
                  ),
          ),
          // 快捷提問（有對話後仍可用）
          if (_messages.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final q in _quickAsks)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(q),
                        onPressed: _busy ? null : () => _send(q),
                      ),
                    ),
                ],
              ),
            ),
          // 輸入列
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Row(
                children: [
                  // 🎤 對小憶說話（聽寫中變紅、輸入框即時顯示聽到的字）
                  IconButton.filledTonal(
                    tooltip: _listening ? '停止' : '按著說話',
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                    color: _listening ? Colors.red : null,
                    onPressed: _busy ? null : _toggleListening,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: _listening ? '我在聽…' : '問問小憶…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _busy
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton.filled(
                          onPressed: () => _send(_inputController.text),
                          icon: const Icon(Icons.send),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _headPatLines = [
  '呵呵，好癢喔～',
  '嘿嘿，最喜歡你了！',
  '摸摸頭充電中～精神百倍！',
  '今天也一起去冒險吧！',
];

const _quickAsks = ['附近有冰店嗎？', '走路10分鐘有什麼好吃的', '介紹這附近', '你好呀'];

class _SpeechBubble extends StatelessWidget {
  final String text;

  const _SpeechBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
            ),
          ],
        ),
        child: Text(text,
            textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  final void Function(String) onPick;

  const _Suggestions({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('試著問我：', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final q in _quickAsks)
                  ActionChip(label: Text(q), onPressed: () => onPick(q)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final GuideMessage msg;

  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final align = msg.fromUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = msg.fromUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;

    return Column(
      crossAxisAlignment:
          msg.fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: align,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(msg.text, style: theme.textTheme.bodyMedium),
          ),
        ),
        // 精靈推薦的景點卡片
        for (final s in msg.spots) _SpotChip(spot: s),
      ],
    );
  }
}

class _SpotChip extends StatelessWidget {
  final Spot spot;

  const _SpotChip({required this.spot});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // route 查詢回的目的地：點卡片直接開步行導航
    final isDestination = spot.category == '目的地';
    final tint = spot.isFood ? Colors.deepOrange : theme.colorScheme.primary;
    return Card(
      margin: const EdgeInsets.only(top: 2, bottom: 4),
      child: ListTile(
        dense: true,
        leading: Icon(
          isDestination
              ? Icons.directions_walk
              : (spot.isFood ? Icons.restaurant : Icons.place),
          color: tint,
        ),
        title: Text(spot.name),
        subtitle: Text(isDestination
            ? (spot.description.isNotEmpty ? spot.description : '目的地')
            : spot.distanceLabel),
        trailing: Icon(
            isDestination ? Icons.navigation : Icons.map_outlined, size: 20),
        onTap: () => isDestination
            ? openDirections(context, spot)
            : openSpotInMaps(context, spot),
      ),
    );
  }
}
