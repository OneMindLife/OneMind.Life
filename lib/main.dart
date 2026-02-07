import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'firebase_options.dart';
import 'config/supabase_config.dart';
import 'config/sentry_config.dart';
import 'config/router.dart';
import 'core/errors/error_handler.dart';
import 'core/errors/app_exception.dart';
import 'core/l10n/locale_provider.dart';
import 'l10n/generated/app_localizations.dart';
import 'providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use path-based URLs (e.g., /join/invite) instead of hash-based (/#/join/invite)
  usePathUrlStrategy();

  // Initialize Firebase (for Analytics) - non-fatal if it fails
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
    // Continue without Analytics - not critical for app function
  }

  // Wire ErrorHandler to Sentry for error tracking
  ErrorHandler(
    reportCallback: (AppException error, StackTrace? stackTrace) async {
      if (kDebugMode) return;

      await Sentry.captureException(
        error,
        stackTrace: stackTrace,
        withScope: (scope) {
          scope.setTag('error_code', error.codeString);
          if (error.context != null) {
            for (final entry in error.context!.entries) {
              scope.setExtra(entry.key, entry.value);
            }
          }
        },
      );
    },
    logCallback: (String level, String message, Map<String, dynamic>? data) {
      if (!kDebugMode) {
        Sentry.addBreadcrumb(Breadcrumb(
          message: message,
          level: _sentryLevelFromString(level),
          data: data,
        ));
      }
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

  // Initialize Sentry and run the app
  if (SentryConfig.isConfigured) {
    await SentryFlutter.init(
      (options) {
        options.dsn = SentryConfig.dsn;
        options.environment = SentryConfig.environment;
        options.tracesSampleRate = SentryConfig.tracesSampleRate;
        options.sampleRate = SentryConfig.sampleRate;
        options.sendDefaultPii = false;
        options.enableAutoSessionTracking = true;

        if (kDebugMode) {
          options.debug = true;
        }
      },
      appRunner: () => _runApp(sharedPreferences),
    );
  } else {
    _runApp(sharedPreferences);
  }
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

/// Convert log level string to Sentry level
SentryLevel _sentryLevelFromString(String level) {
  switch (level.toLowerCase()) {
    case 'error':
      return SentryLevel.error;
    case 'warning':
      return SentryLevel.warning;
    case 'info':
      return SentryLevel.info;
    case 'debug':
      return SentryLevel.debug;
    default:
      return SentryLevel.info;
  }
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), // Indigo
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade800),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      ),
    );
  }
}
