import 'package:flutter/material.dart';
import '../utils/pwa_install.dart';

/// Banner prompting mobile users to install OneMind as a PWA.
///
/// Always shown on the home page if the user is on mobile and not
/// running in standalone (installed) mode. Hidden on desktop.
///
/// Three modes:
/// - **Install**: beforeinstallprompt available -> "Install" button
/// - **Already installed**: getInstalledRelatedApps detects it -> "Open from home screen"
/// - **iOS / no prompt**: Show "Tap Share -> Add to Home Screen" instructions
class PwaInstallBanner extends StatefulWidget {
  const PwaInstallBanner({super.key});

  @override
  State<PwaInstallBanner> createState() => _PwaInstallBannerState();
}

enum _BannerMode { install, alreadyInstalled, iosInstructions }

class _PwaInstallBannerState extends State<PwaInstallBanner> {
  bool _visible = false;
  bool _loading = true;
  late bool _ios;
  _BannerMode _mode = _BannerMode.install;

  @override
  void initState() {
    super.initState();
    if (!isMobileDevice() || isPwaInstalled()) return;
    _ios = isIos();
    _visible = true;
    _detectState();
  }

  Future<void> _detectState() async {
    if (_ios) {
      setState(() {
        _mode = _BannerMode.iosInstructions;
        _loading = false;
      });
      return;
    }

    final installed = await hasInstalledPwa();
    if (!mounted) return;

    setState(() {
      _mode = installed ? _BannerMode.alreadyInstalled : _BannerMode.install;
      _loading = false;
    });
  }

  Future<void> _install() async {
    final accepted = await triggerPwaInstall();
    if (accepted && mounted) {
      setState(() => _visible = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _loading) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final onContainer = theme.colorScheme.onPrimaryContainer;

    final String title;
    final String subtitle;
    final IconData icon;
    final Widget? action;

    switch (_mode) {
      case _BannerMode.alreadyInstalled:
        icon = Icons.check_circle_outline;
        title = 'OneMind is installed';
        subtitle = 'Open it from your home screen';
        action = null;
      case _BannerMode.install:
        icon = Icons.install_mobile;
        title = 'Install OneMind';
        subtitle = 'Add to your home screen for the best experience';
        action = TextButton(
          onPressed: _install,
          child: const Text('Install'),
        );
      case _BannerMode.iosInstructions:
        icon = Icons.ios_share;
        title = 'Install OneMind';
        subtitle = 'Tap Share then "Add to Home Screen"';
        action = null;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(icon, color: onContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: onContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onContainer.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null) action,
            ],
          ),
        ),
      ),
    );
  }
}
