/// Where the invoices and the database copies are sent, and whether they are
/// sent automatically.
///
/// The token and the chat id are the shop's secrets: they are stored encrypted
/// and never logged or shown in full.
final class TelegramSettings {
  const TelegramSettings({
    this.token = '',
    this.chatId = '',
    this.sendInvoicePdf = true,
    this.sendDatabase = true,
  });

  /// The bot token from `@BotFather`, e.g. `123456789:AA...`.
  final String token;

  /// The chat that receives the files (a private chat with the shop).
  final String chatId;

  /// Send the invoice as a PDF right after it is saved.
  final bool sendInvoicePdf;

  /// Send a database snapshot after the data settles.
  final bool sendDatabase;

  bool get isConfigured => token.trim().isNotEmpty && chatId.trim().isNotEmpty;

  /// "1234••••••wxyz" - safe to show on screen.
  String get maskedToken {
    final value = token.trim();
    if (value.isEmpty) return '';
    if (value.length <= 8) return '••••••••';
    return '${value.substring(0, 4)}••••••${value.substring(value.length - 4)}';
  }

  TelegramSettings copyWith({
    String? token,
    String? chatId,
    bool? sendInvoicePdf,
    bool? sendDatabase,
  }) => TelegramSettings(
    token: token ?? this.token,
    chatId: chatId ?? this.chatId,
    sendInvoicePdf: sendInvoicePdf ?? this.sendInvoicePdf,
    sendDatabase: sendDatabase ?? this.sendDatabase,
  );
}
