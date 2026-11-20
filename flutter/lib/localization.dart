import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class AppLocales {
  static const english = Locale('en');
  static const persian = Locale('fa');
  static const iraqiArabic = Locale('ar', 'IQ');
  static const supported = <Locale>[english, persian, iraqiArabic];
  static bool isRtl(Locale locale) =>
      const {'fa', 'ar'}.contains(locale.languageCode);
  static Locale resolve(Locale? locale) {
    if (locale?.languageCode == 'fa') return persian;
    if (locale?.languageCode == 'ar') return iraqiArabic;
    return english;
  }

  static String encode(Locale locale) {
    final value = resolve(locale);
    return value.countryCode == null
        ? value.languageCode
        : '${value.languageCode}-${value.countryCode}';
  }

  static Locale? decode(String? value) {
    switch (value?.trim().replaceAll('_', '-').toLowerCase()) {
      case 'en':
        return english;
      case 'fa':
      case 'fa-ir':
        return persian;
      case 'ar':
      case 'ar-iq':
        return iraqiArabic;
      default:
        return null;
    }
  }
}

class LocaleStore {
  final File file;
  const LocaleStore(this.file);
  Future<Locale?> read() async {
    try {
      return AppLocales.decode(file.readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(Locale locale) async {
    file.parent.createSync(recursive: true);
    final temporary = File('${file.path}.tmp');
    temporary.writeAsStringSync(AppLocales.encode(locale), flush: true);
    try {
      temporary.renameSync(file.path);
    } on FileSystemException {
      if (file.existsSync()) file.deleteSync();
      temporary.renameSync(file.path);
    }
  }
}

class LocaleController extends ChangeNotifier {
  final LocaleStore store;
  Locale _locale;
  LocaleController(this.store, {Locale initialLocale = AppLocales.english})
    : _locale = AppLocales.resolve(initialLocale);
  Locale get locale => _locale;
  TextDirection get textDirection =>
      AppLocales.isRtl(_locale) ? TextDirection.rtl : TextDirection.ltr;
  Future<void> load({Locale? systemLocale}) async {
    _locale = AppLocales.resolve(await store.read() ?? systemLocale);
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    final resolved = AppLocales.resolve(locale);
    if (resolved == _locale) return;
    _locale = resolved;
    notifyListeners();
    await store.write(resolved);
  }
}

class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);
  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(AppLocales.english);
  String text(String key) =>
      _translations[AppLocales.encode(locale)]?[key] ??
      _translations['en']![key] ??
      key;
  String get appName => text('appName');
  String get language => text('language');
  String get english => text('english');
  String get persian => text('persian');
  String get iraqiArabic => text('iraqiArabic');
  String get connect => text('connect');
  String get disconnect => text('disconnect');
  String get settings => text('settings');
  static Set<String> get keys => _translations['en']!.keys.toSet();
  bool hasTranslation(String key) =>
      _translations[AppLocales.encode(locale)]?.containsKey(key) == true;
  static const delegate = _AppLocalizationsDelegate();
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) =>
      const {'en', 'fa', 'ar'}.contains(locale.languageCode);
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(AppLocales.resolve(locale)));
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

// Flutter's full locale bundle depends on the external intl package. These
// delegates keep the app dependency-free and provide framework control labels;
// all user-facing Aether text is translated by [AppLocalizations].
class _FallbackMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _FallbackMaterialLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) =>
      const {'en', 'fa', 'ar'}.contains(locale.languageCode);
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      DefaultMaterialLocalizations.delegate.load(AppLocales.english);
  @override
  bool shouldReload(_FallbackMaterialLocalizationsDelegate old) => false;
}

class _FallbackWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _FallbackWidgetsLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) =>
      const {'en', 'fa', 'ar'}.contains(locale.languageCode);
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      DefaultWidgetsLocalizations.delegate.load(AppLocales.english);
  @override
  bool shouldReload(_FallbackWidgetsLocalizationsDelegate old) => false;
}

class _FallbackCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _FallbackCupertinoLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) =>
      const {'en', 'fa', 'ar'}.contains(locale.languageCode);
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      DefaultCupertinoLocalizations.delegate.load(AppLocales.english);
  @override
  bool shouldReload(_FallbackCupertinoLocalizationsDelegate old) => false;
}

