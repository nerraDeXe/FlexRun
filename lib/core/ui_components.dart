import 'package:flutter/material.dart';
import 'theme.dart';

// ============================================================================
// REUSABLE CARD COMPONENTS
// ============================================================================

/// Minimalist card with subtle shadow and elegant borders
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.backgroundColor = kSurfaceCard,
    this.border,
    this.elevation = AppShadow.sm,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Border? border;
  final BoxShadow elevation;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppBorderRadius.lg),
            border: border ?? Border.all(color: kDivider, width: 1),
            boxShadow: [elevation],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Metric card for displaying key statistics
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.unit = '',
    this.onTap,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final String unit;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      backgroundColor: highlighted ? kBrandOrangeLight : kSurfaceCard,
      elevation: highlighted ? AppShadow.md : AppShadow.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: kBrandOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppBorderRadius.md),
                ),
                child: Icon(icon, color: kBrandOrange, size: 18),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(label, style: AppTypography.labelSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: AppTypography.headingMedium),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(unit, style: AppTypography.labelSmall),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// LOADING & SKELETON COMPONENTS
// ============================================================================

/// Shimmer loading animation
class ShimmerLoading extends StatefulWidget {
  const ShimmerLoading({super.key, required this.child});

  final Widget child;

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                Color(0x1AFFFFFF),
                Color(0x3AFFFFFF),
                Color(0x1AFFFFFF),
              ],
              stops: [
                _controller.value - 0.3,
                _controller.value,
                _controller.value + 0.3,
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Skeleton card placeholder
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.height = 100,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.showShimmer = true,
  });

  final double height;
  final EdgeInsets padding;
  final bool showShimmer;

  @override
  Widget build(BuildContext context) {
    final skeleton = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: kDivider,
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        border: Border.all(color: kDisabled, width: 1),
      ),
      child: Container(height: height),
    );

    if (showShimmer) {
      return ShimmerLoading(child: skeleton);
    }
    return skeleton;
  }
}

/// Skeleton line placeholder for text
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.width = double.infinity,
    this.height = 12,
    this.showShimmer = true,
  });

  final double width;
  final double height;
  final bool showShimmer;

  @override
  Widget build(BuildContext context) {
    final skeleton = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: kDivider,
        borderRadius: BorderRadius.circular(AppBorderRadius.xs),
      ),
    );

    if (showShimmer) {
      return ShimmerLoading(child: skeleton);
    }
    return skeleton;
  }
}

// ============================================================================
// EMPTY STATE COMPONENTS
// ============================================================================

/// Empty state view for when no data is available
class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: kBrandOrangeLight,
                  borderRadius: BorderRadius.circular(AppBorderRadius.full),
                ),
                child: Icon(icon, size: 48, color: kBrandOrange),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(title, style: AppTypography.headingLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle,
                style: AppTypography.bodyMedium.copyWith(color: kTextSecondary),
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.xl),
                ElevatedButton(
                  onPressed: onAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kBrandOrange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(140, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppBorderRadius.lg),
                    ),
                  ),
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ERROR STATE COMPONENTS
// ============================================================================

/// Error state widget with recovery action
class ErrorStateWidget extends StatelessWidget {
  const ErrorStateWidget({
    super.key,
    required this.message,
    this.actionLabel = 'Try Again',
    this.onAction,
    this.icon = Icons.error_outline,
  });

  final String message;
  final String actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: kErrorLight,
        border: Border.all(color: kError.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: kError, size: 20),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  message,
                  style: AppTypography.bodyMedium.copyWith(color: kError),
                ),
              ),
            ],
          ),
          if (onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kError,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppBorderRadius.md),
                  ),
                ),
                child: Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// INPUT & FORM COMPONENTS
// ============================================================================

/// Enhanced text input field
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.maxLines = 1,
    this.validator,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final String? errorText;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType keyboardType;
  final bool obscureText;
  final int maxLines;
  final String? Function(String?)? validator;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        AnimatedContainer(
          duration: AppAnimation.fast,
          decoration: BoxDecoration(
            color: _isFocused ? kBrandOrangeLight : kSurfaceCard,
            border: Border.all(
              color: hasError
                  ? kError
                  : _isFocused
                  ? kBrandOrange
                  : kDivider,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(AppBorderRadius.lg),
            boxShadow: _isFocused ? [AppShadow.sm] : null,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            keyboardType: widget.keyboardType,
            obscureText: widget.obscureText,
            maxLines: widget.obscureText ? 1 : widget.maxLines,
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: AppTypography.bodyMedium.copyWith(
                color: kTextTertiary,
              ),
              prefixIcon: widget.prefixIcon != null
                  ? Icon(widget.prefixIcon, color: kBrandOrange)
                  : null,
              suffixIcon: widget.suffixIcon != null
                  ? Icon(widget.suffixIcon, color: kTextSecondary)
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
            ),
            style: AppTypography.bodyMedium,
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.errorText!,
            style: AppTypography.captionSmall.copyWith(color: kError),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// NOTIFICATION COMPONENTS
// ============================================================================

/// Enhanced snackbar notification
class AppNotification {
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show({
    required BuildContext context,
    required String message,
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    final (backgroundColor, iconData) = _getTypeStyles(type);

    return ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(iconData, color: Colors.white, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        ),
        margin: const EdgeInsets.all(AppSpacing.lg),
        elevation: 8,
        action: action,
      ),
    );
  }

  static (Color, IconData) _getTypeStyles(NotificationType type) {
    return switch (type) {
      NotificationType.success => (kSuccess, Icons.check_circle),
      NotificationType.error => (kError, Icons.error),
      NotificationType.warning => (kWarning, Icons.warning),
      NotificationType.info => (kInfo, Icons.info),
    };
  }
}

enum NotificationType { success, error, warning, info }

// ============================================================================
// PROGRESS & STATUS COMPONENTS
// ============================================================================

/// Circular progress indicator with label
class LabeledProgressIndicator extends StatelessWidget {
  const LabeledProgressIndicator({
    super.key,
    required this.value,
    required this.label,
    this.size = 80,
    this.strokeWidth = 6,
  });

  final double value;
  final String label;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: value,
                strokeWidth: strokeWidth,
                color: kBrandOrange,
                backgroundColor: kDivider,
              ),
              Text(
                '${(value * 100).toStringAsFixed(0)}%',
                style: AppTypography.headingSmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(label, style: AppTypography.labelSmall),
      ],
    );
  }
}

/// Status badge
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.type,
    this.icon,
  });

  final String label;
  final BadgeType type;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bgColor, textColor, borderColor) = _getTypeColors(type);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(AppBorderRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(color: textColor),
          ),
        ],
      ),
    );
  }

  (Color, Color, Color) _getTypeColors(BadgeType type) {
    return switch (type) {
      BadgeType.success => (
        kSuccessLight,
        kSuccess,
        kSuccess.withValues(alpha: 0.3),
      ),
      BadgeType.error => (kErrorLight, kError, kError.withValues(alpha: 0.3)),
      BadgeType.warning => (
        kWarningLight,
        kWarning,
        kWarning.withValues(alpha: 0.3),
      ),
      BadgeType.info => (kInfoLight, kInfo, kInfo.withValues(alpha: 0.3)),
    };
  }
}

enum BadgeType { success, error, warning, info }

// ============================================================================
// DIVIDER COMPONENTS
// ============================================================================

/// Minimalist divider
class AppDivider extends StatelessWidget {
  const AppDivider({
    super.key,
    this.height = 1,
    this.margin = const EdgeInsets.symmetric(vertical: AppSpacing.lg),
  });

  final double height;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(height: height, color: kDivider),
    );
  }
}
