import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/i18n/i18n.dart';
import '../core/widgets/shell.dart';

/// Bottom-tab shell. Tabs keep their state because go_router keeps the shell route alive.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const List<String> _paths = <String>['/home', '/servers', '/content', '/console', '/more'];

  int _indexFor(String path) {
    final index = _paths.indexWhere((p) => path.startsWith(p));
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final index = _indexFor(location);
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingNav(
              index: index,
              onSelected: (i) {
                if (i != index) {
                  context.go(_paths[i]);
                }
              },
              items: <NavItem>[
                NavItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard_rounded, label: context.tr('nav.home')),
                NavItem(icon: Icons.dns_outlined, selectedIcon: Icons.dns_rounded, label: context.tr('nav.servers')),
                NavItem(icon: Icons.extension_outlined, selectedIcon: Icons.extension_rounded, label: context.tr('nav.content')),
                NavItem(icon: Icons.terminal_outlined, selectedIcon: Icons.terminal_rounded, label: context.tr('nav.console')),
                NavItem(icon: Icons.tune_outlined, selectedIcon: Icons.tune_rounded, label: context.tr('nav.more')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
