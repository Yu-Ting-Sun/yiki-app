import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 導遊精靈「小憶」——純 Flutter 繪製的角色，含待機呼吸/眨眼、揮手、
/// 被摸頭開心（冒愛心）、講話（嘴巴動）、思考等動作。
///
/// 之後若要換成專業立繪，把整個 build 換成 Rive/Lottie 的播放器、保留
/// 這裡的公開方法（wave / setTalking / setThinking / cheer）當觸發即可。
///
/// 用法：用 `GlobalKey<GuideAvatarState>` 拿到 state 後呼叫
/// `wave()` / `setTalking(true)` / `cheer()` 觸發動作。
class GuideAvatar extends StatefulWidget {
  final double size;

  /// 使用者摸她的頭時觸發（她會自己播開心動畫，這裡讓外部加台詞/音效）。
  final VoidCallback? onHeadPat;

  const GuideAvatar({super.key, this.size = 200, this.onHeadPat});

  @override
  GuideAvatarState createState() => GuideAvatarState();
}

class GuideAvatarState extends State<GuideAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _breath;   // 待機呼吸/漂浮
  late final AnimationController _blink;     // 眨眼
  late final AnimationController _wave;      // 揮手（一次性）
  late final AnimationController _happy;     // 開心（一次性）
  late final AnimationController _talk;      // 講話（持續）

  bool _talking = false;
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _blink = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 160));
    _wave = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300));
    _happy = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500));
    _talk = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320));
    _scheduleBlink();
  }

  void _scheduleBlink() {
    // 每 3~5 秒眨一次眼（閉→開）。
    final ms = 3000 + math.Random().nextInt(2000);
    Future.delayed(Duration(milliseconds: ms), () async {
      if (!mounted) return;
      await _blink.forward();
      await _blink.reverse();
      _scheduleBlink();
    });
  }

  @override
  void dispose() {
    _breath.dispose();
    _blink.dispose();
    _wave.dispose();
    _happy.dispose();
    _talk.dispose();
    super.dispose();
  }

  // ---- 公開動作（外部用 GlobalKey 呼叫）----
  void wave() {
    if (!mounted) return;
    _wave.forward(from: 0);
  }

  void cheer() {
    if (!mounted) return;
    _happy.forward(from: 0);
  }

  void setTalking(bool v) {
    if (!mounted || _talking == v) return;
    setState(() => _talking = v);
    if (v) {
      _talk.repeat(reverse: true);
    } else {
      _talk.stop();
      _talk.value = 0;
    }
  }

  void setThinking(bool v) {
    if (!mounted || _thinking == v) return;
    setState(() => _thinking = v);
  }

  void _onHeadPat() {
    cheer();
    widget.onHeadPat?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: Listenable.merge([_breath, _blink, _wave, _happy, _talk]),
        builder: (context, _) {
          final breath = _breath.value;          // 0..1
          final bob = math.sin(breath * math.pi) * s * 0.03;

          // 開心：Q 彈的縮放（先壓後彈）
          final hp = _happy.value;               // 0..1
          final squash = hp == 0
              ? 1.0
              : 1.0 + math.sin(hp * math.pi * 2) * 0.06;

          return Transform.translate(
            offset: Offset(0, bob),
            child: Transform.scale(
              scaleX: squash,
              scaleY: 2 - squash,
              alignment: Alignment.bottomCenter,
              child: _buildCharacter(s),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCharacter(double s) {
    final theme = Theme.of(context);
    final bodyD = s * 0.72;
    final eyeOpen = 1.0 - _blink.value;   // 1 開 0 閉
    final happy = _happy.value > 0.05;
    final mouthOpen = _talking ? _talk.value : 0.0;

    // 揮手：手臂抬高並來回擺
    final wv = _wave.value;
    final waving = wv > 0 && wv < 1;
    final waveAngle = waving
        ? -1.15 + math.sin(wv * math.pi * 6) * 0.35   // 抬高 + 擺動
        : 0.28;                                        // 待機垂放

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // 開心冒愛心
        if (happy) ..._buildHearts(s),

        // 頭上的小葉子觸角（旅行意象）
        Positioned(
          top: s * 0.02,
          child: Transform.rotate(
            angle: -0.3 + math.sin(_breath.value * math.pi) * 0.08,
            child: Icon(Icons.eco, size: s * 0.16,
                color: Colors.green.shade400),
          ),
        ),

        // 左手（待機微擺）
        Positioned(
          left: s * 0.08,
          top: s * 0.5,
          child: Transform.rotate(
            angle: 0.3,
            alignment: Alignment.topCenter,
            child: _arm(s),
          ),
        ),
        // 右手（揮手）
        Positioned(
          right: s * 0.08,
          top: s * 0.5,
          child: Transform.rotate(
            angle: waveAngle,
            alignment: Alignment.topCenter,
            child: _arm(s),
          ),
        ),

        // 身體
        Container(
          width: bodyD,
          height: bodyD,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.95),
                theme.colorScheme.primary,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
        ),

        // 臉
        SizedBox(
          width: bodyD,
          height: bodyD,
          child: CustomPaint(
            painter: _FacePainter(
              eyeOpen: eyeOpen,
              happy: happy,
              mouthOpen: mouthOpen,
              onColor: Colors.white,
              cheek: const Color(0xFFFF8A8A),
            ),
          ),
        ),

        // 思考中的小泡泡
        if (_thinking)
          Positioned(
            right: s * 0.06,
            top: s * 0.14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6),
                ],
              ),
              child: Text('…', style: TextStyle(fontSize: s * 0.12)),
            ),
          ),

        // 摸頭熱區（頭頂到臉部上緣）
        Positioned(
          top: 0,
          child: GestureDetector(
            onTap: _onHeadPat,
            child: SizedBox(width: bodyD, height: bodyD * 0.5),
          ),
        ),
      ],
    );
  }

  Widget _arm(double s) => Container(
        width: s * 0.12,
        height: s * 0.26,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(s * 0.06),
        ),
      );

  List<Widget> _buildHearts(double s) {
    final p = _happy.value;
    // 三顆愛心以不同起點上升淡出
    const starts = [0.0, 0.15, 0.3];
    const xs = [-0.22, 0.0, 0.24];
    return [
      for (var i = 0; i < 3; i++)
        Builder(builder: (_) {
          final t = ((p - starts[i]) / (1 - starts[i])).clamp(0.0, 1.0);
          if (t <= 0) return const SizedBox.shrink();
          return Positioned(
            top: s * 0.1 - t * s * 0.35,
            left: s * 0.5 + xs[i] * s - s * 0.06,
            child: Opacity(
              opacity: (1 - t).clamp(0.0, 1.0),
              child: Icon(Icons.favorite,
                  color: const Color(0xFFFF6B8A), size: s * 0.12),
            ),
          );
        }),
    ];
  }
}

