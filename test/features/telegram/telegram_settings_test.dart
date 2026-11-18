import 'package:bkdash_sanitary_ware/features/backup/models/data_summary.dart';
import 'package:bkdash_sanitary_ware/features/telegram/data/telegram_service.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/backup_caption.dart';
import 'package:bkdash_sanitary_ware/features/telegram/models/telegram_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TelegramSettings', () {
    test('the token is masked and never shown in full', () {
      const settings = TelegramSettings(
        token: '123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw',
        chatId: '987654',
      );
      expect(settings.maskedToken, startsWith('1234'));
      expect(settings.maskedToken, endsWith('Dsaw'));
      expect(settings.maskedToken, contains('••••'));
      expect(settings.maskedToken, isNot(contains('AAHdqTcvCH1vGWJxfSeof')));
    });

    test('a short or empty token is masked completely', () {
      expect(const TelegramSettings().maskedToken, '');
      expect(const TelegramSettings(token: '123:abc').maskedToken, '••••••••');
    });

    test('isConfigured needs both the token and the chat id', () {
      expect(const TelegramSettings(token: 'x').isConfigured, isFalse);
      expect(
        const TelegramSettings(token: 'x', chatId: 'y').isConfigured,
        isTrue,
      );
      expect(const TelegramSettings(chatId: 'y').isConfigured, isFalse);
    });
  });

  group('captions', () {
    test('a long caption is cut to what Telegram accepts', () {
      final text = 'ا' * 2000;
      expect(TelegramService.clampCaption(text).length, 1024);
      expect(TelegramService.clampCaption('قصير'), 'قصير');
    });

    test('the database caption ends with the machine-readable line', () {
      final caption = BackupCaption.database(
        sentAt: DateTime(2026, 11, 16, 15, 30, 5),
        summary: const DataSummary(
          invoices: 12,
          customers: 4,
          products: 67,
          schemaVersion: 1,
        ),
        fileName: 'bkdash_2026-11-16_15-30.db',
      );
      expect(caption, contains('bkdash_2026-11-16_15-30.db'));
      expect(
        caption,
        endsWith(
          '#bkdash_sync v=1 schema=1 ts=2026-11-16T15:30:05 '
          'invoices=12 customers=4 products=67',
        ),
      );
    });
  });
}
