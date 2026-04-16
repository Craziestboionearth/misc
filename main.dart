import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'boot_splash_wrapper.dart';
import 'home_screen.dart';
import 'settings_page.dart';
import 'dart:convert';
import 'native_theme_sync.dart';
import 'premium_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'paywall_helper.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'auth_service.dart';
import 'device_service.dart';
import 'purchase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'admin_telemetry_service.dart';

// design-constants (Colors)
const kLightCard = kLightSurfaceAlt;
const kDarkCard = kDarkSurfaceAlt;

const kBrandAccent = Color(0xFF4F8FDE);
const kBrandAccentStrong = Color(0xFF2F6FBE);
const kBrandAccentSoft = Color(0xFFEAF2FF);

const kLightBackground = Color(0xFFF7F9FC);
const kLightSurface = Colors.white;
const kLightSurfaceAlt = Color(0xFFF1F5FB);
const kLightBorder = Color(0xFFD7E1EE);
const kLightText = Color(0xFF18212B);
const kLightMutedText = Color(0xFF5F6E7E);

const kDarkBackground = Color(0xFF0F141A);
const kDarkSurface = Color(0xFF161D26);
const kDarkSurfaceAlt = Color(0xFF1B2430);
const kDarkBorder = Color(0xFF2A3644);
const kDarkText = Color(0xFFF3F7FC);
const kDarkMutedText = Color(0xFF9AA9BA);
const kDarkAccent = Color(0xFF78AEEF);
const kDarkAccentSoft = Color(0xFF1E324A);

const kAccentPrimary = Color(0xFF4F8FDE);
const kAccentPrimaryStrong = Color(0xFF2F6FBE);
const kAccentPrimarySoft = Color(0xFFEAF2FF);

const kAccentViolet = Color(0xFF7C3AED);
const kAccentOrange = Color(0xFFDD6B20);
const kAccentTeal = Color(0xFF0F9D7A);
const kAccentBlue = Color(0xFF3182CE);

const kAccentSuccess = Color(0xFF2E8B57);
const kAccentWarning = Color(0xFFD97706);
const kAccentDanger = Color(0xFFC2410C);
const kAccentError = Color(0xFFDC2626);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  unawaited(AdminTelemetryService.trackEvent(
    'app_open',
    meta: {
      'source': 'main',
    },
  ));

  await PurchaseService().init();

  await PremiumService().load();

  final settings = AppSettings();
  await settings.load();

  final authService = AuthService();
  final deviceService = DeviceService();
  if (authService.isLoggedIn) deviceService.touchCurrentDevice();

  await NativeThemeSync.setThemeMode(
    settings.isDarkMode ? NativeThemeMode.dark : NativeThemeMode.light,
  );

  runApp(AbiHelperRoot(settings: settings));
}

enum SubjectArea { sprachlichKreativ, gesellschaftlich, mint, sonstiges }

enum Bundesland {
  badenWuerttemberg,
  bayern,
  berlin,
  brandenburg,
  bremen,
  hamburg,
  hessen,
  mecklenburgVorpommern,
  niedersachsen,
  nordrheinWestfalen,
  rheinlandPfalz,
  saarland,
  sachsen,
  sachsenAnhalt,
  schleswigHolstein,
  thueringen,
}

Bundesland? bundeslandFromCode(String code) {
  switch (code) {
    case 'bw':
      return Bundesland.badenWuerttemberg;
    case 'by':
      return Bundesland.bayern;
    case 'be':
      return Bundesland.berlin;
    case 'bb':
      return Bundesland.brandenburg;
    case 'hb':
      return Bundesland.bremen;
    case 'hh':
      return Bundesland.hamburg;
    case 'he':
      return Bundesland.hessen;
    case 'mv':
      return Bundesland.mecklenburgVorpommern;
    case 'ni':
      return Bundesland.niedersachsen;
    case 'nw':
      return Bundesland.nordrheinWestfalen;
    case 'rp':
      return Bundesland.rheinlandPfalz;
    case 'sl':
      return Bundesland.saarland;
    case 'sn':
      return Bundesland.sachsen;
    case 'st':
      return Bundesland.sachsenAnhalt;
    case 'sh':
      return Bundesland.schleswigHolstein;
    case 'th':
      return Bundesland.thueringen;
    default:
      return null;
  }
}


class AppSettings extends ChangeNotifier {
  bool isDarkMode = false;
  Bundesland? selectedBundesland;
  int defaultLessonDurationMinutes = 60;

  List<SavedAbiCombination> savedCombinations = [];
  List<String> lastOfferedSubjectNames = [];

  DateTime? lastSuccessfulSyncAt;
  DateTime? lastLocalSettingsChangeAt;
  DateTime? lastLocalAbiChangeAt;
  DateTime? lastLocalCalendarChangeAt;

  bool get hasLocalCalendarChangesSinceLastSync =>
      lastLocalCalendarChangeAt != null &&
          (lastSuccessfulSyncAt == null ||
              lastLocalCalendarChangeAt!.isAfter(lastSuccessfulSyncAt!));

  void markCalendarChanged() {
    if (_suspendChangeTracking) return;
    lastLocalCalendarChangeAt = DateTime.now();
  }

  DateTime? get latestLocalChangeAt {
    final values = [
      lastLocalSettingsChangeAt,
      lastLocalAbiChangeAt,
      lastLocalCalendarChangeAt,
    ].whereType<DateTime>().toList();

    if (values.isEmpty) return null;
    values.sort();
    return values.last;
  }

  bool _suspendChangeTracking = false;

  bool get hasLocalSettingsChangesSinceLastSync =>
      lastLocalSettingsChangeAt != null &&
          (lastSuccessfulSyncAt == null ||
              lastLocalSettingsChangeAt!.isAfter(lastSuccessfulSyncAt!));

  bool get hasLocalAbiChangesSinceLastSync =>
      lastLocalAbiChangeAt != null &&
          (lastSuccessfulSyncAt == null ||
              lastLocalAbiChangeAt!.isAfter(lastSuccessfulSyncAt!));

  bool get hasAnyLocalChangesSinceLastSync =>
      hasLocalSettingsChangesSinceLastSync || hasLocalAbiChangesSinceLastSync;

  void _markSettingsChanged() {
    if (_suspendChangeTracking) return;
    lastLocalSettingsChangeAt = DateTime.now();
  }

  void _markAbiChanged() {
    if (_suspendChangeTracking) return;
    lastLocalAbiChangeAt = DateTime.now();
  }

  Future<void> markSyncSuccessful() async {
    lastSuccessfulSyncAt = DateTime.now();
    await _save();
  }

  Future<void> runWithoutTracking(Future<void> Function() action) async {
    _suspendChangeTracking = true;
    try {
      await action();
    } finally {
      _suspendChangeTracking = false;
    }
  }

  Future<void> saveAbiCombination(SavedAbiCombination combination) async {
    final index = savedCombinations.indexWhere((e) => e.id == combination.id);
    if (index >= 0) {
      savedCombinations[index] = combination;
    } else {
      savedCombinations.add(combination);
    }
    _markSettingsChanged();
    await _save();
    notifyListeners();
  }

  Future<void> deleteAbiCombination(String id) async {
    savedCombinations.removeWhere((e) => e.id == id);
    _markSettingsChanged();
    await _save();
    notifyListeners();
  }

