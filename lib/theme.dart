import 'package:flutter/material.dart';

/// The palette shared by the web apps in this projects folder (see
/// fileshare/public/index.html): blue->violet gradient accent, soft cards,
/// 14px-rounded bold buttons. Follows the system light/dark setting.
class AppColors {
  const AppColors._({
    required this.bg,
    required this.card,
    required this.card2,
    required this.text,
    required this.muted,
    required this.line,
  });

  static const Color accent = Color(0xFF1A73E8);
  static const Color accent2 = Color(0xFF7C4DFF);
  static const LinearGradient grad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5B4BFF), Color(0xFF3A2BD0), Color(0xFF1C1165)],
    stops: [0, 0.55, 1],
  );

  final Color bg, card, card2, text, muted, line;

  static const light = AppColors._(
    bg: Color(0xFFF4F6FB),
    card: Color(0xFFFFFFFF),
    card2: Color(0xFFEEF1F8),
    text: Color(0xFF1B1F2A),
    muted: Color(0xFF6B7386),
    line: Color(0xFFDFE3EE),
  );

  static const dark = AppColors._(
    bg: Color(0xFF0F1220),
    card: Color(0xFF181C2F),
    card2: Color(0xFF20253B),
    text: Color(0xFFECEFFA),
    muted: Color(0xFF98A1BB),
    line: Color(0xFF2A3050),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

const double kButtonRadius = 14;
const double kButtonHeight = 48;

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: brightness,
      ).copyWith(
        primary: AppColors.accent,
        secondary: AppColors.accent2,
        surface: c.card,
        onSurface: c.text,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}

/// Gradient-filled bold button: the app's primary action.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled || busy ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: AppColors.grad,
            borderRadius: BorderRadius.circular(kButtonRadius),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(kButtonRadius),
            onTap: enabled ? onPressed : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kButtonHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else if (icon != null)
                      Icon(icon, color: Colors.white, size: 20),
                    if (busy || icon != null) const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
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

/// Soft card-coloured bold button: secondary actions. Set [overCamera] to
/// use a translucent dark fill with white text on top of the live preview.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.overCamera = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool overCamera;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fg = overCamera ? Colors.white : c.text;
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: Material(
        color: overCamera ? Colors.black.withValues(alpha: 0.55) : c.card2,
        borderRadius: BorderRadius.circular(kButtonRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(kButtonRadius),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kButtonHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: fg, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
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