const _translations = <String, Map<String, String>>{
  'en': {
    'appName': 'Aether VPN',
    'language': 'Language',
    'english': 'English',
    'persian': 'Persian',
    'iraqiArabic': 'Iraqi Arabic',
    'connect': 'Connect',
    'disconnect': 'Disconnect',
    'settings': 'Settings',
    'connection': 'Connection',
    'nextProtocol': 'Next protocol',
    'next': 'Next',
    'connected': 'Connected',
    'connectingCancel': 'Connecting… tap to cancel',
    'cancel': 'Cancel',
    'batteryGuideTitle': 'Background running',
    'stepsFor': 'Steps for {device}',
    'thisPhone': 'this phone',
    'batteryAlreadyOff': 'Battery optimization is already off for Aether',
    'open': 'Open',
    'settingOpenFailed':
        'Could not open it here. Search Settings for the name.',
    'batteryGuideNote':
        'Only the battery optimization step can be checked by the app; the others cannot be detected, so they are always shown. Menu names differ between phone models and versions. These settings help, but Android or your phone maker may still stop apps in the background, so a stable connection is not guaranteed.',
    'batteryOptimization': 'Battery optimization',
    'batteryOptimizationBody':
        'Find Aether in the list (choose ?All apps? if needed) and set it to ?Don?t optimize?.',
    'openBatteryOptimization': 'Open battery optimization',
    'appBatteryUsage': 'App battery usage',
    'appBatteryUsageBody':
        'Open App info > Battery (or ?App battery usage?) and choose ?{mode}?.',
    'openAppInfo': 'Open App info',
    'neverSleepingApps': 'Never sleeping apps',
    'samsungBatteryBody':
        'Settings > Battery > Background usage limits: remove Aether from ?Sleeping apps? and ?Deep sleeping apps?, turn off ?Put unused apps to sleep?, and add Aether to ?Never sleeping apps?.',
    'openSamsungBattery': 'Open Samsung battery',
    'autostart': 'Autostart',
    'autostartBody': 'Turn on Autostart for Aether.',
    'openAutostart': 'Open Autostart',
    'batterySaver': 'Battery saver',
    'xiaomiBatteryBody':
        'In App info > Battery saver (or ?Battery usage?) choose ?No restrictions?. Also open Recent apps, long-press the Aether card and tap the lock icon.',
    'appLaunch': 'App launch',
    'huaweiLaunchBody':
        'Settings > Apps > App launch: set Aether to ?Manage manually? and turn on ?Auto-launch?, ?Secondary launch? and ?Run in background?.',
    'openAppLaunch': 'Open App launch',
    'autoLaunch': 'Auto-launch',
    'oppoLaunchBody':
        'Allow Aether to auto-launch (Settings > Apps > Auto launch, or App info > ?Allow auto launch?).',
    'openAutoLaunch': 'Open Auto-launch',
    'backgroundActivity': 'Background activity',
    'oppoBackgroundBody':
        'In App info > Battery usage turn on ?Allow background activity?. Lock Aether in Recent apps if your phone offers it.',
    'vivoBackgroundBody':
        'In Settings > Battery > Background power consumption management, allow Aether to use power in the background.',
    'autoOrder': 'Auto order',
    'reset': 'Reset',
    'save': 'Save',
    'autoOrderEmpty': 'Check at least one protocol for Auto.',
    'autoOrderHelp':
        'Auto tries the checked protocols from the top. After each try the app puts protocols that worked on top (best success rate, then fastest) and ones that only failed at the bottom. Drag the handle to reorder. Reset restores the speed ranking.',
    'worksForYou': 'Works for you',
    'oftenFails': 'Often fails',
    'tooFewTries': 'Too few tries',
    'notTriedYet': 'Not tried yet',
    'okCount': '{count} ok',
    'failedCount': '{count} failed',
    'successRate': '{rate}% success',
    'averageSeconds': 'avg {seconds}s',
    'lastOk': 'last ok {ago}',
    'justNow': 'just now',
    'minutesAgo': '{count}m ago',
    'hoursAgo': '{count}h ago',
    'daysAgo': '{count}d ago',
    'protocolOrder': 'Protocol order',
    'done': 'Done',
    'autoOrderInSettings': 'Auto (order in Settings)',
    'coreSettings': 'Core settings',
    'loadingCoreHelp': 'Loading bundled core help?',
    'coreHelpFailed': 'Could not read bundled core help.',
    'saveSettingsFailed': 'Could not save settings.',
    'coreExpertIntro':
        'Expert options apply to every selected protocol. Choose a manual protocol for protocol-specific options. Flags override environment variables. Unsupported combinations are reported by the core.',
    'coreManagedIntro':
        'Protocol, proxy ports and bundled helper paths are app-managed. SO_MARK needs root; external helper executables must be packaged for Android. File paths must be accessible to the app.',
    'coreSensitiveWarning':
        'Arguments and environment variables can contain sensitive data.',
    'additionalArguments': 'Additional arguments (JSON array)',
    'environmentJson': 'Environment (JSON object)',
    'startupTimeout': 'Advanced startup timeout (seconds)',
    'startupTimeoutHelp':
        '30?3600; used when a country or extra arguments/environment are configured.',
    'resetFields': 'Reset fields to defaults',
    'featureExamples': 'Feature examples',
    'bundledCoreHelp': 'Bundled core: full help',
    'autoTrySeconds': 'Auto try (seconds)',
    'reconnectAether': 'Reconnect Aether',
    'autoFastestRoute': 'Auto - fastest route',
    'resetOrderAndConnect': 'Reset order and connect',
    'tapToChooseOrDrag': 'Tap to choose or drag to reorder',
    'quickSettings': 'Quick Settings',
    'autoConnectStartup': 'Auto-Connect on Startup',
    'killSwitch': 'Kill Switch',
    'killSwitchSubtitle':
        'Turn on "Always-on VPN" and "Block connections without VPN"',
    'backgroundRunningSubtitle':
        'Step-by-step guide for your phone to keep the VPN running with the screen off',
    'connectionSteps': 'Connection steps',
    'clear': 'Clear',
    'copyError': 'Copy error',
    'errorCopied': 'Error copied',
    'dismissError': 'Dismiss error',
    'psiphonServerCountry': 'Psiphon server country',
    'serverSearch': 'Server search',
    'fast': 'Fast',
    'balanced': 'Balanced',
    'realDelayTest': 'Real delay test',
    'realDelayTestSubtitle':
        'Verify internet access and measure delay. When off, only the local proxy is checked.',
    'delayTestUrl': 'Delay test URL',
    'mode': 'Mode',
    'vpnAllApps': 'VPN (all apps)',
    'proxyOnly': 'Proxy only',
    'httpPort': 'HTTP port',
    'socksPort': 'SOCKS5 port',
    'advanced': 'Advanced',
    'coreInput': 'Core input',
    'coreInputSubtitle': 'Send a sign-in code the core asks for',
    'proxyInfo': 'Proxy info',
    'checkForUpdates': 'Check for updates',
    'showActivityLog': 'Show activity log',
    'diagnostics': 'Diagnostics',
    'diagnosticsHelp':
        'Reports stay on this device unless you copy them. Credentials and common tokens are redacted, and only recent activity is retained.',
    'copyReport': 'Copy report',
    'saveLocally': 'Save locally',
    'activity': 'Activity',
    'clearActivity': 'Clear activity',
    'waitingForLogs': 'Waiting for logs...',
  },
  'fa': {
    'appName': 'ایثر وی‌پی‌ان',
    'language': 'زبان',
    'english': 'انگلیسی',
    'persian': 'فارسی',
    'iraqiArabic': 'عربی عراقی',
    'connect': 'اتصال',
    'disconnect': 'قطع اتصال',
    'settings': 'تنظیمات',
    'connection': 'اتصال',
    'nextProtocol': 'پروتکل بعدی',
    'next': 'بعدی',
    'connected': 'متصل',
    'connectingCancel': 'در حال اتصال… برای لغو بزنید',
    'cancel': 'لغو',
    'batteryGuideTitle': 'اجرای پس‌زمینه',
    'stepsFor': 'مراحل برای {device}',
    'thisPhone': 'این گوشی',
    'batteryAlreadyOff': 'بهینه‌سازی باتری برای ایثر از قبل خاموش است',
    'open': 'باز کردن',
    'settingOpenFailed': 'این بخش باز نشد. نام آن را در تنظیمات جست‌وجو کنید.',
    'batteryGuideNote':
        'برنامه فقط می‌تواند وضعیت بهینه‌سازی باتری را بررسی کند؛ مراحل دیگر قابل تشخیص نیستند و همیشه نمایش داده می‌شوند. نام منوها بین مدل‌ها و نسخه‌ها فرق می‌کند. این تنظیمات کمک می‌کنند، اما ممکن است اندروید یا سازندهٔ گوشی همچنان برنامه را در پس‌زمینه متوقف کند.',
    'batteryOptimization': 'بهینه‌سازی باتری',
    'batteryOptimizationBody':
        'ایثر را در فهرست پیدا کنید (در صورت نیاز «همهٔ برنامه‌ها» را انتخاب کنید) و آن را روی «بهینه‌سازی نشود» بگذارید.',
    'openBatteryOptimization': 'باز کردن بهینه‌سازی باتری',
    'appBatteryUsage': 'مصرف باتری برنامه',
    'appBatteryUsageBody':
        'اطلاعات برنامه > باتری (یا «مصرف باتری برنامه») را باز کنید و «{mode}» را انتخاب کنید.',
    'openAppInfo': 'باز کردن اطلاعات برنامه',
    'neverSleepingApps': 'برنامه‌های هرگز خواب',
    'samsungBatteryBody':
        'تنظیمات > باتری > محدودیت مصرف پس‌زمینه: ایثر را از برنامه‌های خواب و خواب عمیق خارج کنید، خواباندن برنامه‌های بدون استفاده را خاموش کنید و ایثر را به برنامه‌های هرگز خواب اضافه کنید.',
    'openSamsungBattery': 'باز کردن تنظیمات باتری سامسونگ',
    'autostart': 'اجرای خودکار',
    'autostartBody': 'اجرای خودکار ایثر را روشن کنید.',
    'openAutostart': 'باز کردن اجرای خودکار',
    'batterySaver': 'ذخیره‌کنندهٔ باتری',
    'xiaomiBatteryBody':
        'در اطلاعات برنامه > ذخیره‌کنندهٔ باتری، «بدون محدودیت» را انتخاب کنید. همچنین در برنامه‌های اخیر، کارت ایثر را نگه دارید و نماد قفل را بزنید.',
    'appLaunch': 'راه‌اندازی برنامه',
    'huaweiLaunchBody':
        'تنظیمات > برنامه‌ها > راه‌اندازی برنامه: ایثر را روی «مدیریت دستی» بگذارید و راه‌اندازی خودکار، راه‌اندازی ثانویه و اجرا در پس‌زمینه را روشن کنید.',
    'openAppLaunch': 'باز کردن راه‌اندازی برنامه',
    'autoLaunch': 'راه‌اندازی خودکار',
    'oppoLaunchBody':
        'در تنظیمات برنامه‌ها، اجازهٔ راه‌اندازی خودکار را برای ایثر فعال کنید.',
    'openAutoLaunch': 'باز کردن راه‌اندازی خودکار',
    'backgroundActivity': 'فعالیت پس‌زمینه',
    'oppoBackgroundBody':
        'در اطلاعات برنامه > مصرف باتری، «اجازهٔ فعالیت در پس‌زمینه» را روشن کنید و در صورت امکان ایثر را در برنامه‌های اخیر قفل کنید.',
    'vivoBackgroundBody':
        'در تنظیمات > باتری > مدیریت مصرف برق پس‌زمینه، به ایثر اجازه دهید در پس‌زمینه باتری مصرف کند.',
    'autoOrder': 'ترتیب خودکار',
    'reset': 'بازنشانی',
    'save': 'ذخیره',
    'autoOrderEmpty': 'برای حالت خودکار حداقل یک پروتکل را انتخاب کنید.',
    'autoOrderHelp':
        'حالت خودکار پروتکل‌های انتخاب‌شده را از بالا امتحان می‌کند. پروتکل‌های موفق بر اساس نرخ موفقیت و سرعت بالا می‌آیند و موارد ناموفق پایین می‌روند. برای تغییر ترتیب دستگیره را بکشید.',
    'worksForYou': 'برای شما کار می‌کند',
    'oftenFails': 'اغلب ناموفق است',
    'tooFewTries': 'آزمایش‌های کم',
    'notTriedYet': 'هنوز آزمایش نشده',
    'okCount': '{count} موفق',
    'failedCount': '{count} ناموفق',
    'successRate': '{rate}٪ موفقیت',
    'averageSeconds': 'میانگین {seconds} ثانیه',
    'lastOk': 'آخرین موفقیت {ago}',
    'justNow': 'همین حالا',
    'minutesAgo': '{count} دقیقه پیش',
    'hoursAgo': '{count} ساعت پیش',
    'daysAgo': '{count} روز پیش',
    'protocolOrder': 'ترتیب پروتکل‌ها',
    'done': 'انجام شد',
    'autoOrderInSettings': 'خودکار (ترتیب در تنظیمات)',
    'coreSettings': 'تنظیمات هسته',
    'loadingCoreHelp': 'در حال بارگیری راهنمای هسته…',
    'coreHelpFailed': 'راهنمای هستهٔ همراه خوانده نشد.',
    'saveSettingsFailed': 'تنظیمات ذخیره نشد.',
    'coreExpertIntro':
        'گزینه‌های پیشرفته روی همهٔ پروتکل‌های انتخابی اعمال می‌شوند. برای گزینه‌های ویژه، یک پروتکل دستی انتخاب کنید. پرچم‌ها بر متغیرهای محیطی اولویت دارند.',
    'coreManagedIntro':
        'پروتکل، درگاه‌های پراکسی و مسیر ابزارهای همراه توسط برنامه مدیریت می‌شوند. SO_MARK به روت نیاز دارد و فایل‌ها باید برای برنامه قابل دسترسی باشند.',
    'coreSensitiveWarning':
        'آرگومان‌ها و متغیرهای محیطی ممکن است اطلاعات حساس داشته باشند.',
    'additionalArguments': 'آرگومان‌های اضافی (آرایهٔ JSON)',
    'environmentJson': 'محیط (شیء JSON)',
    'startupTimeout': 'مهلت راه‌اندازی پیشرفته (ثانیه)',
    'startupTimeoutHelp':
        '۳۰ تا ۳۶۰۰؛ هنگام تنظیم کشور یا گزینه‌های اضافی استفاده می‌شود.',
    'resetFields': 'بازنشانی فیلدها به پیش‌فرض',
    'featureExamples': 'نمونه قابلیت‌ها',
    'bundledCoreHelp': 'راهنمای کامل هستهٔ همراه',
    'autoTrySeconds': 'تلاش خودکار (ثانیه)',
    'reconnectAether': 'اتصال دوبارهٔ ایثر',
    'autoFastestRoute': 'خودکار - سریع‌ترین مسیر',
    'resetOrderAndConnect': 'بازنشانی ترتیب و اتصال',
    'tapToChooseOrDrag': 'برای انتخاب بزنید یا برای جابه‌جایی بکشید',
    'quickSettings': 'تنظیمات سریع',
    'autoConnectStartup': 'اتصال خودکار هنگام شروع',
    'killSwitch': 'کلید قطع اضطراری',
    'killSwitchSubtitle':
        '«وی‌پی‌ان همیشه‌روشن» و «مسدودسازی اتصال بدون وی‌پی‌ان» را روشن کنید',
    'backgroundRunningSubtitle':
        'راهنمای گام‌به‌گام گوشی شما برای روشن ماندن وی‌پی‌ان هنگام خاموش بودن صفحه',
    'connectionSteps': 'مراحل اتصال',
    'clear': 'پاک کردن',
    'copyError': 'کپی خطا',
    'errorCopied': 'خطا کپی شد',
    'dismissError': 'بستن خطا',
    'psiphonServerCountry': 'کشور سرور سایفون',
    'serverSearch': 'جست‌وجوی سرور',
    'fast': 'سریع',
    'balanced': 'متعادل',
    'realDelayTest': 'آزمایش واقعی تأخیر',
    'realDelayTestSubtitle':
        'دسترسی اینترنت و تأخیر را می‌سنجد. هنگام خاموش بودن، فقط پراکسی محلی بررسی می‌شود.',
    'delayTestUrl': 'نشانی آزمایش تأخیر',
    'mode': 'حالت',
    'vpnAllApps': 'وی‌پی‌ان (همهٔ برنامه‌ها)',
    'proxyOnly': 'فقط پراکسی',
    'httpPort': 'درگاه HTTP',
    'socksPort': 'درگاه SOCKS5',
    'advanced': 'پیشرفته',
    'coreInput': 'ورودی هسته',
    'coreInputSubtitle': 'ارسال کد ورودی که هسته درخواست می‌کند',
    'proxyInfo': 'اطلاعات پراکسی',
    'checkForUpdates': 'بررسی به‌روزرسانی',
    'showActivityLog': 'نمایش گزارش فعالیت',
    'diagnostics': 'عیب‌یابی',
    'diagnosticsHelp':
        'گزارش‌ها تا زمانی که کپی نکنید روی همین دستگاه می‌مانند. گذرواژه‌ها و توکن‌های رایج سانسور می‌شوند.',
    'copyReport': 'کپی گزارش',
    'saveLocally': 'ذخیرهٔ محلی',
    'activity': 'فعالیت',
    'clearActivity': 'پاک کردن فعالیت',
    'waitingForLogs': 'در انتظار گزارش‌ها...',
  },
  'ar-IQ': {
    'appName': 'إيثر VPN',
    'language': 'اللغة',
    'english': 'الإنكليزية',
    'persian': 'الفارسية',
    'iraqiArabic': 'العربية العراقية',
    'connect': 'اتصال',
    'disconnect': 'قطع الاتصال',
    'settings': 'الإعدادات',
    'connection': 'الاتصال',
    'nextProtocol': 'البروتوكول التالي',
    'next': 'التالي',
    'connected': 'متصل',
    'connectingCancel': 'جاري الاتصال… اضغط للإلغاء',
    'cancel': 'إلغاء',
    'batteryGuideTitle': 'التشغيل بالخلفية',
    'stepsFor': 'الخطوات لجهاز {device}',
    'thisPhone': 'هذا التلفون',
    'batteryAlreadyOff': 'تحسين البطارية مطفّي لإيثر من قبل',
    'open': 'فتح',
    'settingOpenFailed': 'ما كدرنا نفتح هذا الخيار. دوّر على اسمه بالإعدادات.',
    'batteryGuideNote':
        'التطبيق يكدر يفحص بس تحسين البطارية؛ باقي الخطوات ما يگدر يكتشفها ولهذا تبقى ظاهرة. أسماء القوائم تختلف حسب الجهاز والإصدار. هالإعدادات تساعد، بس ممكن أندرويد أو الشركة تبقى توقف التطبيق بالخلفية.',
    'batteryOptimization': 'تحسين البطارية',
    'batteryOptimizationBody':
        'لكِ إيثر بالقائمة (اختار «كل التطبيقات» إذا احتجت) وخليه على «بدون تحسين».',
    'openBatteryOptimization': 'فتح تحسين البطارية',
    'appBatteryUsage': 'استخدام بطارية التطبيق',
    'appBatteryUsageBody':
        'افتح معلومات التطبيق > البطارية (أو «استخدام بطارية التطبيق») واختار «{mode}».',
    'openAppInfo': 'فتح معلومات التطبيق',
    'neverSleepingApps': 'تطبيقات ما تدخل بالنوم',
    'samsungBatteryBody':
        'الإعدادات > البطارية > حدود الاستخدام بالخلفية: شيل إيثر من التطبيقات النائمة والعميقة، طفّي تنويم التطبيقات غير المستخدمة، وضيف إيثر إلى التطبيقات اللي ما تنام.',
    'openSamsungBattery': 'فتح بطارية سامسونگ',
    'autostart': 'تشغيل تلقائي',
    'autostartBody': 'فعّل التشغيل التلقائي لإيثر.',
    'openAutostart': 'فتح التشغيل التلقائي',
    'batterySaver': 'توفير البطارية',
    'xiaomiBatteryBody':
        'من معلومات التطبيق > توفير البطارية اختار «بدون قيود». وبالتطبيقات الأخيرة اضغط مطوّل على بطاقة إيثر واضغط علامة القفل.',
    'appLaunch': 'تشغيل التطبيق',
    'huaweiLaunchBody':
        'الإعدادات > التطبيقات > تشغيل التطبيق: خلي إيثر على «إدارة يدوية» وفعّل التشغيل التلقائي والثانوي والعمل بالخلفية.',
    'openAppLaunch': 'فتح تشغيل التطبيق',
    'autoLaunch': 'تشغيل تلقائي',
    'oppoLaunchBody': 'اسمح لإيثر يشتغل تلقائياً من إعدادات التطبيقات.',
    'openAutoLaunch': 'فتح التشغيل التلقائي',
    'backgroundActivity': 'النشاط بالخلفية',
    'oppoBackgroundBody':
        'من معلومات التطبيق > استخدام البطارية فعّل «السماح بالنشاط بالخلفية»، وإذا موجود ثبّت إيثر بالتطبيقات الأخيرة.',
    'vivoBackgroundBody':
        'من الإعدادات > البطارية > إدارة استهلاك الطاقة بالخلفية، اسمح لإيثر يستخدم الطاقة بالخلفية.',
    'autoOrder': 'الترتيب التلقائي',
    'reset': 'إعادة ضبط',
    'save': 'حفظ',
    'autoOrderEmpty': 'اختار بروتوكول واحد على الأقل للوضع التلقائي.',
    'autoOrderHelp':
        'الوضع التلقائي يجرّب البروتوكولات المختارة من الأعلى. الناجحة تصعد حسب نسبة النجاح والسرعة، والفاشلة تنزل. اسحب المقبض حتى تغيّر الترتيب.',
    'worksForYou': 'يشتغل عندك',
    'oftenFails': 'غالباً يفشل',
    'tooFewTries': 'تجارب قليلة',
    'notTriedYet': 'بعده ما متجرّب',
    'okCount': '{count} ناجح',
    'failedCount': '{count} فاشل',
    'successRate': 'نجاح {rate}٪',
    'averageSeconds': 'المعدل {seconds} ث',
    'lastOk': 'آخر نجاح {ago}',
    'justNow': 'هسه',
    'minutesAgo': 'قبل {count} دقيقة',
    'hoursAgo': 'قبل {count} ساعة',
    'daysAgo': 'قبل {count} يوم',
    'protocolOrder': 'ترتيب البروتوكولات',
    'done': 'تم',
    'autoOrderInSettings': 'تلقائي (الترتيب بالإعدادات)',
    'coreSettings': 'إعدادات النواة',
    'loadingCoreHelp': 'جاري تحميل دليل النواة…',
    'coreHelpFailed': 'ما كدرنا نقرا دليل النواة المرفق.',
    'saveSettingsFailed': 'ما كدرنا نحفظ الإعدادات.',
    'coreExpertIntro':
        'الخيارات المتقدمة تنطبق على كل البروتوكولات المختارة. اختار بروتوكول يدوي للخيارات الخاصة. الأعلام تتقدم على متغيرات البيئة.',
    'coreManagedIntro':
        'البروتوكول ومنافذ البروكسي ومسارات الأدوات يديرها التطبيق. SO_MARK يحتاج روت، والملفات لازم تكون متاحة للتطبيق.',
    'coreSensitiveWarning':
        'المعاملات ومتغيرات البيئة ممكن تحتوي معلومات حساسة.',
    'additionalArguments': 'معاملات إضافية (مصفوفة JSON)',
    'environmentJson': 'البيئة (كائن JSON)',
    'startupTimeout': 'مهلة التشغيل المتقدمة (ثانية)',
    'startupTimeoutHelp':
        'من 30 إلى 3600؛ تستخدم عند ضبط بلد أو خيارات إضافية.',
    'resetFields': 'رجّع الحقول للوضع الافتراضي',
    'featureExamples': 'أمثلة للميزات',
    'bundledCoreHelp': 'الدليل الكامل للنواة المرفقة',
    'autoTrySeconds': 'محاولة تلقائية (ثانية)',
    'reconnectAether': 'إعادة اتصال إيثر',
    'autoFastestRoute': 'تلقائي - أسرع مسار',
    'resetOrderAndConnect': 'إعادة ضبط الترتيب والاتصال',
    'tapToChooseOrDrag': 'اضغط للاختيار أو اسحب لتغيير الترتيب',
    'quickSettings': 'إعدادات سريعة',
    'autoConnectStartup': 'اتصال تلقائي عند التشغيل',
    'killSwitch': 'مفتاح الإيقاف',
    'killSwitchSubtitle': 'فعّل «VPN دائم التشغيل» و«حظر الاتصالات بدون VPN»',
    'backgroundRunningSubtitle':
        'خطوات جهازك حتى يبقى الـVPN شغّال من تنطفي الشاشة',
    'connectionSteps': 'خطوات الاتصال',
    'clear': 'مسح',
    'copyError': 'نسخ الخطأ',
    'errorCopied': 'تم نسخ الخطأ',
    'dismissError': 'إخفاء الخطأ',
    'psiphonServerCountry': 'بلد سيرفر سايفون',
    'serverSearch': 'البحث عن السيرفر',
    'fast': 'سريع',
    'balanced': 'متوازن',
    'realDelayTest': 'فحص التأخير الحقيقي',
    'realDelayTestSubtitle':
        'يتأكد من الإنترنت ويقيس التأخير. إذا مطفّي، يفحص بس البروكسي المحلي.',
    'delayTestUrl': 'رابط فحص التأخير',
    'mode': 'الوضع',
    'vpnAllApps': 'VPN (كل التطبيقات)',
    'proxyOnly': 'بروكسي فقط',
    'httpPort': 'منفذ HTTP',
    'socksPort': 'منفذ SOCKS5',
    'advanced': 'متقدم',
    'coreInput': 'إدخال النواة',
    'coreInputSubtitle': 'إرسال كود تسجيل الدخول اللي تطلبه النواة',
    'proxyInfo': 'معلومات البروكسي',
    'checkForUpdates': 'التحقق من التحديثات',
    'showActivityLog': 'إظهار سجل النشاط',
    'diagnostics': 'التشخيص',
    'diagnosticsHelp':
        'التقارير تبقى على جهازك إلا إذا نسختها. كلمات السر والتوكنات الشائعة تنحذف تلقائياً.',
    'copyReport': 'نسخ التقرير',
    'saveLocally': 'حفظ محلياً',
    'activity': 'النشاط',
    'clearActivity': 'مسح النشاط',
    'waitingForLogs': 'بانتظار السجلات...',
  },
};