  Future<void> setLastOfferedSubjectNames(List<String> names) async {
    lastOfferedSubjectNames = List<String>.from(names);
    _markSettingsChanged();
    await _save();
    notifyListeners();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isDarkMode = prefs.getBool('isDarkMode') ?? false;
    final bundeslandCode = prefs.getString('selectedBundesland');
    if (bundeslandCode != null && bundeslandCode.isNotEmpty) {
      selectedBundesland = _bundeslandFromCode(bundeslandCode);
    }
    defaultLessonDurationMinutes =
        prefs.getInt('defaultLessonDurationMinutes') ?? 60;

    final lastSyncRaw = prefs.getString('lastSuccessfulSyncAt');
    if (lastSyncRaw != null && lastSyncRaw.isNotEmpty) {
      lastSuccessfulSyncAt = DateTime.tryParse(lastSyncRaw);
    }

    final lastSettingsRaw = prefs.getString('lastLocalSettingsChangeAt');
    if (lastSettingsRaw != null && lastSettingsRaw.isNotEmpty) {
      lastLocalSettingsChangeAt = DateTime.tryParse(lastSettingsRaw);
    }

    final lastAbiRaw = prefs.getString('lastLocalAbiChangeAt');
    if (lastAbiRaw != null && lastAbiRaw.isNotEmpty) {
      lastLocalAbiChangeAt = DateTime.tryParse(lastAbiRaw);
    }

    final lastCalendarRaw = prefs.getString('lastLocalCalendarChangeAt');
    if (lastCalendarRaw != null && lastCalendarRaw.isNotEmpty) {
      lastLocalCalendarChangeAt = DateTime.tryParse(lastCalendarRaw);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDarkMode);
    await prefs.setString(
      'selectedBundesland',
      selectedBundesland != null
          ? getBundeslandCode(selectedBundesland!)
          : '',
    );
    await prefs.setInt(
      'defaultLessonDurationMinutes',
      defaultLessonDurationMinutes,
    );

    await prefs.setString(
      'lastSuccessfulSyncAt',
      lastSuccessfulSyncAt?.toIso8601String() ?? '',
    );
    await prefs.setString(
      'lastLocalSettingsChangeAt',
      lastLocalSettingsChangeAt?.toIso8601String() ?? '',
    );
    await prefs.setString(
      'lastLocalAbiChangeAt',
      lastLocalAbiChangeAt?.toIso8601String() ?? '',
    );
    await prefs.setString(
      'lastLocalCalendarChangeAt',
      lastLocalCalendarChangeAt?.toIso8601String() ?? '',
    );
  }

  Future<void> save() async {
    await _save();
  }

  Future<void> toggleDarkMode() async {
    isDarkMode = !isDarkMode;
    await NativeThemeSync.setThemeMode(
      isDarkMode ? NativeThemeMode.dark : NativeThemeMode.light,
    );
    _markSettingsChanged();
    await _save();
    notifyListeners();
  }

  Future<void> setBundesland(Bundesland land) async {
    selectedBundesland = land;
    _markSettingsChanged();
    await _save();
    notifyListeners();
  }

  Future<void> setLessonDuration(int minutes) async {
    defaultLessonDurationMinutes = minutes;
    _markSettingsChanged();
    await _save();
    notifyListeners();
  }

  Bundesland? _bundeslandFromCode(String code) {
    switch (code) {
      case 'bw':
        return Bundesland.badenWuerttemberg;
      case 'by':
        return Bundesland.bayern;
      case 'be':
        return Bundesland.berlin;
      case 'bb':
        return Bundesland.brandenburg;
      case 'hb':
        return Bundesland.bremen;
      case 'hh':
        return Bundesland.hamburg;
      case 'he':
        return Bundesland.hessen;
      case 'mv':
        return Bundesland.mecklenburgVorpommern;
      case 'ni':
        return Bundesland.niedersachsen;
      case 'nw':
        return Bundesland.nordrheinWestfalen;
      case 'rp':
        return Bundesland.rheinlandPfalz;
      case 'sl':
        return Bundesland.saarland;
      case 'sn':
        return Bundesland.sachsen;
      case 'st':
        return Bundesland.sachsenAnhalt;
      case 'sh':
        return Bundesland.schleswigHolstein;
      case 'th':
        return Bundesland.thueringen;
      default:
        return null;
    }
  }
}

String getBundeslandName(Bundesland land) => switch (land) {
      Bundesland.badenWuerttemberg => 'Baden-Württemberg',
      Bundesland.bayern => 'Bayern',
      Bundesland.berlin => 'Berlin',
      Bundesland.brandenburg => 'Brandenburg',
      Bundesland.bremen => 'Bremen',
      Bundesland.hamburg => 'Hamburg',
      Bundesland.hessen => 'Hessen',
      Bundesland.mecklenburgVorpommern => 'Mecklenburg-Vorpommern',
      Bundesland.niedersachsen => 'Niedersachsen',
      Bundesland.nordrheinWestfalen => 'Nordrhein-Westfalen',
      Bundesland.rheinlandPfalz => 'Rheinland-Pfalz',
      Bundesland.saarland => 'Saarland',
      Bundesland.sachsen => 'Sachsen',
      Bundesland.sachsenAnhalt => 'Sachsen-Anhalt',
      Bundesland.schleswigHolstein => 'Schleswig-Holstein',
      Bundesland.thueringen => 'Thüringen',
    };

String getBundeslandCode(Bundesland land) => switch (land) {
      Bundesland.badenWuerttemberg => 'bw',
      Bundesland.bayern => 'by',
      Bundesland.berlin => 'be',
      Bundesland.brandenburg => 'bb',
      Bundesland.bremen => 'hb',
      Bundesland.hamburg => 'hh',
      Bundesland.hessen => 'he',
      Bundesland.mecklenburgVorpommern => 'mv',
      Bundesland.niedersachsen => 'ni',
      Bundesland.nordrheinWestfalen => 'nw',
      Bundesland.rheinlandPfalz => 'rp',
      Bundesland.saarland => 'sl',
      Bundesland.sachsen => 'sn',
      Bundesland.sachsenAnhalt => 'st',
      Bundesland.schleswigHolstein => 'sh',
      Bundesland.thueringen => 'th',
    };

ThemeData _buildTheme({required bool dark}) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: dark ? kDarkBackground : kLightBackground,
    colorScheme: ColorScheme.fromSeed(
      brightness: dark ? Brightness.dark : Brightness.light,
      seedColor: kBrandAccent,
      primary: kBrandAccent,
      surface: dark ? kDarkSurface : kLightSurface,
      background: dark ? kDarkBackground : kLightBackground,
    ),
  );

  final textColor = dark ? Colors.white : Colors.black87;
  final mutedColor = dark ? kDarkMutedText : kLightMutedText;
  final cardColor = dark ? kDarkCard : kLightCard;
  final borderColor = dark ? kDarkBorder : kLightBorder;

  return base.copyWith(
    primaryColor: kBrandAccent,
    textTheme: base.textTheme.copyWith(
      titleLarge: TextStyle(
        color: textColor,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: textColor,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: textColor,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: TextStyle(
        color: mutedColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      bodySmall: TextStyle(
        color: mutedColor,
        fontSize: 12,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: textColor,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: dark
          ? const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      )
          : const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: dark ? 0 : 1,
      margin: EdgeInsets.zero,
      shadowColor: dark ? Colors.black26 : Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: borderColor, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF242933) : Colors.white,
      labelStyle: TextStyle(color: mutedColor),
      hintStyle: TextStyle(color: mutedColor.withOpacity(0.9)),
      prefixIconColor: mutedColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        borderSide: BorderSide(color: kBrandAccent, width: 1.4),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: borderColor),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      elevation: 2,
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: borderColor),
      ),
      side: BorderSide(color: borderColor),
      backgroundColor: cardColor,
      selectedColor: kBrandAccent.withOpacity(dark ? 0.22 : 0.28),
      labelStyle: TextStyle(color: textColor, fontWeight: FontWeight.w600),
      secondaryLabelStyle:
          const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    dividerColor: borderColor,
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? kBrandAccent
            : (dark ? Colors.white70 : Colors.white),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? kBrandAccent.withOpacity(0.45)
            : (dark ? Colors.white24 : Colors.black12),
      ),
    ),
  );
}

class AbiHelperRoot extends StatefulWidget {
  final AppSettings settings;
  const AbiHelperRoot({super.key, required this.settings});

  @override
  State<AbiHelperRoot> createState() => _AbiHelperRootState();
}

class _AbiHelperRootState extends State<AbiHelperRoot> {
  final _authService = AuthService();
  final _appLinks = AppLinks();
  final _deviceService = DeviceService();

