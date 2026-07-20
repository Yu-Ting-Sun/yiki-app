import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'router.dart';

void main() {
  runApp(const ProviderScope(child: YikiApp()));
}

class YikiApp extends StatelessWidget {
  const YikiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appName,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFE8871E), // 溫暖的琥珀色
        useMaterial3: true,
      ),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
