import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options_stub.dart';
import 'config/app_colors.dart';
import 'config/supabase_config.dart';
import 'config/router.dart';
import 'services/analytics_web_stub.dart'
    if (dart.library.html) 'services/analytics_web.dart';
import 'core/errors/error_handler.dart';
import 'core/errors/app_exception.dart';
import 'core/l10n/locale_provider.dart';
import 'l10n/generated/app_localizations.dart';
import 'providers/providers.dart';
import 'utils/perf_logger.dart';
import 'utils/web_timing_stub.dart'
    if (dart.library.html) 'utils/web_timing.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use path-based URLs (e.g., /join/invite) instead of hash-based (/#/join/invite)
  usePathUrlStrategy();

  // Initialize Firebase (for Analytics) - non-fatal if it fails
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Continue without Analytics - not critical for app function
  }

  // Wire ErrorHandler to PostHog error tracking. On web, Flutter errors are
  // forwarded to window.posthog.captureException via the index.html bridge, so
  // each error links to the user's session replay. (Replaced Sentry, whose
  // SentryFlutter.init white-screened Flutter web.)
  ErrorHandler(
    reportCallback: (AppException error, StackTrace? stackTrace) async {
      if (kDebugMode) return;
      sendWebException(
        error.codeString,
        error.toString(),
        stackTrace?.toString(),
      );
    },
  );

  // Validate configuration for production builds
  SupabaseConfig.validateForProduction();

  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // Initialize SharedPreferences for localization
  final sharedPreferences = await SharedPreferences.getInstance();

  // Perf logger: emit timing events to remote `perf_logs` for diagnosis.
  // Default-on in debug builds. In release builds (production web at
  // onemind.life), opt-in via `?perflog=1` query param OR a sticky
  // `flutter.perflog` SharedPreferences flag — the param sets the flag,
  // so a single annotated link enables logging for the whole tab
  // session. This lets stress tests / load simulators emit telemetry
  // without billing every real user for the log writes.
  PerfLogger.enabled =
      kDebugMode || _shouldEnablePerfLog(sharedPreferences);

  // Analytics + error tracking are handled by PostHog (web posthog-js snippet in
  // index.html) + GA4 gtag. No Sentry — it broke Flutter web rendering and PostHog
  // covers error tracking (with session-replay linkage).
  _runApp(sharedPreferences);
}

void _runApp(SharedPreferences sharedPreferences) {
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const OneMindApp(),
    ),
  );
}

/// Decide whether to enable [PerfLogger] in release builds.
///
/// Two equivalent triggers — either turns it on for the rest of the tab:
///   1. URL contains `?perflog=1` (or `&perflog=1`). The flag is stored
///      in SharedPreferences so a refresh / SPA navigation doesn't lose
///      it. To turn it off again, append `?perflog=0`.
///   2. SharedPreferences key `perflog` is `true` (set previously by #1
///      or manually by a debug tool).
///
/// Any other state — including the absence of the URL param — leaves
/// the flag at whatever the previous session set, which is what we
/// want: an annotated bot link only needs to be hit once.
bool _shouldEnablePerfLog(SharedPreferences prefs) {
  // kIsWeb gate keeps us off the dart:html dependency on mobile builds
  // where PerfLogger is already on (kDebugMode usually).
  if (kIsWeb) {
    final uri = Uri.tryParse(Uri.base.toString());
    final qp = uri?.queryParameters['perflog'];
    if (qp == '1' || qp == 'true') {
      prefs.setBool('perflog', true);
      return true;
    }
    if (qp == '0' || qp == 'false') {
      prefs.setBool('perflog', false);
      return false;
    }
  }
  return prefs.getBool('perflog') ?? false;
}

const _fadeTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: _CrossFadePageTransitionsBuilder(),
    TargetPlatform.iOS: _CrossFadePageTransitionsBuilder(),
    TargetPlatform.linux: _CrossFadePageTransitionsBuilder(),
    TargetPlatform.macOS: _CrossFadePageTransitionsBuilder(),
    TargetPlatform.windows: _CrossFadePageTransitionsBuilder(),
  },
);

ThemeData _buildLightTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.seed,
    brightness: Brightness.light,
    surface: AppColors.surfaceWarm,
  );
  final textTheme = GoogleFonts.plusJakartaSansTextTheme(
    ThemeData.light().textTheme,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    textTheme: textTheme.copyWith(
      headlineMedium: textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleSmall: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodySmall: textTheme.bodySmall?.copyWith(
        color: AppColors.textSecondary,
      ),
      labelSmall: textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w500,
      ),
    ),
    scaffoldBackgroundColor: AppColors.surfaceWarm,
    pageTransitionsTheme: _fadeTransitions,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: colorScheme.primary,
      backgroundColor: AppColors.surfaceWarm,
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.borderWarm),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderWarm),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderWarm),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.borderWarm,
    ),
  );
}

ThemeData _buildDarkTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.seed,
    brightness: Brightness.dark,
    surface: AppColors.darkSurface,
  );
  final textTheme = GoogleFonts.plusJakartaSansTextTheme(
    ThemeData.dark().textTheme,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    textTheme: textTheme.copyWith(
      headlineMedium: textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleSmall: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelSmall: textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w500,
      ),
    ),
    scaffoldBackgroundColor: AppColors.darkSurface,
    pageTransitionsTheme: _fadeTransitions,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: colorScheme.primary,
      backgroundColor: AppColors.darkSurface,
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.darkBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      filled: true,
      fillColor: AppColors.darkSurfaceContainer,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.darkBorder,
    ),
  );
}

class OneMindApp extends ConsumerStatefulWidget {
  const OneMindApp({super.key});

  @override
  ConsumerState<OneMindApp> createState() => _OneMindAppState();
}

class _OneMindAppState extends ConsumerState<OneMindApp> {
  @override
  void initState() {
    super.initState();
    // Initialize locale on app start
    Future.microtask(() {
      ref.read(localeProvider.notifier).initialize();
    });
    // Let the HTML hero "Try It Free" CTA enter the app WITHOUT a full page
    // reload. Flutter boots behind the hero while the user reads it; on tap the
    // shell calls this to navigate go_router straight to the target (e.g.
    // /create) and then uncovers the already-rendered app — no second cold
    // start, no loading splash. Falls back to a full navigation in index.html
    // if Flutter isn't ready yet.
    registerHtmlCreateCallback((target) {
      try {
        ref.read(routerProvider).go(target);
      } catch (_) {}
    });
    // Tell the HTML shell to drop its loading splash now that Flutter has
    // rendered. The splash covers the SEO-content backdrop (demo video) that
    // would otherwise flash through during the gap between engine init and
    // first paint — most visibly on PWA launches that start at /home.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      signalFlutterFirstFrame();
    });
  }

  @override
  void dispose() {
    unregisterHtmlCreateCallback();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch auth state but don't block router - let screens handle loading
    // This ensures URL routing works on initial page load
    ref.watch(currentUserIdProvider);
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);

    // Always use router to preserve URL on initial load
    // Global tap-to-unfocus: dismisses keyboard when tapping outside text fields
    // and prevents the known Flutter bug where viewInsets.bottom gets stuck
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: MaterialApp.router(
      title: 'OneMind',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: ThemeMode.dark,
      ),
    );
  }
}

/// Cross-fade transition: outgoing page fades out, incoming page fades in.
class _CrossFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _CrossFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: bgColor,
      child: FadeTransition(
        opacity: animation,
        child: FadeTransition(
          opacity: Tween<double>(begin: 1.0, end: 0.0).animate(secondaryAnimation),
          child: child,
        ),
      ),
    );
  }
}
