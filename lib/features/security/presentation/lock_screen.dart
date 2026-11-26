import 'dart:async';

import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/pin_pad.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/security_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Which part of the lock is on screen: picking a method or typing the PIN.
enum _LockStep { chooseMethod, enterPin }

/// Creates the PIN on the first run and unlocks the app afterwards.
///
/// When the phone has a fingerprint the user first picks how to open the app
/// (fingerprint or PIN); otherwise the PIN pad is shown directly.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  _LockStep _step = _LockStep.chooseMethod;

  /// During setup: the PIN typed the first time, waiting for confirmation.
  String? _firstEntry;
  String? _message;
  bool _hasError = false;
  bool _busy = false;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncCountdown();
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  void _onDigit(int digit) {
    if (_busy || _pin.length >= AppConstants.pinLength) return;
    setState(() {
      _pin += '$digit';
      _hasError = false;
    });
    if (_pin.length == AppConstants.pinLength) unawaited(_submit());
  }

  void _onBackspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _choosePin() {
    setState(() {
      _step = _LockStep.enterPin;
      _message = null;
      _hasError = false;
    });
  }

  void _chooseBiometrics() {
    _message = null;
    unawaited(_unlockWithBiometrics());
  }

  void _backToMethods() {
    setState(() {
      _step = _LockStep.chooseMethod;
      _pin = '';
      _message = null;
      _hasError = false;
    });
  }

  Future<void> _submit() async {
    final security = context.read<SecurityController>();
    final entered = _pin;
    setState(() => _busy = true);

    if (security.status == LockStatus.needsSetup) {
      await _submitSetup(security, entered);
    } else {
      await _submitUnlock(security, entered);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _submitSetup(SecurityController security, String entered) async {
    final first = _firstEntry;
    if (first == null) {
      setState(() {
        _firstEntry = entered;
        _pin = '';
        _message = null;
      });
    } else if (first == entered) {
      await security.createPin(entered);
    } else {
      await HapticFeedback.heavyImpact();
      setState(() {
        _firstEntry = null;
        _pin = '';
        _hasError = true;
        _message = 'الرمزان غير متطابقين، ابدأ من جديد.';
      });
    }
  }

  Future<void> _submitUnlock(
    SecurityController security,
    String entered,
  ) async {
    final result = await security.unlockWithPin(entered);
    if (!mounted) return;
    switch (result) {
      case PinAccepted():
        break; // the gate replaces this screen
      case PinRejected(:final attemptsLeft):
        await HapticFeedback.heavyImpact();
        setState(() {
          _pin = '';
          _hasError = true;
          _message = 'رمز PIN غير صحيح. المحاولات المتبقية: $attemptsLeft';
        });
      case PinBlocked():
        await HapticFeedback.heavyImpact();
        setState(() {
          _pin = '';
          _hasError = true;
          _message = null;
        });
        _syncCountdown();
    }
  }

  Future<void> _unlockWithBiometrics() async {
    if (_busy) return;
    setState(() => _busy = true);
    final accepted = await context
        .read<SecurityController>()
        .unlockWithBiometrics();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!accepted) {
        _hasError = true;
        _message = 'لم يتم التحقق من البصمة. أعد المحاولة أو استخدم رمز PIN.';
      }
    });
  }

  /// Re-draws the screen every second while PIN entry is blocked.
  void _syncCountdown() {
    final security = context.read<SecurityController>();
    if (security.blockRemaining == null) {
      _countdown?.cancel();
      _countdown = null;
      return;
    }
    _countdown ??= Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (context.read<SecurityController>().blockRemaining == null) {
        timer.cancel();
        _countdown = null;
        setState(() => _hasError = false);
      } else {
        setState(() {});
      }
    });
  }

  String _formatRemaining(Duration remaining) {
    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final security = context.watch<SecurityController>();
    final theme = Theme.of(context);
    final isSetup = security.status == LockStatus.needsSetup;
    final blocked = security.blockRemaining;
    final showMethods =
        !isSetup &&
        blocked == null &&
        security.canUseBiometrics &&
        _step == _LockStep.chooseMethod;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: showMethods
              ? _chooserView(theme)
              : _pinView(theme, isSetup: isSetup, blocked: blocked),
        ),
      ),
    );
  }

  /// The first screen: pick fingerprint or PIN.
  Widget _chooserView(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Column(
      key: const ValueKey('methods'),
      children: [
        const _LockHeader(subtitle: 'اختر طريقة الدخول'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'مرحباً بعودتك',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'افتح التطبيق بالطريقة التي تناسبك',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _MethodCard(
                      icon: Icons.fingerprint_rounded,
                      title: 'الدخول بالبصمة',
                      subtitle: 'بلمسة واحدة، دون كتابة الرمز',
                      highlighted: true,
                      onTap: _chooseBiometrics,
                    ),
                    const SizedBox(height: 12),
                    _OrDivider(theme: theme),
                    const SizedBox(height: 12),
                    _MethodCard(
                      icon: Icons.dialpad_rounded,
                      title: 'الدخول برمز PIN',
                      subtitle: 'أدخل رمزاً من ${AppConstants.pinLength} أرقام',
                      onTap: _choosePin,
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'بيانات المحل محفوظة على هذا الجهاز فقط',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The PIN pad (creation on the first run, unlocking afterwards).
  Widget _pinView(
    ThemeData theme, {
    required bool isSetup,
    required Duration? blocked,
  }) {
    final security = context.watch<SecurityController>();
    final subtitle = isSetup
        ? (_firstEntry == null
              ? 'اختر رمزاً من ${AppConstants.pinLength} أرقام'
              : 'أعد إدخال الرمز نفسه')
        : 'أدخل الرمز لفتح التطبيق';
    final message = blocked != null
        ? 'تم إيقاف الإدخال مؤقتاً. حاول بعد ${_formatRemaining(blocked)}'
        : _message;

    return Column(
      key: const ValueKey('pin'),
      children: [
        _LockHeader(
          subtitle: isSetup
              ? (_firstEntry == null ? 'إنشاء رمز PIN' : 'تأكيد رمز PIN')
              : 'رمز PIN',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              children: [
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                PinDots(
                  filled: _pin.length,
                  hasError: _hasError || blocked != null,
                ),
                SizedBox(
                  height: 48,
                  child: Center(
                    child: message == null
                        ? null
                        : Text(
                            message,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                  ),
                ),
                PinPad(
                  enabled: !_busy && blocked == null,
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                ),
                if (!isSetup && security.canUseBiometrics) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _busy ? null : _backToMethods,
                    icon: const Icon(Icons.fingerprint_rounded, size: 20),
                    label: const Text('الدخول بالبصمة'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The brand bar at the top of every lock screen.
class _LockHeader extends StatelessWidget {
  const _LockHeader({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[scheme.primary, const Color(0xFF059669)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.water_drop_rounded,
              size: 34,
              color: Color(0xFF0F766E),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'بكداش للأدوات الصحية',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// A large tappable choice (fingerprint / PIN).
class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = highlighted ? scheme.primaryContainer : scheme.surface;
    final foreground = highlighted
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    return Card(
      color: background,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: highlighted ? Colors.transparent : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: highlighted
                      ? scheme.primary.withValues(alpha: 0.16)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, size: 28, color: foreground),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: foreground.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                color: foreground.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The thin "or" separator between the two choices.
class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final color = theme.colorScheme.outlineVariant;
    return Row(
      children: [
        Expanded(child: Divider(color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'أو',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: Divider(color: color)),
      ],
    );
  }
}
