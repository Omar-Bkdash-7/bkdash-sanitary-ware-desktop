import 'package:bkdash_sanitary_ware/core/constants/app_strings.dart';
import 'package:bkdash_sanitary_ware/core/errors/app_exception.dart';
import 'package:flutter/foundation.dart';

enum LoadStatus { initial, loading, ready, failure }

/// Base of the screen controllers (the "view models" of the app).
///
/// It tracks the loading state of the screen data and makes sure a controller
/// never notifies after it was disposed (a late database answer is harmless).
abstract class BaseController extends ChangeNotifier {
  LoadStatus _status = LoadStatus.initial;
  String? _errorMessage;
  bool _disposed = false;

  LoadStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isDisposed => _disposed;

  /// Runs [action] and updates [status]. Data already on screen stays visible
  /// while a refresh is running.
  @protected
  Future<void> runLoad(Future<void> Function() action) async {
    if (_status != LoadStatus.ready) {
      _status = LoadStatus.loading;
      notifyListeners();
    }
    try {
      await action();
      _status = LoadStatus.ready;
      _errorMessage = null;
    } on AppException catch (error) {
      _status = LoadStatus.failure;
      _errorMessage = error.message;
    } catch (error, stackTrace) {
      debugPrint('Load failed: $error\n$stackTrace');
      _status = LoadStatus.failure;
      _errorMessage = AppStrings.unexpectedError;
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
