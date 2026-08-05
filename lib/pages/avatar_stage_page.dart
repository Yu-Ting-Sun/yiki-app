import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/guide_avatar.dart';

/// 影片攝影棚(隱藏頁):純綠背景+大隻小憶,給競賽影片當解說員用。
/// 錄影(scrcpy)→ 剪映裁掉底部黑色控制列 → 色度摳圖去綠背 → 疊進影片。
/// 入口:小憶分頁 AppBar 標題長按。
class AvatarStagePage extends StatefulWidget {
  const AvatarStagePage({super.key});

  @override
  State<AvatarStagePage> createState() => _AvatarStagePageState();
}

class _AvatarStagePageState extends State<AvatarStagePage> {
  final _avatarKey = GlobalKey<GuideAvatarState>();
  Timer? _talkTimer;
  bool _talking = false;

  @override
  void dispose() {
    _talkTimer?.cancel();
    super.dispose();
  }

  void _setTalking(bool v) {
    _talkTimer?.cancel();
    _avatarKey.currentState?.setTalking(v);
    setState(() => _talking = v);
  }

  /// 講固定秒數(對齊旁白段落長度),到點自動閉嘴。
  void _talkFor(int seconds) {
    _setTalking(true);
    _talkTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) _setTalking(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      // 純綠幕:剪映「色度摳圖」一鍵去背
      backgroundColor: const Color(0xFF00FF00),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: GuideAvatar(key: _avatarKey, size: w * 0.85),
              ),
            ),
            // 控制列(黑條,剪輯時裁掉)
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _btn('👋 揮手', () => _avatarKey.currentState?.wave()),
                  _btn('🎉 開心', () => _avatarKey.currentState?.cheer()),
                  _btn(_talking ? '⏹ 停' : '🗣 說話',
                      () => _setTalking(!_talking)),
                  _btn('說10秒', () => _talkFor(10)),
                  _btn('說14秒', () => _talkFor(14)),
                  _btn('說19秒', () => _talkFor(19)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
      );
}
