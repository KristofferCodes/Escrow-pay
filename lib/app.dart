import 'package:flutter/material.dart';

import 'app_links_handler.dart';
import 'features/home/home_screen.dart';
import 'theme/app_theme.dart';

class EscrowPayApp extends StatelessWidget {
  EscrowPayApp({super.key});

  /// Deep links arrive outside the widget tree, so routing them needs a
  /// navigator reachable from anywhere.
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Escrow Pay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      navigatorKey: _navigatorKey,
      home: AppLinksHandler(
        navigatorKey: _navigatorKey,
        child: const HomeScreen(),
      ),
    );
  }
}
