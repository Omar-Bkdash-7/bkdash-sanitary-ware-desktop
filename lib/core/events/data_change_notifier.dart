import 'package:flutter/foundation.dart';

/// What a repository just committed.
enum DataWrite {
  /// A new invoice was issued.
  invoice,

  /// A saved invoice was rewritten.
  invoiceUpdated,

  /// A saved invoice was deleted.
  invoiceDeleted,

  /// An item was added, edited or removed.
  inventory,

  /// A customer was added, edited or removed.
  customers,

  /// A payment was received.
  payment,

  /// Pieces were bought from a customer.
  purchase,

  /// A purchase was deleted.
  purchaseDeleted,

  /// Money was paid to a customer for a purchase.
  payout,

  /// Pieces came back from the customer against an invoice.
  returnCreated,

  /// A saved return was deleted.
  returnDeleted,
}

/// Called after a commit; [invoiceId] is set for the invoice writes.
typedef WriteListener = void Function(DataWrite write, int? invoiceId);

/// Tells every screen holding cached data that the database content changed.
///
/// Repositories call [markChanged] after each successful write; controllers
/// listen to it and reload what they display. This keeps the controllers
/// independent from each other.
///
/// The same repositories also call [reportWrite] once the transaction
/// committed. That is what the background Telegram delivery listens to, so no
/// write path can be forgotten in a screen.
class DataChangeNotifier extends ChangeNotifier {
  final List<WriteListener> _writeListeners = <WriteListener>[];

  void addWriteListener(WriteListener listener) =>
      _writeListeners.add(listener);

  void removeWriteListener(WriteListener listener) =>
      _writeListeners.remove(listener);

  void markChanged() => notifyListeners();

  /// Reports a committed write to the background delivery.
  void reportWrite(DataWrite write, {int? invoiceId}) {
    for (final listener in List<WriteListener>.of(_writeListeners)) {
      listener(write, invoiceId);
    }
  }
}
