/// Base class of every error whose message can be shown to the user as is.
sealed class AppException implements Exception {
  const AppException(this.message);

  /// A user-facing (Arabic) description of what went wrong.
  final String message;

  @override
  String toString() => message;
}

/// The data entered by the user is not acceptable.
final class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// A sale line asks for more pieces than the stock holds.
final class InsufficientStockException extends AppException {
  InsufficientStockException({
    required this.itemName,
    required this.available,
    required this.requested,
  }) : super(
         'الكمية المتوفرة من "$itemName" هي $available فقط '
         '(المطلوب $requested).',
       );

  final String itemName;
  final int available;
  final int requested;
}

/// Another item already uses the same SKU / code.
final class DuplicateSkuException extends AppException {
  DuplicateSkuException(this.sku)
    : super('الرمز "$sku" مستخدم لصنف آخر، اختر رمزاً مختلفاً.');

  final String sku;
}

/// The requested record does not exist (anymore).
final class NotFoundException extends AppException {
  const NotFoundException(super.message);
}

/// The operation conflicts with existing data (e.g. deleting a used record).
final class ConflictException extends AppException {
  const ConflictException(super.message);
}

/// Creating, reading or restoring a backup failed.
final class BackupException extends AppException {
  const BackupException(super.message);
}

/// Linking with the desktop program or sending to Telegram failed.
final class SyncException extends AppException {
  const SyncException(super.message);
}

/// Telegram refused the request (bad token, unknown chat, rate limit, ...).
final class TelegramException extends AppException {
  const TelegramException(super.message, {this.retryAfter});

  /// For a `429` answer: how long Telegram asked us to wait.
  final Duration? retryAfter;
}
