import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/like_provider.dart';

/// 底部導覽容器：四個 tab 的 shell，內容由 go_router 的
/// StatefulShellRoute 提供（各 tab 保留自己的導覽堆疊）。
/// 也負責監聽相框按讚事件（likeFeedProvider）並跳通知橫幅——
/// shell 永遠在畫面上，所以不管使用者在哪個 tab 都收得到。
class HomePage extends ConsumerWidget {
  final StatefulNavigationShell shell;

  const HomePage({super.key, required this.shell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(likeFeedProvider, (prev, next) {
      if (next != null && next.id != prev?.id) {
        _showLikeBanner(context, next);
      }
    });

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) => shell.goBranch(
          index,
          // 點目前所在的 tab 時回到該 tab 的第一頁
          initialLocation: index == shell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.radio_button_checked),
            label: '記錄',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: '旅程',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '精靈',
          ),
          NavigationDestination(
            icon: Icon(Icons.filter_frames_outlined),
            selectedIcon: Icon(Icons.filter_frames),
            label: '相框',
          ),
        ],
      ),
    );
  }

  void _showLikeBanner(BuildContext context, LikeEvent ev) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _LikeBanner(event: ev, onDismiss: () => entry.remove()),
    );
    overlay.insert(entry);
  }
}

/// 通知樣式的頂部橫幅：滑入 → 停 4.5 秒 → 滑出。點擊跳到該趟旅程。
class _LikeBanner extends StatefulWidget {
  final LikeEvent event;
  final VoidCallback onDismiss;

  const _LikeBanner({required this.event, required this.onDismiss});

  @override
  State<_LikeBanner> createState() => _LikeBannerState();
}

class _LikeBannerState extends State<_LikeBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, -1.5),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 4500), _close);
  }

  Future<void> _close() async {
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ev = widget.event;
    final who = ev.user.isEmpty ? '家人' : ev.user;
    final what =
        ev.tripTitle.isEmpty ? '相框裡的照片' : '「${ev.tripTitle}」的照片';

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () {
              if (ev.tripId != null) {
                // rootContext 由 Overlay 提供，用 go_router 全域跳轉
                GoRouter.of(context).push('/trips/${ev.tripId}');
              }
              _close();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xF2323232),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.pink.shade400,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.favorite,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '來自智慧相框',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$who 對$what按了讚 ❤️',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
