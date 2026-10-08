import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../../domain/server_models.dart';

/// Frosted-looking surface: translucent fill, gradient sheen and a hairline border.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.onTap,
    this.accent,
    this.highlighted = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? accent;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final radius = AppRadius.all(AppRadius.lg);
    final borderColor = highlighted ? (accent ?? AppColors.primary).withValues(alpha: 0.55) : AppColors.outline;
    final body = Padding(padding: padding, child: child);
    final surface = AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.standard,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        gradient: AppColors.surfaceGradient,
        borderRadius: radius,
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 12)),
          if (highlighted) BoxShadow(color: (accent ?? AppColors.primary).withValues(alpha: 0.18), blurRadius: 28),
        ],
      ),
      child: onTap == null
          ? body
          : ClipRRect(
              borderRadius: radius,
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap, child: body),
              ),
            ),
    );
    if (onTap == null) {
      return surface;
    }
    return PressScale(onTap: onTap, child: surface);
  }
}

/// Subtly shrinks its child while a pointer is down. It never consumes gestures.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.onTap, this.scale = 0.97});

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value) {
      setState(() => _down = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.onTap == null ? null : (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        child: widget.child,
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return PressScale(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: AppMotion.fast,
        opacity: enabled || busy ? 1 : 0.5,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.brand,
            borderRadius: AppRadius.all(AppRadius.md),
            boxShadow: [
              BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 10)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: AppRadius.all(AppRadius.md),
              onTap: enabled ? onPressed : null,
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: AppSpace.md),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (busy)
                      const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.ink))
                    else if (icon != null)
                      Icon(icon, size: 20, color: AppColors.ink),
                    if (busy || icon != null) const SizedBox(width: AppSpace.sm),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed, this.icon, this.danger = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.textPrimary;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20, color: color),
      label: Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: danger ? AppColors.danger.withValues(alpha: 0.5) : AppColors.outline),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class ServerStateChip extends StatelessWidget {
  const ServerStateChip({super.key, required this.state});

  final ServerState state;

  @override
  Widget build(BuildContext context) {
    final (color, key, pulsing) = switch (state) {
      ServerState.running => (AppColors.success, 'state.running', true),
      ServerState.starting => (AppColors.warning, 'state.starting', true),
      ServerState.stopping => (AppColors.warning, 'state.stopping', true),
      ServerState.restarting => (AppColors.warning, 'state.restarting', true),
      ServerState.saving => (AppColors.info, 'state.saving', true),
      ServerState.error => (AppColors.danger, 'state.error', false),
      ServerState.offline => (AppColors.textMuted, 'state.offline', false),
      ServerState.unknown => (AppColors.textMuted, 'state.unknown', false),
    };
    return AnimatedContainer(
      duration: AppMotion.base,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs + 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadius.all(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseDot(color: color, active: pulsing),
          const SizedBox(width: AppSpace.sm),
          Text(
            context.tr(key),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.active = false, this.size = 8});

  final Color color;
  final bool active;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size * 2.4,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = widget.active ? _controller.value : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.active)
                Container(
                  width: widget.size * (1 + t * 1.4),
                  height: widget.size * (1 + t * 1.4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.35 * (1 - t)),
                  ),
                ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: AppMotion.slow,
            curve: AppMotion.emphasized,
            builder: (context, value, child) => Transform.scale(scale: value, child: Opacity(opacity: value.clamp(0.0, 1.0).toDouble(), child: child)),
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.brand,
                boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 30)],
              ),
              child: Icon(icon, color: AppColors.ink, size: 40),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(message!, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: AppSpace.lg), action!],
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final detail = describeError(context, error);
    return EmptyState(
      icon: Icons.cloud_off_rounded,
      title: context.tr('error.title'),
      message: detail,
      action: onRetry == null ? null : SecondaryButton(label: context.tr('action.retry'), onPressed: onRetry, icon: Icons.refresh_rounded),
    );
  }
}

class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder, this.onRetry, this.loading});

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (data) => builder(context, data),
      loading: () => loading ?? const SkeletonList(),
      error: (error, _) => ErrorState(error: error, onRetry: onRetry),
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4, this.height = 88});

  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(
        count,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.md),
          child: Shimmer(child: Container(height: height, decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.all(AppRadius.lg)))),
        ),
      ),
    );
  }
}

