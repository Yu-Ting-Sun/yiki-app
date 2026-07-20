import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 底部導覽容器：三個 tab 的 shell，內容由 go_router 的
/// StatefulShellRoute 提供（各 tab 保留自己的導覽堆疊）。
class HomePage extends StatelessWidget {
  final StatefulNavigationShell shell;

  const HomePage({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
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
}