  StreamSubscription<Uri>? _linkSub;
  late final StreamSubscription<AuthState> _authSub;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_onSettingsChanged);
    _setupDeepLinks();
    _setupAuthSync();
    _cleanupInactiveDevicesOnStart();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (authService.isLoggedIn) {
        try {
          await deviceService.registerCurrentDevice();  // Creates device on startup
          print('✅ Device registered on app start');
        } catch (e) {
          print('Device registration failed: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    _linkSub?.cancel();
    widget.settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _setupAuthSync() {
    final supabase = Supabase.instance.client;

    _authSub = supabase.auth.onAuthStateChange.listen((data) async {
      final event = data.event;

      if (event == AuthChangeEvent.initialSession ||
          event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.tokenRefreshed ||
          event == AuthChangeEvent.userUpdated) {
        await PurchaseService().logInCurrentUser();
        await PremiumService().load();
        if (mounted) setState(() {});
      }

      if (event == AuthChangeEvent.signedOut) {
        await PurchaseService().logInCurrentUser();
        await PremiumService().setPremiumLocalOnly(false);
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _setupDeepLinks() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        await _handleIncomingLink(initialUri);
      }
    } catch (_) {}

    _linkSub = _appLinks.uriLinkStream.listen((uri) async {
      await _handleIncomingLink(uri);
    });
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    final uriString = uri.toString();

    final isAuthLink =
        uriString.contains('access_token=') ||
            uriString.contains('refresh_token=') ||
            uriString.contains('type=recovery') ||
            uriString.contains('type=signup') ||
            uriString.contains('type=magiclink');

    if (!isAuthLink) return;

    try {
      await _authService.handleDeepLink(uri);
      await PurchaseService().logInCurrentUser();
      await PremiumService().load();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Authentifizierung erfolgreich!'),
        ),
      );

      setState(() {});
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler beim Authentifizieren. Bitte wende dich bei Bedarf an unseren Support. Fehler: $e'),
        ),
      );
    }
  }

  void _onSettingsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _cleanupInactiveDevicesOnStart() async {
    try {
      if (!_authService.isLoggedIn) return;
      await _deviceService.deleteInactiveDevices();
    } catch (e) {
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.settings.isDarkMode;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      )
          : const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: MaterialApp(
        title: 'AbiWizard',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(dark: false),
        darkTheme: _buildTheme(dark: true),
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        home: BootSplashWrapper(settings: widget.settings),
      ),
    );
  }
}