/// Moving highlight used for loading placeholders.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          final dx = rect.width * (_controller.value * 2 - 0.5);
          return LinearGradient(
            colors: [Colors.white.withValues(alpha: 0.04), Colors.white.withValues(alpha: 0.12), Colors.white.withValues(alpha: 0.04)],
            stops: const [0.3, 0.5, 0.7],
            transform: _SlideGradient(dx),
          ).createShader(rect);
        },
        child: child,
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);

  final double dx;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(dx, 0, 0);
}

/// Fade + rise entrance with a small stagger by [index].
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    final delay = (index.clamp(0, 8) * 45).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: AppMotion.base.inMilliseconds + delay.toInt()),
      curve: AppMotion.enter,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
      child: child,
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.progress,
    this.color = AppColors.primary,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final double? progress;
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(label, style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(value, style: theme.textTheme.titleLarge),
          if (progress != null) ...[
            const SizedBox(height: AppSpace.md),
            ClipRRect(
              borderRadius: AppRadius.all(AppRadius.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: progress!.clamp(0.0, 1.0).toDouble()),
                duration: AppMotion.slow,
                curve: AppMotion.standard,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  color: color,
                  backgroundColor: AppColors.surfaceHigh,
                ),
              ),
            ),
          ],
          if (caption != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(caption!, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

class InfoLine extends StatelessWidget {
  const InfoLine({super.key, required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: AppColors.textMuted), const SizedBox(width: AppSpace.sm)],
          Expanded(flex: 2, child: Text(label, style: theme.textTheme.bodySmall)),
          const SizedBox(width: AppSpace.md),
          Expanded(
            flex: 3,
            child: SelectableText(value, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class OptionChips<T> extends StatelessWidget {
  const OptionChips({
    super.key,
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<T> options;
  final T? selected;
  final String Function(T value) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: [
        for (final option in options)
          PressScale(
            onTap: () => onSelected(option),
            child: AnimatedContainer(
              duration: AppMotion.base,
              curve: AppMotion.standard,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm + 2),
              decoration: BoxDecoration(
                gradient: option == selected ? AppColors.brand : null,
                color: option == selected ? null : AppColors.glassFill,
                borderRadius: AppRadius.all(AppRadius.pill),
                border: Border.all(color: option == selected ? Colors.transparent : AppColors.outline),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: AppRadius.all(AppRadius.pill),
                  onTap: () => onSelected(option),
                  child: Text(
                    label(option),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: option == selected ? AppColors.ink : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ValueStepper extends StatelessWidget {
  const ValueStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.suffix,
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: value - step >= min ? () => onChanged(value - step) : null,
          icon: const Icon(Icons.remove_rounded),
          tooltip: '-',
        ),
        SizedBox(
          width: 96,
          child: Text(
            suffix == null ? '$value' : '$value $suffix',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        IconButton.filledTonal(
          onPressed: value + step <= max ? () => onChanged(value + step) : null,
          icon: const Icon(Icons.add_rounded),
          tooltip: '+',
        ),
      ],
    );
  }
}

class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(title, style: theme.textTheme.bodyLarge),
      subtitle: subtitle == null ? null : Text(subtitle!, style: theme.textTheme.bodySmall),
      secondary: icon == null ? null : Icon(icon, color: AppColors.textSecondary),
    );
  }
}

class AppSearchField extends StatelessWidget {
  const AppSearchField({super.key, required this.controller, required this.hint, this.onSubmitted});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: context.tr('action.clear'),
                  onPressed: () {
                    controller.clear();
                    onSubmitted?.call('');
                  },
                ),
        ),
      ),
    );
  }
}

class AvatarImage extends StatelessWidget {
  const AvatarImage({super.key, required this.url, required this.fallback, this.size = 40});

  final String? url;
  final String fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = fallback.isEmpty ? '?' : fallback.substring(0, 1).toUpperCase();
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url == null || url!.isEmpty
            ? _initials(context, initial)
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => _initials(context, initial),
                loadingBuilder: (context, child, progress) => progress == null ? child : _initials(context, initial),
              ),
      ),
    );
  }

  Widget _initials(BuildContext context, String initial) {
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: AppColors.brand),
      child: Text(initial, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.ink)),
    );
  }
}