class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    super.key,
    required LocaleController controller,
    required super.child,
  }) : super(notifier: controller);
  static LocaleController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocaleScope>()?.notifier;
  static LocaleController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'No LocaleScope found in context');
    return controller!;
  }
}

extension AppLocalizationContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  LocaleController get localeController => LocaleScope.of(this);
}

class LocalizedApp extends StatelessWidget {
  final LocaleController controller;
  final ThemeData theme;
  final Widget home;
  const LocalizedApp({
    super.key,
    required this.controller,
    required this.theme,
    required this.home,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => LocaleScope(
      controller: controller,
      child: MaterialApp(
        onGenerateTitle: (context) => context.l10n.appName,
        debugShowCheckedModeBanner: false,
        theme: theme,
        locale: controller.locale,
        supportedLocales: AppLocales.supported,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          _FallbackMaterialLocalizationsDelegate(),
          _FallbackWidgetsLocalizationsDelegate(),
          _FallbackCupertinoLocalizationsDelegate(),
        ],
        builder: (context, child) => Directionality(
          textDirection: controller.textDirection,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.3),
            ),
            child: child!,
          ),
        ),
        home: home,
      ),
    ),
  );
}

LocaleStore defaultLocaleStore(String appDirectory) =>
    LocaleStore(File('$appDirectory/locale.txt'));