class SavedAbiCombination {
  final String id;
  final String name;
  final String bundeslandCode;
  final List<String> offeredSubjectNames;
  final String? lk1Name;
  final String? lk2Name;
  final String? schriftlich3Name;
  final String? muendlichName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  SavedAbiCombination({
    required this.id,
    required this.name,
    required this.bundeslandCode,
    required this.offeredSubjectNames,
    this.lk1Name,
    this.lk2Name,
    this.schriftlich3Name,
    this.muendlichName,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bundeslandCode': bundeslandCode,
    'offeredSubjectNames': offeredSubjectNames,
    'lk1Name': lk1Name,
    'lk2Name': lk2Name,
    'schriftlich3Name': schriftlich3Name,
    'muendlichName': muendlichName,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory SavedAbiCombination.fromJson(Map<String, dynamic> json) {
    return SavedAbiCombination(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? json['title'] ?? '').toString(),
      bundeslandCode:
      (json['bundeslandCode'] ?? json['bundesland'] ?? '').toString(),
      offeredSubjectNames: (json['offeredSubjectNames'] as List?)
          ?.map((e) => e.toString())
          .toList() ??
          <String>[],
      lk1Name: json['lk1Name']?.toString(),
      lk2Name: json['lk2Name']?.toString(),
      schriftlich3Name: json['schriftlich3Name']?.toString(),
      muendlichName: json['muendlichName']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }
}

class Subject {
  final String name;
  final SubjectArea area;
  final bool isAlwaysActive;
  final bool isLanguageOrGerman;
  final bool isLK1Eligible;
  final bool isSpecialReligion;
  final String bundesland;

  Subject({
    required this.name,
    required this.area,
    required this.bundesland,
    this.isAlwaysActive = false,
    this.isLanguageOrGerman = false,
    this.isLK1Eligible = false,
    this.isSpecialReligion = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Subject &&
              name == other.name &&
              area == other.area &&
              bundesland == other.bundesland;

  @override
  int get hashCode => name.hashCode ^ area.hashCode ^ bundesland.hashCode;
}

// ===============MAIN================

class AbiCombinationOverviewPage extends StatelessWidget {
  final AppSettings settings;
  const AbiCombinationOverviewPage({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final combinations = settings.savedCombinations;
    return Scaffold(
      appBar: AppBar(title: const Text('Abi-Kombinationen')),
      body: combinations.isEmpty
          ? const Center(child: Text('Noch keine Kombinationen gespeichert.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: combinations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final combo = combinations[index];
                final land = bundeslandFromCode(combo.bundeslandCode);
                return Card(
                  child: ListTile(
                    title: Text(combo.name),
                    subtitle: Text(land != null ? getBundeslandName(land) : combo.bundeslandCode),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Konfiguration löschen?'),
                            content: Text(
                              '„${combo.name}“ wird dauerhaft gelöscht. Diese Aktion ist unwiderruflich.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext, false),
                                child: const Text('Abbrechen'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(dialogContext, true),
                                child: const Text('Endgültig löschen'),
                              ),
                            ],
                          ),
                        );

                        if (confirmed == true) {
                          await settings.deleteAbiCombination(combo.id);
                          (context as Element).markNeedsBuild();
                        }
                      },
                    ),
                    onTap: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AbiWizard(
                            settings: settings,
                            initialCombination: combo,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // is premium?
          final premiumService = PremiumService();

          if (!premiumService.isPremium &&
              settings.savedCombinations.length >= PremiumService.maxFreeLKKombis) {
            showPaywall(
              context,
              reason: 'Im kostenlosen Plan sind nur 2 Abi-Kombinationen möglich.',
              settings: settings,
            );
            return;
          }
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => AbiWizard(settings: settings)),
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Neue Kombination'),
      ),
    );
  }
}

class AbiWizard extends StatefulWidget {
  final AppSettings settings;
  final SavedAbiCombination? initialCombination;

  const AbiWizard({
    super.key,
    required this.settings,
    this.initialCombination,
  });

  @override
  State<AbiWizard> createState() => _AbiWizardState();
}

class _AbiWizardState extends State<AbiWizard> {
  final _authService = AuthService();
  final _deviceService = DeviceService();

  Subject? _findSubjectByName(String? name) {
    if (name == null || name
        .trim()
        .isEmpty) return null;
    final needle = name.trim().toLowerCase();

    for (final subject in alwaysActiveSubjects) {
      if (subject.name.trim().toLowerCase() == needle) {
        return subject;
      }
    }

    for (final subject in availableSubjects) {
      if (subject.name.trim().toLowerCase() == needle) {
        return subject;
      }
    }

    for (final subjects in bundeslandSubjects.values) {
      for (final subject in subjects) {
        if (subject.name.trim().toLowerCase() == needle) {
          return subject;
        }
      }
    }

    return null;
  }

  void _restoreOfferedSubjectsByName(List<String>? names) {
    offeredSubjects
      ..clear()
      ..addAll(alwaysActiveSubjects);

    if (names == null) return;

    for (final name in names) {
      final subject = _findSubjectByName(name);
      if (subject != null) {
        offeredSubjects.add(subject);
      }
    }
  }

  List<Subject> get coreSubjects {
    return availableSubjects.where((s) =>
    s.name == 'Deutsch' ||
        s.name == 'Mathematik' ||
        s.name == 'Englisch',
    ).toList();
  }

  int currentStep = 0;
  Bundesland? selectedBundesland;

  final Set<Subject> offeredSubjects = <Subject>{};
  Subject? lk1, lk2, schriftlich3, muendlich;

  late final List<Subject> alwaysActiveSubjects;

  bool get step0Complete => selectedBundesland != null;

  String _getBundeslandName(Bundesland land) =>
      switch (land) {
        Bundesland.badenWuerttemberg => 'Baden-Württemberg',
        Bundesland.bayern => 'Bayern',
        Bundesland.berlin => 'Berlin',
        Bundesland.brandenburg => 'Brandenburg',
        Bundesland.bremen => 'Bremen',
        Bundesland.hamburg => 'Hamburg',
        Bundesland.hessen => 'Hessen',
        Bundesland.mecklenburgVorpommern => 'Mecklenburg-Vorpommern',
        Bundesland.niedersachsen => 'Niedersachsen',
        Bundesland.nordrheinWestfalen => 'Nordrhein-Westfalen',
        Bundesland.rheinlandPfalz => 'Rheinland-Pfalz',
        Bundesland.saarland => 'Saarland',
        Bundesland.sachsen => 'Sachsen',
        Bundesland.sachsenAnhalt => 'Sachsen-Anhalt',
        Bundesland.schleswigHolstein => 'Schleswig-Holstein',
        Bundesland.thueringen => 'Thüringen',
      };

  String _getBundeslandInitial(Bundesland land) =>
      switch (land) {
        Bundesland.badenWuerttemberg => 'bw',
        Bundesland.bayern => 'by',
        Bundesland.berlin => 'be',
        Bundesland.brandenburg => 'bb',
        Bundesland.bremen => 'hb',
        Bundesland.hamburg => 'hh',
        Bundesland.hessen => 'he',
        Bundesland.mecklenburgVorpommern => 'mv',
        Bundesland.niedersachsen => 'ni',
        Bundesland.nordrheinWestfalen => 'nw',
        Bundesland.rheinlandPfalz => 'rp',
        Bundesland.saarland => 'sl',
        Bundesland.sachsen => 'sn',
        Bundesland.sachsenAnhalt => 'st',
        Bundesland.schleswigHolstein => 'sh',
        Bundesland.thueringen => 'th',
      };

  Color _getBundeslandColor(Bundesland land) =>
      switch (land) {
        Bundesland.badenWuerttemberg => Colors.purple,
        Bundesland.bayern => Colors.blue,
        Bundesland.berlin => Colors.red,
        Bundesland.brandenburg => Colors.orange,
        Bundesland.bremen => Colors.green,
        Bundesland.hamburg => Colors.teal,
        Bundesland.hessen => Colors.cyan,
        Bundesland.mecklenburgVorpommern => Colors.indigo,
        Bundesland.niedersachsen => Colors.amber,
        Bundesland.nordrheinWestfalen => Colors.deepPurple,
        Bundesland.rheinlandPfalz => Colors.brown,
        Bundesland.saarland => Colors.lime,
        Bundesland.sachsen => Colors.pink,
        Bundesland.sachsenAnhalt => Colors.lightBlue,
        Bundesland.schleswigHolstein => Colors.deepOrange,
        Bundesland.thueringen => Colors.lightGreen,
      };

  late final Map<Bundesland, List<Subject>> bundeslandSubjects;

  List<Subject> get availableSubjects {
    if (selectedBundesland == null) return [];
    return [
      ...alwaysActiveSubjects,
      ...?bundeslandSubjects[selectedBundesland],
    ];
  }

  @override
  void initState() {
    super.initState();

    Future<void> _cleanupInactiveDevicesOnStart() async {
      try {
        if (!_authService.isLoggedIn) return;
        await _deviceService.deleteInactiveDevices();
      } catch (e) {
        // Silent fail beim App-Start
      }
    }

    _cleanupInactiveDevicesOnStart();

    if (_authService.isLoggedIn) {
      _deviceService.touchCurrentDevice();
    }

    selectedBundesland = widget.initialCombination != null
        ? bundeslandFromCode(widget.initialCombination!.bundeslandCode)
        : widget.settings.selectedBundesland;

    alwaysActiveSubjects = [
      Subject(
        name: 'Mathematik',
        area: SubjectArea.mint,
        bundesland: '',
        isAlwaysActive: true,
        isLK1Eligible: true,
      ),
      Subject(
        name: 'Deutsch',
        area: SubjectArea.sprachlichKreativ,
        bundesland: '',
        isAlwaysActive: true,
        isLanguageOrGerman: true,
        isLK1Eligible: true,
      ),
      Subject(
        name: 'Englisch',
        area: SubjectArea.sprachlichKreativ,
        bundesland: '',
        isAlwaysActive: true,
        isLanguageOrGerman: true,
        isLK1Eligible: true,
      ),
    ];

    bundeslandSubjects = {
      // 1️⃣ BADEN-WÜRTTEMBERG
      Bundesland.badenWuerttemberg: [
        // AF1 Sprachlich-Kreativ (Deutsch/Fremdsprachen; Kunst/Musik/Theater bzw. Schauspiel)
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Latein',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Griechisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Russisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Italienisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Portugiesisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Chinesisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Japanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Türkisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        // AF1 Kreativ (zählt nicht für Abdeckung)
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW'),
        Subject(name: 'Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW'),
        Subject(name: 'Literatur',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW'),
        Subject(name: 'Theater',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BW'),
        // AF2 Gesellschaftlich
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BW'),
        Subject(name: 'Geographie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BW'),
        Subject(name: 'Gemeinschaftskunde',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BW'),
        Subject(name: 'Wirtschaft',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BW'),
        Subject(name: 'Philosophie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BW'),
        Subject(name: 'Psychologie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BW'),
        Subject(name: 'Religion/Ethik',
            area: SubjectArea.sonstiges,
            bundesland: 'BW',
            isSpecialReligion: true),
        // AF3 MINT
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'BW',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'BW',
            isLK1Eligible: true),
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'BW',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'BW'),
        Subject(name: 'NwT', area: SubjectArea.mint, bundesland: 'BW'),
      ],

      // 2️⃣ BAYERN
      Bundesland.bayern: [
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BY',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Italienisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BY',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Latein',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BY',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BY',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BY'),
        Subject(name: 'Bildende Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BY'),
        Subject(name: 'Darstellendes Spiel',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BY'),
        // AF2
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BY'),
        Subject(name: 'Geografie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BY'),
        Subject(name: 'Wirtschaftskunde',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BY'),
        Subject(name: 'Sozialkunde',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BY'),
        Subject(name: 'Religion/Ethik',
            area: SubjectArea.sonstiges,
            bundesland: 'BY',
            isSpecialReligion: true),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'BY',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'BY',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'BY',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'BY'),
      ],

      // 3️⃣ BERLIN
      Bundesland.berlin: [
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BE',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Italienisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BE',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BE',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Polnisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BE',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Russisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BE',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Türkisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BE',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Latein',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BE',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BE'),
        Subject(name: 'Bildende Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BE'),
        Subject(name: 'Darstellendes Spiel',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BE'),
        // AF2
        Subject(name: 'Politische Bildung',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BE'),
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BE'),
        Subject(name: 'Geografie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BE'),
        Subject(name: 'Philosophie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BE'),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'BE',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'BE',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'BE',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'BE'),
      ],

      // 4️⃣ BRANDENBURG
      Bundesland.brandenburg: [
        // AF1
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BB',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BB',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Russisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BB',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BB'),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BB'),
        Subject(name: 'Darstellendes Spiel',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'BB'),
        // AF2
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BB'),
        Subject(name: 'Politikwissenschaft',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BB'),
        Subject(name: 'Geografie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BB'),
        Subject(name: 'Ethik',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BB'),
        Subject(name: 'Philosophie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BB'),
        Subject(name: 'Psychologie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BB'),
        Subject(name: 'Wirtschaftswissenschaften',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'BB'),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'BB',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'BB',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'BB',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'BB'),
        // Sonstiges
        Subject(name: 'Sport', area: SubjectArea.sonstiges, bundesland: 'BB'),
      ],

      // 5️⃣ BREMEN
      Bundesland.bremen: [
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HB',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HB',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Latein',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HB',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Griechisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HB',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HB'),
        Subject(name: 'Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HB'),
        // AF2
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HB'),
        Subject(name: 'Politik-Wirtschaft',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HB'),
        Subject(name: 'Geographie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HB'),
        Subject(name: 'Philosophie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HB'),
        Subject(name: 'Religion',
            area: SubjectArea.sonstiges,
            bundesland: 'HB',
            isSpecialReligion: true),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'HB',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'HB',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'HB',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'HB'),
        Subject(name: 'Sport', area: SubjectArea.sonstiges, bundesland: 'HB'),
      ],

      // 6️⃣ HAMBURG
      Bundesland.hamburg: [
        Subject(name: 'Arabisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HH',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Chinesisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HH',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HH',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HH',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Italienisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HH',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Bildende Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HH'),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HH'),
        Subject(name: 'Theater',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HH'),
        // AF2
        Subject(name: 'Politik/Gesellschaft/Wirtschaft',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HH'),
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HH'),
        Subject(name: 'Geografie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HH'),
        Subject(name: 'Philosophie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HH'),
        Subject(name: 'Psychologie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HH'),
        Subject(name: 'Religion',
            area: SubjectArea.sonstiges,
            bundesland: 'HH',
            isSpecialReligion: true),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'HH',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'HH',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'HH',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'HH'),
      ],

      // 7️⃣ HESSEN
      Bundesland.hessen: [
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HE',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Italienisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HE',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HE',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Russisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HE',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Latein',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HE',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Altgriechisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HE',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HE'),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'HE'),
        // AF2
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HE'),
        Subject(name: 'Politik und Wirtschaft',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HE'),
        Subject(name: 'Erdkunde',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HE'),
        Subject(name: 'Ethik',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HE'),
        Subject(name: 'Philosophie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'HE'),
        Subject(name: 'Religion',
            area: SubjectArea.sonstiges,
            bundesland: 'HE',
            isSpecialReligion: true),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'HE',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'HE',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'HE',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'HE'),
        Subject(name: 'Sport', area: SubjectArea.sonstiges, bundesland: 'HE'),
      ],

      // 8️⃣ MECKLENBURG-VORPOMMERN
      Bundesland.mecklenburgVorpommern: [
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'MV',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Polnisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'MV',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Russisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'MV',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Schwedisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'MV',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'MV',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Darstellendes Spiel',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'MV'),
        Subject(name: 'Kunst und Gestaltung',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'MV'),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'MV'),
        // AF2
        Subject(name: 'Geografie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'MV'),
        Subject(name: 'Geschichte und Politische Bildung',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'MV'),
        Subject(name: 'Philosophie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'MV'),
        Subject(name: 'Sozialkunde',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'MV'),
        Subject(name: 'Wirtschaft',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'MV'),
        Subject(name: 'Religion',
            area: SubjectArea.sonstiges,
            bundesland: 'MV',
            isSpecialReligion: true),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'MV',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'MV',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'MV',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'MV'),
        Subject(name: 'Sport', area: SubjectArea.sonstiges, bundesland: 'MV'),
      ],

      // 9️⃣ NIEDERSACHSEN
      Bundesland.niedersachsen: [
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NI',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Latein',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NI',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Griechisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NI',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NI'),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NI'),
        Subject(name: 'Darstellendes Spiel',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NI'),
        // AF2
        Subject(name: 'Politik',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'NI'),
        Subject(name: 'Wirtschaft',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'NI'),
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'NI'),
        Subject(name: 'Erdkunde',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'NI'),
        Subject(name: 'Rechtskunde',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'NI'),
        Subject(name: 'Philosophie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'NI'),
        Subject(name: 'Religion',
            area: SubjectArea.sonstiges,
            bundesland: 'NI',
            isSpecialReligion: true),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'NI',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'NI',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'NI',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'NI'),
        Subject(name: 'Sport', area: SubjectArea.sonstiges, bundesland: 'NI'),
      ],

      // 🔟 NORDRHEIN-WESTFALEN
      Bundesland.nordrheinWestfalen: [
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Italienisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Japanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Russisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Latein',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Chinesisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Türkisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Niederländisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NW',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NW'),
        Subject(name: 'Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'NW'),
        // AF2
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'NW'),
        Subject(name: 'Sozialwissenschaften',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'NW'),
        Subject(name: 'Geographie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'NW'),
        Subject(name: 'Philosophie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'NW'),
        Subject(name: 'Psychologie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'NW'),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'NW',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'NW',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'NW',
            isLK1Eligible: true),
        Subject(name: 'Informatik',
            area: SubjectArea.mint,
            bundesland: 'NW',
            isLK1Eligible: true),
        // Sonstiges
        Subject(name: 'Religion/Ethik',
            area: SubjectArea.sonstiges,
            bundesland: 'NW',
            isSpecialReligion: true),
        Subject(name: 'Sport', area: SubjectArea.sonstiges, bundesland: 'NW'),
      ],

      // 1️⃣1️⃣ RHEINLAND-PFALZ
      Bundesland.rheinlandPfalz: [
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'RP',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Latein',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'RP',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Griechisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'RP',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Russisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'RP',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'RP',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Italienisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'RP',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Japanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'RP',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Bildende Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'RP'),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'RP'),
        // AF2
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'RP'),
        Subject(name: 'Erdkunde',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'RP'),
        Subject(name: 'Sozialkunde',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'RP'),
        Subject(name: 'Religion',
            area: SubjectArea.sonstiges,
            bundesland: 'RP',
            isSpecialReligion: true),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'RP',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'RP',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'RP',
            isLK1Eligible: true),
        Subject(name: 'Informatik',
            area: SubjectArea.mint,
            bundesland: 'RP'),
        Subject(name: 'Naturwissenschaften',
            area: SubjectArea.mint,
            bundesland: 'RP',
            isLK1Eligible: true),
        Subject(name: 'Sport', area: SubjectArea.sonstiges, bundesland: 'RP'),
      ],

      // 1️⃣2️⃣ SAARLAND
      Bundesland.saarland: [
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SL',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SL',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Bildende Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SL'),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SL'),
        Subject(name: 'Darstellendes Spiel',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SL'),
        // AF2
        Subject(name: 'Erdkunde',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'SL'),
        Subject(name: 'Politik',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'SL'),
        Subject(name: 'Wirtschaftslehre',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'SL'),
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'SL'),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'SL',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'SL',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'SL',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'SL'),
        Subject(name: 'Sport', area: SubjectArea.sonstiges, bundesland: 'SL'),
        Subject(name: 'Religion',
            area: SubjectArea.sonstiges,
            bundesland: 'SL',
            isSpecialReligion: true),
      ],

      // 1️⃣3️⃣ SACHSEN
      Bundesland.sachsen: [
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SN',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Latein',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SN',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Russisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SN',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SN',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SN'),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SN'),
        // AF2
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'SN'),
        Subject(name: 'Geografie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'SN'),
        Subject(name: 'Sozialkunde/Wirtschaft',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'SN'),
        Subject(name: 'Ethik/Religion',
            area: SubjectArea.sonstiges,
            bundesland: 'SN',
            isSpecialReligion: true),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'SN',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'SN',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'SN',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'SN'),
        Subject(name: 'Sport', area: SubjectArea.sonstiges, bundesland: 'SN'),
      ],

      // 1️⃣4️⃣ SACHSEN-ANHALT
      Bundesland.sachsenAnhalt: [
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'ST',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Latein',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'ST',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'ST',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'ST'),
        Subject(name: 'Bildende Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'ST'),
        // AF2
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'ST'),
        Subject(name: 'Geografie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'ST'),
        Subject(name: 'Politik/Wirtschaft',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'ST'),
        Subject(name: 'Religion/Ethik',
            area: SubjectArea.sonstiges,
            bundesland: 'ST',
            isSpecialReligion: true),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'ST',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'ST',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'ST',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'ST'),
        Subject(name: 'Sport', area: SubjectArea.sonstiges, bundesland: 'ST'),
      ],

      // 1️⃣5️⃣ SCHLESWIG-HOLSTEIN
      Bundesland.schleswigHolstein: [
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SH',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SH',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Latein',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SH',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SH'),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SH'),
        Subject(name: 'Darstellendes Spiel',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'SH'),
        // AF2
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'SH'),
        Subject(name: 'Geographie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'SH'),
        Subject(name: 'Politik/Wirtschaft',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'SH'),
        Subject(name: 'Philosophie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'SH'),
        Subject(name: 'Religion',
            area: SubjectArea.sonstiges,
            bundesland: 'SH',
            isSpecialReligion: true),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'SH',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'SH',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'SH',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'SH'),
        Subject(name: 'Sport', area: SubjectArea.sonstiges, bundesland: 'SH'),
      ],

      // 1️⃣6️⃣ THÜRINGEN
      Bundesland.thueringen: [
        Subject(name: 'Französisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'TH',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Latein',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'TH',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Spanisch',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'TH',
            isLanguageOrGerman: true,
            isLK1Eligible: true),
        Subject(name: 'Musik',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'TH'),
        Subject(name: 'Kunst',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'TH'),
        Subject(name: 'Darstellendes Spiel',
            area: SubjectArea.sprachlichKreativ,
            bundesland: 'TH'),
        // AF2
        Subject(name: 'Geschichte',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'TH'),
        Subject(name: 'Geografie',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'TH'),
        Subject(name: 'Sozialkunde',
            area: SubjectArea.gesellschaftlich,
            bundesland: 'TH'),
        Subject(name: 'Religion/Philosophie',
            area: SubjectArea.sonstiges,
            bundesland: 'TH',
            isSpecialReligion: true),
        // AF3
        Subject(name: 'Physik',
            area: SubjectArea.mint,
            bundesland: 'TH',
            isLK1Eligible: true),
        Subject(name: 'Chemie',
            area: SubjectArea.mint,
            bundesland: 'TH',
            isLK1Eligible: true),
        Subject(name: 'Biologie',
            area: SubjectArea.mint,
            bundesland: 'TH',
            isLK1Eligible: true),
        Subject(name: 'Informatik', area: SubjectArea.mint, bundesland: 'TH'),
        Subject(name: 'Sport', area: SubjectArea.sonstiges, bundesland: 'TH'),
      ],
    };

    if (selectedBundesland != null) {
      if (widget.initialCombination != null) {
        _restoreOfferedSubjectsByName(
          widget.initialCombination!.offeredSubjectNames,
        );

        lk1 = _findSubjectByName(widget.initialCombination!.lk1Name);
        lk2 = _findSubjectByName(widget.initialCombination!.lk2Name);
        schriftlich3 =
            _findSubjectByName(widget.initialCombination!.schriftlich3Name);
        muendlich =
            _findSubjectByName(widget.initialCombination!.muendlichName);

        currentStep = 1;
      } else {
        _restoreOfferedSubjectsByName(widget.settings.lastOfferedSubjectNames);
      }
    }

    cleanupInactiveDevicesOnStart();  // delete old/inactive devices
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_authService.isLoggedIn) {  // Fixed naming
        await _deviceService.touchCurrentDevice();
        print('Current device touched');  // DEBUG
      }
    });
  }

