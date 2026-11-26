import 'dart:async';

import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/widgets/bkdash_logo.dart';
import 'package:bkdash_sanitary_ware/features/customers/presentation/customers_controller.dart';
import 'package:bkdash_sanitary_ware/features/customers/presentation/customers_screen.dart';
import 'package:bkdash_sanitary_ware/features/inventory/presentation/inventory_controller.dart';
import 'package:bkdash_sanitary_ware/features/inventory/presentation/inventory_screen.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/invoices_controller.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/invoices_screen.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/presentation/sync_center_controller.dart';
import 'package:bkdash_sanitary_ware/features/phone_sync/presentation/sync_center_screen.dart';
import 'package:bkdash_sanitary_ware/features/reports/presentation/reports_controller.dart';
import 'package:bkdash_sanitary_ware/features/reports/presentation/reports_screen.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/security_controller.dart';
import 'package:bkdash_sanitary_ware/features/settings/presentation/settings_screen.dart';
import 'package:bkdash_sanitary_ware/features/telegram/presentation/sync_log_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The unlocked program: a side rail with six sections and the controllers that
/// feed them.
///
/// The controllers live only while the program is unlocked, so no business data
/// stays in memory behind the lock screen (same rule as on the phone).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = context.read<AppDependencies>();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<InventoryController>(
          create: (_) =>
              InventoryController(repository: deps.items, changes: deps.changes)
                ..load(),
        ),
        ChangeNotifierProvider<InvoicesController>(
          create: (_) => InvoicesController(
            repository: deps.invoices,
            changes: deps.changes,
          )..load(),
        ),
        ChangeNotifierProvider<CustomersController>(
          create: (_) => CustomersController(
            customers: deps.customers,
            payments: deps.payments,
            purchases: deps.purchases,
            changes: deps.changes,
          )..load(),
        ),
        ChangeNotifierProvider<ReportsController>(
          create: (_) =>
              ReportsController(repository: deps.reports, changes: deps.changes)
                ..load(),
        ),
        ChangeNotifierProvider<SyncCenterController>(
          create: (_) => SyncCenterController(
            service: deps.phoneSync,
            queue: deps.syncQueue,
            changes: deps.changes,
          )..load(),
        ),
      ],
      child: const _HomeScaffold(),
    );
  }
}

class _HomeScaffold extends StatefulWidget {
  const _HomeScaffold();

  @override
  State<_HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<_HomeScaffold> {
  static const int _syncIndex = 4;

  int _index = 0;

  static const List<_Tab> _tabs = <_Tab>[
    _Tab(
      AppStrings.tabInventory,
      Icons.inventory_2_outlined,
      Icons.inventory_2,
    ),
    _Tab(
      AppStrings.tabInvoices,
      Icons.receipt_long_outlined,
      Icons.receipt_long,
    ),
    _Tab(AppStrings.tabCustomers, Icons.people_outline, Icons.people),
    _Tab(AppStrings.tabReports, Icons.bar_chart_outlined, Icons.bar_chart),
    _Tab('المزامنة', Icons.phonelink_outlined, Icons.phonelink),
    _Tab(AppStrings.tabSettings, Icons.settings_outlined, Icons.settings),
  ];

  /// Ctrl+1 ... Ctrl+6 jump to a section.
  static final List<LogicalKeyboardKey> _digits = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
  ];

  void _select(int index) {
    setState(() => _index = index);
    if (index == _syncIndex) {
      // Telegram settings or data may have changed since the screen was built.
      unawaited(context.read<SyncCenterController>().refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final security = context.read<SecurityController>();

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        for (var i = 0; i < _tabs.length; i++)
          SingleActivator(_digits[i], control: true): () => _select(i),
        const SingleActivator(LogicalKeyboardKey.keyL, control: true):
            security.lock,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: BkdashLogo(size: 34, isDark: isDark),
            actions: [
              ValueListenableBuilder<int>(
                valueListenable: context
                    .read<AppDependencies>()
                    .syncCoordinator
                    .pending,
                builder: (context, pending, _) => IconButton(
                  tooltip: pending == 0
                      ? 'سجل الإرسال'
                      : '$pending بانتظار الإرسال إلى تيليجرام',
                  icon: Icon(
                    pending == 0
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_sync_outlined,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SyncLogScreen(),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '${AppStrings.lockNow} (Ctrl+L)',
                icon: const Icon(Icons.lock_outline_rounded),
                onPressed: security.lock,
              ),
            ],
          ),
          body: Row(
            children: [
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        selectedIndex: _index,
                        onDestinationSelected: _select,
                        labelType: NavigationRailLabelType.all,
                        destinations: [
                          for (final tab in _tabs)
                            NavigationRailDestination(
                              icon: Icon(tab.icon),
                              selectedIcon: Icon(tab.selectedIcon),
                              label: Text(tab.label),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: IndexedStack(
                      index: _index,
                      sizing: StackFit.expand,
                      children: const [
                        InventoryScreen(),
                        InvoicesScreen(),
                        CustomersScreen(),
                        ReportsScreen(),
                        SyncCenterScreen(),
                        SettingsScreen(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
