import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/empty_state.dart';
import 'package:bkdash_sanitary_ware/core/widgets/form_fields.dart';
import 'package:bkdash_sanitary_ware/core/widgets/load_state_view.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/create_invoice_screen.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/invoice_card.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/invoice_details_screen.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/invoices_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The issued invoices, with filters and the button for a new invoice.
class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InvoicesController>();
    return Scaffold(
      body: LoadStateView(
        status: controller.status,
        errorMessage: controller.errorMessage,
        onRetry: controller.load,
        builder: (context) => _InvoicesBody(controller: controller),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createInvoice(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('فاتورة جديدة'),
      ),
    );
  }

  Future<void> _createInvoice(BuildContext context) async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(builder: (_) => const CreateInvoiceScreen()),
    );
    if (id != null && context.mounted) {
      showAppSnackBar(context, 'تم حفظ الفاتورة #$id');
    }
  }
}

class _InvoicesBody extends StatelessWidget {
  const _InvoicesBody({required this.controller});

  final InvoicesController controller;

  @override
  Widget build(BuildContext context) {
    final invoices = controller.visible;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: SearchField(
            hint: 'ابحث باسم الزبون أو رقم الفاتورة...',
            onChanged: controller.setQuery,
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final filter in InvoiceFilter.values)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    label: Text(filter.label),
                    selected: controller.filter == filter,
                    onSelected: (_) => controller.setFilter(filter),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: invoices.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'لا توجد فواتير',
                  message: 'اضغط «فاتورة جديدة» لإصدار أول فاتورة.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                  itemCount: invoices.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => InvoiceCard(
                    invoice: invoices[index],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            InvoiceDetailsScreen(invoiceId: invoices[index].id),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