  Future<void> _saveCurrentCombination() async {
    if (selectedBundesland == null) return;

    final existingCombination = widget.initialCombination;
    final controller = TextEditingController(
      text: existingCombination?.name ?? '',
    );
    String? errorText;

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final trimmed = controller.text.trim();

              final duplicateExists = widget.settings.savedCombinations.any(
                    (combo) =>
                combo.name == trimmed &&
                    combo.id != existingCombination?.id,
              );

              if (trimmed.isEmpty) {
                setDialogState(() {
                  errorText = 'Bitte gib einen Namen ein.';
                });
                return;
              }

              if (duplicateExists) {
                setDialogState(() {
                  errorText = 'Dieser Name ist bereits vergeben.';
                });
                return;
              }

              Navigator.pop(dialogContext, trimmed);
            }

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              title: Text(
                existingCombination == null
                    ? 'Kombination speichern'
                    : 'Kombination aktualisieren',
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 280,
                    maxWidth: 420,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vergib einen eindeutigen Namen für diese Konfiguration.',
                        style: Theme
                            .of(context)
                            .textTheme
                            .bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => submit(),
                        decoration: InputDecoration(
                          labelText: 'Name der Kombination',
                          hintText: 'z. B. NRW – Bio / Geschichte',
                          errorText: errorText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: submit,
                  child: Text(
                    existingCombination == null
                        ? 'Speichern'
                        : 'Aktualisieren',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (name == null || name
        .trim()
        .isEmpty) return;

    final now = DateTime.now();

    final combination = SavedAbiCombination(
      id: existingCombination?.id ?? now.microsecondsSinceEpoch.toString(),
      name: name.trim(),
      bundeslandCode: getBundeslandCode(selectedBundesland!),
      offeredSubjectNames: offeredSubjects.map((s) => s.name).toList(),
      lk1Name: lk1?.name,
      lk2Name: lk2?.name,
      schriftlich3Name: schriftlich3?.name,
      muendlichName: muendlich?.name,
      createdAt: existingCombination?.createdAt ?? now,
      updatedAt: now,
    );

    await widget.settings.saveAbiCombination(combination);
    await widget.settings.setLastOfferedSubjectNames(
      offeredSubjects.map((s) => s.name).toList(),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existingCombination == null
              ? '„${name.trim()}“ wurde gespeichert'
              : '„${name.trim()}“ wurde aktualisiert',
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    final isDark = widget.settings.isDarkMode;

    if (currentStep == 4) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AbiCombinationOverviewPage(
                                settings: widget.settings,
                              ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.grid_view_rounded, size: 20),
                    label: const Text(
                      'Übersicht',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saveCurrentCombination,
                    icon: const Icon(Icons.save_rounded, size: 20),
                    label: const Text(
                      'Speichern',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    currentStep = 0;
                    selectedBundesland = null;
                    offeredSubjects
                      ..clear()
                      ..addAll(alwaysActiveSubjects);
                    lk1 = lk2 = schriftlich3 = muendlich = null;
                  });
                },
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text(
                  'Neustarten',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                if (currentStep == 0) {
                  Navigator.pop(context);
                } else {
                  setState(() => currentStep--);
                }
              },
              icon: const Icon(Icons.arrow_back, size: 20),
              label: const Text(
                'Zurück',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _canGoNext ? _goNext : null,
              icon: const Icon(Icons.arrow_forward, size: 20),
              label: const Text(
                'Weiter',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Abi-Prüfungs-Planer – Schritt ${currentStep + 1}'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => _goToHome(context),
        ),
        elevation: 0,
      ),
      body: _buildStep(),
      bottomNavigationBar: _buildActionButton(),
    );
  }

  void _goToHome(BuildContext context) {
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  Widget _buildStep() {
    switch (currentStep) {
      case 0:
        return _buildBundeslandStep();
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3();
      case 4:
        return _buildStep4();
      default:
        return const SizedBox();
    }
  }

  Widget _buildBundeslandStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school, size: 80,
              color: Colors.blue.withValues(alpha: 0.3)),
          const SizedBox(height: 32),
          const Text(
            'Willkommen beim Abi-LK-Helfer!',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Die Abiturregelungen unterscheiden sich je nach Bundesland.\nWähle dein Bundesland:',
            style: TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: Bundesland.values.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final land = Bundesland.values[index];
                final isSelected = selectedBundesland == land;

                return Card(
                  elevation: isSelected ? 4 : 0,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: SizedBox(
                      width: 50,
                      height: 50,
                      child: SvgPicture.asset(
                        'assets/wappen/${_getBundeslandInitial(land)}.svg',
                        width: 36,
                        height: 36,
                        fit: BoxFit.contain,
                      ),
                    ),
                    title: Text(
                      _getBundeslandName(land),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(
                      Icons.check_circle_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    )
                        : null,
                    onTap: () {
                      setState(() {
                        selectedBundesland = land;
                        widget.settings.setBundesland(land);
                        offeredSubjects
                          ..clear()
                          ..addAll(alwaysActiveSubjects);
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _goNext() {
    if (currentStep < 4) setState(() => currentStep++);
  }

  bool get _canGoNext {
    switch (currentStep) {
      case 0:
        return step0Complete;
      case 1:
        return step1Complete;
      case 2:
        return step2Complete;
      case 3:
        return step3Complete;
      default:
        return true;
    }
  }

  Widget _buildStep1() {
    if (selectedBundesland == null) {
      return const Center(child: Text('Bitte wähle zuerst ein Bundesland'));
    }

    return Padding(
      padding: const EdgeInsets.all(15.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _getBundeslandColor(selectedBundesland!),
                child: Text(_getBundeslandInitial(selectedBundesland!),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Schritt 1: Wähle die auf deiner Schule im Abitur angebotenen Fächer',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${availableSubjects
                          .length} verfügbare Fächer (${offeredSubjects
                          .length} ausgewählt)',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(child: _buildSubjectGrid()),
        ],
      ),
    );
  }

  bool get step1Complete => offeredSubjects.length >= 4;

  Widget _buildSubjectGrid() {
    final subjects = availableSubjects;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardTheme = theme.cardTheme;
    final textTheme = theme.textTheme;

    final baseCardColor = cardTheme.color ?? colorScheme.surface;
    final baseBorderColor =
        (cardTheme.shape as RoundedRectangleBorder?)?.side.color ??
            theme.dividerColor;

    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.9,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: subjects.length,
      itemBuilder: (context, index) {
        final subject = subjects[index];
        final isAlwaysActive = subject.isAlwaysActive;
        final isSelected = offeredSubjects.contains(subject) || isAlwaysActive;
        final areaColor = _getAreaColor(subject.area);

        final selectedBorderColor = areaColor;
        final selectedBg = areaColor.withValues(alpha: 0.12);

        return Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          elevation: isSelected ? 0 : cardTheme.elevation ?? 0,
          color: isSelected ? selectedBg : baseCardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isSelected ? selectedBorderColor : baseBorderColor,
              width: isSelected ? 1.6 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: isAlwaysActive
                ? null
                : () {
              setState(() {
                if (isSelected) {
                  offeredSubjects.remove(subject);
                  if (lk1 == subject) lk1 = null;
                  if (lk2 == subject) lk2 = null;
                  if (schriftlich3 == subject) schriftlich3 = null;
                  if (muendlich == subject) muendlich = null;
                } else {
                  offeredSubjects.add(subject);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? selectedBorderColor
                              : areaColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: areaColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Icon(
                          isAlwaysActive
                              ? Icons.lock_rounded
                              : isSelected
                              ? Icons.check_rounded
                              : Icons.add_rounded,
                          size: 14,
                          color: isSelected
                              ? colorScheme.onPrimary
                              : areaColor.withValues(alpha: 0.95),
                        ),
                      ),
                      const Spacer(),
                      Chip(
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                        backgroundColor: areaColor.withValues(alpha: 0.10),
                        label: Text(
                          _getAreaName(subject.area),
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: areaColor.withValues(alpha: 0.98),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    subject.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight:
                      isAlwaysActive ? FontWeight.w800 : FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                      height: 1.15,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    isAlwaysActive
                        ? 'Pflichtfach'
                        : isSelected
                        ? 'Ausgewählt'
                        : 'Antippen zum Auswählen',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: isSelected
                          ? selectedBorderColor
                          : textTheme.bodyMedium?.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


// base-subjects that offered everytime
  List<Subject> get _baseSubjects {
    if (selectedBundesland == null) return [];
    // offeredSubjects enthält immer D/M/E + deine Auswahl
    return offeredSubjects.toList();
  }

// 1. LK: LK-eligable + base-subjects (Mathe, Deutsch, Englisch
  List<Subject> get availableForLK1 {
    if (selectedBundesland == null) return [];
    final set = <Subject>{
      ..._baseSubjects.where((s) => s.isLK1Eligible),
      ...coreSubjects,
    };

    if (lk1 != null) set.add(lk1!);
    // LK1 != LK2 != schriftlich != mündlich
    set.remove(lk2);
    set.remove(schriftlich3);
    set.remove(muendlich);
    return set.toList();
  }

  List<Subject> get availableForLK2 {
    if (selectedBundesland == null) return [];

    final set = <Subject>{
      ..._baseSubjects,
      ...coreSubjects,
    };

    // LK2 != LK1 != schriftlich != mündlich
    set.remove(lk1);
    set.remove(schriftlich3);
    set.remove(muendlich);


    if (lk2 != null) {
      set.add(lk2!);
    }

    return set.toList();
  }

// base: every offered + base-subjects (Mathe, Deutsch, Englisch)
  List<Subject> get _basePruefungsSubjects {
    if (selectedBundesland == null) return [];
    return {
      ..._baseSubjects,
      ...coreSubjects,
    }.toList();
  }


  List<Subject> get availableForPruefungen {
    if (selectedBundesland == null) return [];

    final set = <Subject>{
      ..._basePruefungsSubjects,
    };


    set.remove(lk1);
    set.remove(lk2);
    set.remove(schriftlich3);
    set.remove(muendlich);

    // keep selected subjects in set
    if (schriftlich3 != null) set.add(schriftlich3!);
    if (muendlich != null) set.add(muendlich!);

    return set.toList();
  }


  bool get step2Complete => lk1 != null && lk2 != null && lk1 != lk2;

  bool get step3Complete => _allRulesValid();

  Widget get courseCoverageIndicator {
    if (personalCoursesComplete) return const SizedBox.shrink();  // Vollständig → versteckt

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kAccentWarning.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(
                  color: kAccentWarning, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text('FEHLENDE BEREICHE', style: TextStyle(
                fontWeight: FontWeight.bold,
                color: kAccentWarning,
                fontSize: 16,
              )),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 6, children:
          missingCourseAreas.map((area) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: getAreaColor(area).withOpacity(0.4),
                  shape: BoxShape.circle,
                  border: Border.all(color: getAreaColor(area), width: 1.5),
                ),
              ),
              const SizedBox(width: 6),
              Text(_getAreaShortName(area),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          )).toList()
          ),
        ],
      ),
    );
  }

  Set<SubjectArea> get selectedCourseAreas {
    final courses = [lk1, lk2, schriftlich3, muendlich].whereType<Subject>();
    return courses.map((s) => s.area).toSet();
  }

  Set<SubjectArea> get missingCourseAreas {
    return {SubjectArea.sprachlichKreativ, SubjectArea.gesellschaftlich, SubjectArea.mint}
        .difference(selectedCourseAreas);
  }

  bool get personalCoursesComplete => missingCourseAreas.isEmpty;

  Color getAreaColor(SubjectArea area) => _getAreaColor(area);

  String get courseCoverageStatus {
    final coveredDots = selectedCourseAreas.map((a) => '●').join(' ');
    final missingDots = missingCourseAreas.map((a) => '○').join(' ');

    return personalCoursesComplete
        ? 'Alle Bereiche abgedeckt: $coveredDots'
        : 'FEHLT NOCH: $missingDots';
  }

  String _getAreaShortName(SubjectArea area) => switch(area) {
    SubjectArea.sprachlichKreativ => 'Sprachlich',
    SubjectArea.gesellschaftlich  => 'Gesellschaftlich',
    SubjectArea.mint               => 'MINT',
    _ => 'Sonstiges',
  };

  Widget _buildStep2() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Schritt 2: Leistungskurse (${_getBundeslandName(
                selectedBundesland!)})',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '1. LK: $_availableLK1Count Optionen (D/M/E/FS/Nawi verfügbar)',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          _buildDropdownSection(
            '1. LK (fortgeführte Fremdsprache, Mathe, Nawi, Deutsch):',
            lk1,
            availableForLK1,
                () => lk1,
                (v) => lk1 = v,
          ),
          const SizedBox(height: 32),
          _buildDropdownSection(
            '2. LK (frei wählbar):',
            lk2,
            availableForLK2,
                () => lk2,
                (v) => lk2 = v,
          ),
          if (currentStep >= 2) courseCoverageIndicator,
        ],
      ),
    );
  }

  int get _availableLK1Count => availableForLK1.length;

  Widget _buildStep3() {
    final pruefungsOptions = availableForPruefungen;

    if (schriftlich3 != null && !pruefungsOptions.contains(schriftlich3)) {
      schriftlich3 = null;
    }
    if (muendlich != null && !pruefungsOptions.contains(muendlich)) {
      muendlich = null;
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Schritt 3: Abiturprüfungen\n2 LK, 1 schriftlich, 1 mündlich',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            'Verfügbar: ${pruefungsOptions.length} Fächer',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          _buildDropdownSection(
            '3. schriftlich:',
            schriftlich3,
            pruefungsOptions,
                () => schriftlich3,
                (v) => schriftlich3 = v,
          ),
          const SizedBox(height: 32),
          _buildDropdownSection(
            'Mündlich:',
            muendlich,
            pruefungsOptions,
                () => muendlich,
                (v) => muendlich = v,
          ),
          if (currentStep >= 3) courseCoverageIndicator,
        ],
      ),
    );
  }

