import 'package:bkdash_sanitary_ware/app/home_shell.dart';
import 'package:bkdash_sanitary_ware/core/widgets/bkdash_logo.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/lock_screen.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/security_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Decides what is on screen: the lock screen or the app itself, and locks the
/// app again after it stayed in the background for a while.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final security = context.read<SecurityController>();
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        security.appPaused();
      case AppLifecycleState.resumed:
        security.appResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = context.select<SecurityController, LockStatus>(
      (security) => security.status,
    );
    switch (status) {
      case LockStatus.loading:
        return const Scaffold(body: Center(child: BkdashLogo(size: 72)));
      case LockStatus.needsSetup:
      case LockStatus.locked:
        return const LockScreen();
      case LockStatus.unlocked:
        return const HomeShell();
    }
  }
}