class _FacePainter extends CustomPainter {
  final double eyeOpen;   // 1 開 0 閉
  final double mouthOpen; // 0..1（講話張嘴）
  final bool happy;
  final Color onColor;
  final Color cheek;

  _FacePainter({
    required this.eyeOpen,
    required this.mouthOpen,
    required this.happy,
    required this.onColor,
    required this.cheek,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final eyeY = h * 0.42;
    final dx = w * 0.2;
    final eyePaint = Paint()..color = onColor;

    // 腮紅
    final cheekPaint = Paint()..color = cheek.withValues(alpha: 0.55);
    canvas.drawCircle(Offset(w * 0.24, h * 0.56), w * 0.075, cheekPaint);
    canvas.drawCircle(Offset(w * 0.76, h * 0.56), w * 0.075, cheekPaint);

    // 眼睛
    if (happy) {
      // ^ ^ 開心眼
      final arc = Paint()
        ..color = onColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.035
        ..strokeCap = StrokeCap.round;
      for (final cx in [w * 0.5 - dx, w * 0.5 + dx]) {
        final path = Path()
          ..moveTo(cx - w * 0.05, eyeY + h * 0.02)
          ..quadraticBezierTo(cx, eyeY - h * 0.05, cx + w * 0.05, eyeY + h * 0.02);
        canvas.drawPath(path, arc);
      }
    } else {
      // 一般眼（眨眼時壓扁）
      for (final cx in [w * 0.5 - dx, w * 0.5 + dx]) {
        final rect = Rect.fromCenter(
          center: Offset(cx, eyeY),
          width: w * 0.11,
          height: h * 0.14 * eyeOpen.clamp(0.08, 1.0),
        );
        canvas.drawOval(rect, eyePaint);
      }
    }

    // 嘴巴
    final mouthPaint = Paint()
      ..color = onColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.03
      ..strokeCap = StrokeCap.round;
    final my = h * 0.66;
    if (mouthOpen > 0.05) {
      // 講話：張開的橢圓
      final oval = Rect.fromCenter(
        center: Offset(w * 0.5, my),
        width: w * 0.16,
        height: h * 0.06 + mouthOpen * h * 0.1,
      );
      canvas.drawOval(oval, Paint()..color = onColor);
    } else {
      // 微笑弧（開心時更大）
      final width = happy ? w * 0.22 : w * 0.16;
      final depth = happy ? h * 0.09 : h * 0.05;
      final path = Path()
        ..moveTo(w * 0.5 - width / 2, my)
        ..quadraticBezierTo(w * 0.5, my + depth, w * 0.5 + width / 2, my);
      canvas.drawPath(path, mouthPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FacePainter old) =>
      old.eyeOpen != eyeOpen ||
      old.mouthOpen != mouthOpen ||
      old.happy != happy;
}