  bool _allRulesValid() {
    final pruefungen =
    [lk1, lk2, schriftlich3, muendlich].whereType<Subject>().toList();
    if (pruefungen.length != 4) return false;

    if (!_coversAllAreas(pruefungen)) return false;

    switch (selectedBundesland) {
      case Bundesland.badenWuerttemberg:
        return _bwRules(pruefungen);
      case Bundesland.nordrheinWestfalen:
        return _nrwRules(pruefungen);
      case Bundesland.brandenburg:
        return _bbRules(pruefungen);
      case Bundesland.hamburg:
        return _hhRules(pruefungen);
      case Bundesland.hessen:
        return _heRules(pruefungen);
      case Bundesland.saarland:
        return _slRules(pruefungen);
      default:
        return _defaultRules(pruefungen);
    }
  }

  bool _coversAllAreas(List<Subject> pruefungen) {
    bool hasSprachlich = false,
        hasGesellschaftlich = false,
        hasMINT = false;
    for (final s in pruefungen) {
      switch (s.area) {
        case SubjectArea.sprachlichKreativ:
          if (s.isLanguageOrGerman) hasSprachlich = true;
        case SubjectArea.gesellschaftlich:
          hasGesellschaftlich = true;
        case SubjectArea.mint:
          hasMINT = true;
        case SubjectArea.sonstiges:
          if (s.isSpecialReligion) hasGesellschaftlich = true;
      }
    }
    return hasSprachlich && hasGesellschaftlich && hasMINT;
  }

