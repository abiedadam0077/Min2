import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxelops/core/theme/app_theme.dart';
import 'package:voxelops/core/widgets/brand.dart';
import 'package:voxelops/core/widgets/common.dart';
import 'package:voxelops/core/widgets/shell.dart';
import 'package:voxelops/domain/server_models.dart';

Widget _host(Widget child, {String locale = 'en'}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    locale: Locale(locale),
    supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('core widgets build in Arabic (RTL) without exceptions', (tester) async {
    await tester.pumpWidget(_host(
      Column(
        children: [
          const VoxelLogo(size: 64, animate: false),
          GlassCard(child: const Text('مرحبا')),
          const MetricCard(icon: Icons.memory, label: 'المعالج', value: '42%', progress: 0.42),
        ],
      ),
      locale: 'ar',
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('مرحبا'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating navigation reports the tapped index', (tester) async {
    int? selected;
    await tester.pumpWidget(_host(
      FloatingNav(
        index: 0,
        onSelected: (i) => selected = i,
        items: const <NavItem>[
          NavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
          NavItem(icon: Icons.dns_outlined, selectedIcon: Icons.dns, label: 'Servers'),
        ],
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Servers'));
    await tester.pump();
    expect(selected, 1);
  });

  testWidgets('empty state and status chip render every server state', (tester) async {
    await tester.pumpWidget(_host(
      const SingleChildScrollView(
        child: Column(
          children: [
            EmptyState(icon: Icons.dns, title: 'Nothing here', message: 'Create one'),
            Wrap(children: [ServerStateChip(state: ServerState.running)]),
          ],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nothing here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
