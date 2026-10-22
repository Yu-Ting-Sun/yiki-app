import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/like_provider.dart';
import '../providers/message_provider.dart';

/// 底部導覽容器：四個 tab 的 shell，內容由 go_router 的
/// StatefulShellRoute 提供（各 tab 保留自己的導覽堆疊）。
/// 也負責監聽相框傳來的事件（按讚 likeFeedProvider、長輩留言
/// messageFeedProvider）並跳通知橫幅——shell 永遠在畫面上，
/// 所以不管使用者在哪個 tab 都收得到。
class HomePage extends ConsumerWidget {
  final StatefulNavigationShell shell;

  const HomePage({super.key, required this.shell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(likeFeedProvider, (prev, next) {
      if (next != null && next.id != prev?.id) {
        final who = next.user.isEmpty ? '家人' : next.user;
        final what =
            next.tripTitle.isEmpty ? '相框裡的照片' : '「${next.tripTitle}」的照片';
        _showBanner(
          context,
          icon: Icons.favorite,
          iconColor: Colors.pink.shade400,
          text: '$who 對$what按了讚 ❤️',
          route: next.tripId != null ? '/trips/${next.tripId}' : null,
        );
      }
    });
    ref.listen(messageFeedProvider, (prev, next) {
      if (next != null && next.id != prev?.id) {
        final who = next.user.isEmpty ? '家人' : next.user;
        _showBanner(
          context,
          icon: Icons.record_voice_over,
          iconColor: Colors.teal.shade400,
          text: '$who 留言給${next.to}：「${next.text}」',
          route: '/frame', // 相框頁的留言列表能聽原音
        );
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

  void _showBanner(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String text,
    String? route,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FrameBanner(
        icon: icon,
        iconColor: iconColor,
        text: text,
        route: route,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

/// 通知樣式的頂部橫幅：滑入 → 停 4.5 秒 → 滑出。點擊跳到 route（有的話）。
class _FrameBanner extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final String? route;
  final VoidCallback onDismiss;

  const _FrameBanner({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.onDismiss,
    this.route,
  });

  @override
  State<_FrameBanner> createState() => _FrameBannerState();
}

class _FrameBannerState extends State<_FrameBanner>
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
              final route = widget.route;
              if (route != null) {
                // rootContext 由 Overlay 提供，用 go_router 全域跳轉；
                // tab 根頁用 go（切 tab），其他用 push（可返回）
                if (route == '/frame') {
                  GoRouter.of(context).go(route);
                } else {
                  GoRouter.of(context).push(route);
                }
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
                      color: widget.iconColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 24),
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
                          widget.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