  bool _bwRules(List<Subject> pruefungen) {
    return pruefungen.any((s) => s.name == 'Deutsch') &&
        pruefungen.any((s) => s.name == 'Mathematik');
  }

  bool _nrwRules(List<Subject> pruefungen) {
    final hasSprachlich = pruefungen.any((s) => s.isLanguageOrGerman);
    if (!hasSprachlich) return false;

    final religionCount = pruefungen
        .where((s) => s.isSpecialReligion)
        .length;
    final gesellschaftlichCount =
        pruefungen
            .where((s) => s.area == SubjectArea.gesellschaftlich)
            .length;
    if (religionCount > 0 && gesellschaftlichCount == 0) return false;

    if (pruefungen.any((s) => s.isSpecialReligion) &&
        pruefungen.any((s) => s.name == 'Sport')) {
      return false;
    }

    return true;
  }

  bool _bbRules(List<Subject> pruefungen) {
    final artsCount = pruefungen
        .where((s) =>
        ['Kunst', 'Musik', 'Darstellendes Spiel', 'Sport'].contains(s.name))
        .length;
    return artsCount <= 1;
  }

  bool _hhRules(List<Subject> pruefungen) {
    final coreCount = pruefungen
        .where((s) =>
    s.name == 'Deutsch' ||
        s.name == 'Mathematik' ||
        s.isLanguageOrGerman)
        .length;
    return coreCount >= 2;
  }

