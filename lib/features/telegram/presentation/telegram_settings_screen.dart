import 'package:bkdash_sanitary_ware/app/app_dependencies.dart';
import 'package:bkdash_sanitary_ware/core/presentation/base_controller.dart';
import 'package:bkdash_sanitary_ware/core/widgets/app_feedback.dart';
import 'package:bkdash_sanitary_ware/core/widgets/load_state_view.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/telegram_settings.dart';
import 'package:bkdash_sanitary_ware/features/telegram/presentation/telegram_settings_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The bot token, the chat id, the two automatic switches and a manual send.
class TelegramSettingsScreen extends StatelessWidget {
  const TelegramSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<TelegramSettingsController>(
      create: (context) {
        try {
          final deps = context.read<AppDependencies>();
          return TelegramSettingsController(
            settings: deps.telegramSettings,
            service: deps.telegram,
            snapshots: deps.snapshots,
            backups: deps.backups,
          )..load();
        } catch (e, stackTrace) {
          debugPrint('Failed to create TelegramSettingsController: $e\n$stackTrace');
          rethrow;
        }
      },
      child: const _TelegramSettingsView(),
    );
  }
}

class _TelegramSettingsView extends StatefulWidget {
  const _TelegramSettingsView();

  @override
  State<_TelegramSettingsView> createState() => _TelegramSettingsViewState();
}

class _TelegramSettingsViewState extends State<_TelegramSettingsView> {
  final TextEditingController _token = TextEditingController();
  final TextEditingController _chatId = TextEditingController();

  bool _obscure = true;
  bool _bound = false;

  @override
  void dispose() {
    _token.dispose();
    _chatId.dispose();
    super.dispose();
  }

  /// The field starts empty: the stored token is shown only in its masked form.
  TelegramSettings _collect(TelegramSettingsController controller) {
    final typed = _token.text.trim();
    return controller.settings.copyWith(
      token: typed.isEmpty ? controller.settings.token : typed,
      chatId: _chatId.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TelegramSettingsController>();
    final theme = Theme.of(context);
    final busy = controller.isBusy;

    if (!_bound && controller.status == LoadStatus.ready) {
      _chatId.text = controller.settings.chatId;
      _bound = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات تيليجرام')),
      body: LoadStateView(
        status: controller.status,
        errorMessage: controller.errorMessage,
        onRetry: controller.load,
        builder: (context) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('البوت', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'أنشئ بوتاً من @BotFather في Telegram، ثم افتح محادثته '
                      'واضغط /start حتى يستطيع إرسال الملفات إليك.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _token,
                      enabled: !busy,
                      obscureText: _obscure,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'رمز البوت (Bot Token)',
                        hintText: controller.settings.maskedToken.isEmpty
                            ? '123456789:AA...'
                            : controller.settings.maskedToken,
                        helperText: controller.settings.maskedToken.isEmpty
                            ? 'يُخزَّن مشفّراً على هذا الجهاز'
                            : 'محفوظ: ${controller.settings.maskedToken}',
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'إظهار' : 'إخفاء',
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _chatId,
                      enabled: !busy,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'معرّف المحادثة (Chat ID)',
                        helperText: 'رقم محادثتك مع البوت، مثل 123456789',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () => runUiAction(
                                    context,
                                    () => controller.save(_collect(controller)),
                                  ),
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('حفظ'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => runUiAction(context, () async {
                                    await controller.save(_collect(controller));
                                    await controller.testConnection();
                                  }),
                            icon: const Icon(Icons.send_outlined),
                            label: const Text('اختبار الاتصال'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.picture_as_pdf_outlined),
                    title: const Text('إرسال الفاتورة PDF تلقائياً'),
                    subtitle: const Text(
                      'تصل نسخة PDF من كل فاتورة جديدة إلى المحادثة.',
                    ),
                    value: controller.settings.sendInvoicePdf,
                    onChanged: busy
                        ? null
                        : (value) => runUiAction(
                            context,
                            () => controller.setSendInvoicePdf(value: value),
                          ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.storage_outlined),
                    title: const Text('إرسال نسخة قاعدة البيانات تلقائياً'),
                    subtitle: const Text(
                      'تُرسل نسخة واحدة بعد آخر تعديل، لا نسخة لكل حركة.',
                    ),
                    value: controller.settings.sendDatabase,
                    onChanged: busy
                        ? null
                        : (value) => runUiAction(
                            context,
                            () => controller.setSendDatabase(value: value),
                          ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    enabled: !busy,
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: const Text('إرسال نسخة الآن'),
                    subtitle: const Text(
                      'نسخة قاعدة بيانات كاملة تُرسل فوراً.',
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () =>
                        runUiAction(context, controller.sendSnapshotNow),
                  ),
                ],
              ),
            ),
            if (controller.info != null) ...[
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(controller.info!),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'الملفات تُرسل من هذا الكمبيوتر مباشرة إلى Telegram، ولا تُحفظ عند أي '
              'خدمة أخرى.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
