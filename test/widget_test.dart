import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yiki_app/main.dart';

void main() {
  testWidgets('四個底部 tab 存在且能切換', (tester) async {
    SharedPreferences.setMockInitialValues({}); // frame_provider 開機還原用

    await tester.pumpWidget(const ProviderScope(child: YikiApp()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['記錄', '旅程', '精靈', '相框']) {
      expect(find.text(label), findsOneWidget);
    }

    // 切到相框 tab：未配對 → 顯示配對引導
    // （精靈頁的小憶有無限動畫，pumpAndSettle 會等不到靜止，這裡不進去）
    await tester.tap(find.text('相框'));
    await tester.pumpAndSettle();
    expect(find.text('配對你的相框'), findsOneWidget);
  });
}
