/// Arabic texts shared by several screens. Texts used by one feature only
/// live next to that feature.
abstract final class AppStrings {
  // Actions
  static const String save = 'حفظ';
  static const String cancel = 'إلغاء';
  static const String delete = 'حذف';
  static const String edit = 'تعديل';
  static const String add = 'إضافة';
  static const String close = 'إغلاق';
  static const String retry = 'إعادة المحاولة';
  static const String confirm = 'تأكيد';
  static const String share = 'مشاركة';
  static const String all = 'الكل';
  static const String search = 'بحث';
  static const String clear = 'مسح';
  static const String ok = 'حسناً';

  // Validation
  static const String requiredField = 'هذا الحقل مطلوب';
  static const String invalidAmount = 'أدخل مبلغاً صحيحاً';
  static const String amountMustBePositive = 'يجب أن يكون المبلغ أكبر من صفر';
  static const String invalidNumber = 'أدخل رقماً صحيحاً';

  // States
  static const String loading = 'جارٍ التحميل...';
  static const String unexpectedError = 'حدث خطأ غير متوقع، حاول مرة أخرى.';
  static const String loadFailed = 'تعذّر تحميل البيانات';

  // Navigation
  static const String tabInventory = 'المخزون';
  static const String tabInvoices = 'الفواتير';
  static const String tabCustomers = 'الزبائن';
  static const String tabReports = 'التقارير';
  static const String tabSettings = 'الإعدادات';
  static const String lockNow = 'قفل التطبيق';

  // Business info
  static const String piece = 'قطعة';
}