  bool _heRules(List<Subject> pruefungen) {
    return pruefungen.any((s) => s.name == 'Deutsch') &&
        pruefungen.any((s) => s.name == 'Mathematik') &&
        pruefungen.any((s) =>
        s.isLanguageOrGerman ||
            ['Physik', 'Chemie', 'Biologie', 'Informatik'].contains(s.name));
  }

  bool _slRules(List<Subject> pruefungen) {
    final hasCore = pruefungen.any((s) => s.name == 'Deutsch') &&
        pruefungen.any((s) => s.name == 'Mathematik') &&
        pruefungen.any((s) => s.isLanguageOrGerman && s.name != 'Deutsch');
    final lkCoreCount = [lk1, lk2]
        .whereType<Subject>()
        .where((s) =>
    s.name == 'Deutsch' ||
        s.name == 'Mathematik' ||
        (s.isLanguageOrGerman && s.name != 'Deutsch'))
        .length;
    return hasCore && lkCoreCount >= 2;
  }

  bool _defaultRules(List<Subject> pruefungen) {
    final coreCount = pruefungen
        .where((s) =>
    s.name == 'Deutsch' ||
        s.name == 'Mathematik' ||
        s.isLanguageOrGerman)
        .length;
    return coreCount >= 2;
  }

  Widget _buildDropdownSection(String label,
      Subject? value,
      List<Subject> options,
      Subject? Function() getter,
      Function(Subject?) setter,) {
    final isDarkMode = widget.settings.isDarkMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Subject>(
              value: value,
              hint: Text(
                'Wähle $label',
                style: TextStyle(
                  fontSize: 20,
                  color: isDarkMode ? Colors.white70 : Colors.grey,
                ),
              ),
              isExpanded: true,
              iconSize: 32,
              style: const TextStyle(fontSize: 20),
              items: options
                  .map((s) =>
                  DropdownMenuItem(
                    value: s,
                    child: Row(
                      children: [
                        Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _getAreaColor(s.area),
                              shape: BoxShape.circle,
                            )),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            s.name,
                            style: TextStyle(
                              color:
                              isDarkMode ? Colors.white : Colors.black87,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ))
                  .toList(),
              onChanged: (v) => setState(() => setter(v)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildValidationWarnings() {
    final pruefungen =
    [lk1, lk2, schriftlich3, muendlich].whereType<Subject>().toList();

    return Column(
      children: [
        if (!_coversAllAreas(pruefungen))
          _buildWarningCard(Icons.warning, Colors.orange,
              'Fehlende Aufgabenfelder: Sprachlich (nur Deutsch/FS), Gesellschaftlich, MINT'),
        if (!_twoFromCoreSubjects(pruefungen))
          _buildWarningCard(Icons.warning, Colors.orange,
              'Mindestens 2 aus Deutsch/Fremdsprache/Mathematik'),
        if (lk1 != null &&
            !lk1!.isLK1Eligible &&
            selectedBundesland == Bundesland.nordrheinWestfalen)
          _buildWarningCard(Icons.warning, Colors.red,
              '1. LK (NRW): Muss FS/Mathe/Nawi/Deutsch sein'),
        if (_hasReligionAndSport(pruefungen))
          _buildWarningCard(Icons.warning, Colors.red,
              'Religion/Ethik + Sport nicht gleichzeitig (NRW)'),
        if (selectedBundesland == Bundesland.badenWuerttemberg &&
            (!pruefungen.any((s) => s.name == 'Deutsch') ||
                !pruefungen.any((s) => s.name == 'Mathematik')))
          _buildWarningCard(Icons.warning, Colors.red,
              'BW: Deutsch + Mathematik pflicht'),
      ],
    );
  }

  Widget _buildWarningCard(IconData icon, Color color, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Expanded(
            child: Text(text, style: TextStyle(fontSize: 16, color: color))),
      ]),
    );
  }

  Widget _buildStep4() {
    final pruefungen = {
      '1. LK': lk1,
      '2. LK': lk2,
      '3. schriftlich': schriftlich3,
      'Mündlich': muendlich,
    };

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          const Icon(Icons.check_circle, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          const Text(
            'Gültige Abiturkombination!',
            style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          Text(
            'für: ${_getBundeslandName(selectedBundesland!)}',
            style: TextStyle(fontSize: 18, color: Colors.grey[700]),
          ),
          const SizedBox(height: 32),
          Expanded(
              child: Card(
                elevation: 8,
                color: Colors.green.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Deine Fächerkombination:',
                          style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      ...pruefungen.entries.map((e) =>
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(children: [
                              Text('${e.key}:',
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 16),
                              Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      e.value?.name ?? "–",
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  )),
                            ]),
                          )),
                      const SizedBox(height: 24),
                      Text('✓ ${_getBundeslandName(
                          selectedBundesland!)} Regeln erfüllt!',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green)),
                      Text(
                          '\nAbgedeckte Aufgabenfelder:\n ${_getAreasString()}',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.green)),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  bool _twoFromCoreSubjects(List<Subject> pruefungen) {
    final coreCount = pruefungen
        .where((s) =>
    s.name == 'Deutsch' ||
        s.name == 'Mathematik' ||
        s.isLanguageOrGerman)
        .length;
    return coreCount >= 2;
  }

  bool _hasReligionAndSport(List<Subject> pruefungen) {
    return pruefungen.any((s) => s.isSpecialReligion) &&
        pruefungen.any((s) => s.name == 'Sport');
  }

  String _getAreasString() {
    final areas = <String>{};
    final pruefungen =
    [lk1, lk2, schriftlich3, muendlich].whereType<Subject>().toList();
    for (final s in pruefungen) {
      if (s.isLanguageOrGerman) {
        areas.add('Sprachlich ✓');
      } else if (s.area == SubjectArea.gesellschaftlich ||
          s.isSpecialReligion) {
        areas.add('Gesellschaftlich ✓');
      } else if (s.area == SubjectArea.mint) {
        areas.add('MINT ✓');
      }
    }
    return areas.join(', ');
  }

  String _getAreaName(SubjectArea area) =>
      switch (area) {
        SubjectArea.sprachlichKreativ => 'Sprachlich-Kreativ',
        SubjectArea.gesellschaftlich => 'Gesellschaftlich',
        SubjectArea.mint => 'MINT',
        SubjectArea.sonstiges => 'Sonstiges',
      };


  Color _getAreaColor(SubjectArea area) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (area) {
      case SubjectArea.sprachlichKreativ:
        return isDark
            ? const Color(0xFFB794F6) // soft purple
            : const Color(0xFF7C3AED); // clear purple
      case SubjectArea.gesellschaftlich:
        return isDark
            ? const Color(0xFFF6AD55) // warm orange
            : const Color(0xFFDD6B20); // orange
      case SubjectArea.mint:
        return isDark
            ? const Color(0xFF63D2B0) // turqoise
            : const Color(0xFF0F9D7A); // clear teal
      case SubjectArea.sonstiges:
        return isDark
            ? const Color(0xFF90CDF4) // cold light blue
            : const Color(0xFF3182CE); // clean blue
    }
  }

  Future<void> cleanupInactiveDevicesOnStart() async {  // RENAME this method
    try {
      if (!_authService.isLoggedIn) return;           // CHANGE: _authService
      await _deviceService.deleteInactiveDevices();    // CHANGE: _deviceService
    } catch (e) {}
  }
}