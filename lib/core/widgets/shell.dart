import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'common.dart';

class NavItem {
  const NavItem({required this.icon, required this.selectedIcon, required this.label});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Floating glass navigation pill used by the app shell. Selection is animated, not swapped.
class FloatingNav extends StatelessWidget {
  const FloatingNav({super.key, required this.items, required this.index, required this.onSelected});

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.md),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Container(
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.92),
                borderRadius: AppRadius.all(AppRadius.pill),
                border: Border.all(color: AppColors.outline),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 30, offset: const Offset(0, 14))],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _NavButton(
                        item: items[i],
                        selected: i == index,
                        onTap: () => onSelected(i),
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

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AppRadius.all(AppRadius.pill),
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.standard,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: AppRadius.all(AppRadius.pill),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: selected ? 1.08 : 1,
                  duration: AppMotion.base,
                  curve: AppMotion.emphasized,
                  child: Icon(selected ? item.selectedIcon : item.icon, color: color, size: 24),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: AppMotion.base,
                  style: (Theme.of(context).textTheme.labelSmall ?? const TextStyle()).copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Standard screen scaffold: large collapsing app bar, responsive inset and safe-area clearance.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.title,
    this.children = const <Widget>[],
    this.actions = const <Widget>[],
    this.inShell = false,
    this.floatingAction,
    this.onRefresh,
    this.leading,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final bool inShell;
  final Widget? floatingAction;
  final Future<void> Function()? onRefresh;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = AppBreakpoints.horizontalInset(media.size.width);
    final bottom = (inShell ? AppBreakpoints.navClearance : AppSpace.xxl) + media.viewPadding.bottom;
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        spaced.add(const SizedBox(height: AppSpace.md));
      }
      spaced.add(children[i]);
    }
    Widget scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverAppBar.large(
          pinned: true,
          stretch: true,
          automaticallyImplyLeading: !inShell,
          leading: leading,
          title: Text(title),
          actions: actions,
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(inset, AppSpace.sm, inset, bottom),
          sliver: SliverList(delegate: SliverChildListDelegate(spaced)),
        ),
      ],
    );
    if (onRefresh != null) {
      scroll = RefreshIndicator(onRefresh: onRefresh!, color: AppColors.primary, backgroundColor: AppColors.surfaceHigh, child: scroll);
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.background3d),
        child: scroll,
      ),
      floatingActionButton: floatingAction == null
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: inShell ? AppBreakpoints.navClearance - AppSpace.lg : 0),
              child: floatingAction,
            ),
    );
  }
}
