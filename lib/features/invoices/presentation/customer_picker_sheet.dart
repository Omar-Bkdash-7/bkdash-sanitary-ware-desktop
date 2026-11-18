import 'package:bkdash_sanitary_ware/core/formatting/search_text.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/empty_state.dart';
import 'package:bkdash_sanitary_ware/core/widgets/form_fields.dart';
import 'package:bkdash_sanitary_ware/features/customers/presentation/customer_form_sheet.dart';
import 'package:bkdash_sanitary_ware/features/invoices/presentation/create_invoice_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Chooses the customer of the invoice (or a walk-in customer, or a new one).
Future<void> showCustomerPickerSheet(
  BuildContext context,
  CreateInvoiceController controller,
) {
  return showFormSheet<void>(
    context,
    builder: (_) => ChangeNotifierProvider<CreateInvoiceController>.value(
      value: controller,
      child: const _CustomerPicker(),
    ),
  );
}

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker();

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  String _query = '';

  Future<void> _createCustomer(CreateInvoiceController controller) async {
    final created = await showCustomerFormSheet(
      context,
      onSave: controller.addCustomer,
    );
    if (created == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CreateInvoiceController>();
    final theme = Theme.of(context);
    final query = normalizeForSearch(_query);
    final customers = controller.customers.where((customer) {
      if (query.isEmpty) return true;
      return normalizeForSearch(customer.name).contains(query) ||
          customer.phone.contains(query);
    }).toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'اختيار الزبون',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _createCustomer(controller),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('زبون جديد'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchField(
              hint: 'ابحث بالاسم أو الهاتف...',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.storefront_outlined)),
            title: const Text('زبون نقدي (بدون تسجيل)'),
            selected: controller.draft.customer == null,
            onTap: () {
              controller.selectCustomer(null);
              Navigator.of(context).pop();
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: customers.isEmpty
                ? const EmptyState(
                    icon: Icons.people_outline_rounded,
                    title: 'لا يوجد زبائن مطابقون',
                  )
                : ListView.separated(
                    itemCount: customers.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(customer.name.characters.first),
                        ),
                        title: Text(customer.name),
                        subtitle: customer.phone.isEmpty
                            ? null
                            : Text(
                                customer.phone,
                                textDirection: TextDirection.ltr,
                              ),
                        selected: controller.draft.customer?.id == customer.id,
                        onTap: () {
                          controller.selectCustomer(customer);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
