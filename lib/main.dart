import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/app_preferences.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/shared/splash_screen.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/notification_service.dart';
import 'widgets/sync_status_banner.dart';
import 'config/app_environment.dart';
import 'widgets/account_session_guard.dart';
import 'services/spark_backend_service.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

bool firebaseInitFailed = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.instance.load();
  try {
    if (!AppEnvironment.isFieldTest && !AppEnvironment.mainBackendRequested) {
      throw StateError(
        'Build SafePaths Marulas with its reviewed main-backend configuration.',
      );
    }
    if ((AppEnvironment.sparkReportsRequested ||
            AppEnvironment.sparkCoreRequested ||
            AppEnvironment.sparkCommunicationsRequested ||
            AppEnvironment.sparkMediaRequested) &&
        !AppEnvironment.isFieldTest &&
        !AppEnvironment.mainBackendRequested)
      throw StateError('Spark reporting requires the separate Test app.');
    if (AppEnvironment.sparkMediaRequested &&
        !AppEnvironment.sparkCommunicationsRequested)
      throw StateError('The SafePaths Test configuration is incomplete.');
    await dotenv.load(fileName: AppEnvironment.envAsset);
    if (AppEnvironment.mainBackendRequested) {
      if (AppEnvironment.isFieldTest) {
        throw StateError(
          'The Marulas backend cannot be used by SafePaths Test.',
        );
      }
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 8));
      SparkBackendService.validateConfiguration();
      final mapToken = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
      if (!mapToken.startsWith('pk.') ||
          dotenv.env.keys.any(
            (key) =>
                key.contains('PRIVATE_KEY') ||
                key.contains('SERVICE_ROLE') ||
                key.startsWith('FCM_'),
          )) {
        throw StateError(
          'Main app assets must contain only public configuration.',
        );
      }
      MapboxOptions.setAccessToken(mapToken);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      runApp(const SafePathsApp());
      unawaited(
        NotificationService.instance.initialize().catchError((Object _) {}),
      );
      return;
    }
    if (AppEnvironment.isFieldTest) {
      final app = await Firebase.initializeApp().timeout(
        const Duration(seconds: 8),
      );
      AppEnvironment.validateTestConfiguration(
        env: dotenv.env,
        actualProjectId: app.options.projectId,
        productionProjectId: DefaultFirebaseOptions.android.projectId,
      );
      if (AppEnvironment.sparkReportsRequested ||
          AppEnvironment.sparkCoreRequested ||
          AppEnvironment.sparkCommunicationsRequested ||
          AppEnvironment.sparkMediaRequested)
        SparkBackendService.validateConfiguration();
      MapboxOptions.setAccessToken(dotenv.env['MAPBOX_ACCESS_TOKEN']!);
      if (NotificationService.testPushEnabled)
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
      runApp(const SafePathsApp());
      if (NotificationService.testPushEnabled)
        unawaited(
          NotificationService.instance.initialize().catchError((Object _) {}),
        );
      return;
    }
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('App configuration is incomplete.\n$e'),
            ),
          ),
        ),
      ),
    );
    return;
  }

  // Register FCM background handler before anything else
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  debugPrint("Initializing Firebase...");
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 8));
    debugPrint("Firebase initialized successfully.");
  } catch (e) {
    firebaseInitFailed = true;
    debugPrint("FIREBASE INIT ERROR: $e");
  }

  try {
    debugPrint("Initializing Supabase...");
    final uploadUrl = dotenv.env['SUPABASE_URL'] ?? '';
    if (Uri.tryParse(uploadUrl)?.scheme != 'https')
      throw StateError('Upload service requires HTTPS.');
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? '',
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    ).timeout(const Duration(seconds: 8));
    debugPrint("Supabase initialized successfully.");
  } catch (e) {
    debugPrint("SUPABASE INIT ERROR: $e");
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  MapboxOptions.setAccessToken(dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '');

  debugPrint("Running app...");
  runApp(const SafePathsApp());
  if (!firebaseInitFailed) {
    unawaited(
      NotificationService.instance
          .initialize()
          .timeout(const Duration(seconds: 10))
          .catchError((Object e) {
            debugPrint('Notifications unavailable: $e');
          }),
    );
  }
}

class SafePathsApp extends StatelessWidget {
  const SafePathsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppPreferences.instance,
      builder: (context, _) => MaterialApp(
        locale: AppPreferences.instance.locale,
        supportedLocales: const [Locale('en'), Locale('fil')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        navigatorKey: appNavigatorKey,
        title: AppEnvironment.isFieldTest ? 'SafePaths Test' : 'SafePaths',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        darkTheme: AppTheme.darkTheme,
        themeMode: AppPreferences.instance.themeMode,
        home: const SplashScreen(),
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value:
              (Theme.of(context).brightness == Brightness.dark
                      ? SystemUiOverlayStyle.light
                      : SystemUiOverlayStyle.dark)
                  .copyWith(
                    statusBarColor: Colors.transparent,
                    systemNavigationBarColor: Theme.of(
                      context,
                    ).colorScheme.surface,
                  ),
          child: AccountSessionGuard(
            navigatorKey: appNavigatorKey,
            child: AppEnvironment.isFieldTest
                ? Column(
                    children: [
                      Container(
                        width: double.infinity,
                        color: Colors.orange.shade800,
                        padding: EdgeInsets.only(
                          top: MediaQuery.paddingOf(context).top + 4,
                          bottom: 4,
                        ),
                        child: const Text(
                          'TEST AREA — Simulated road conditions',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      Expanded(
                        child: MediaQuery.removePadding(
                          context: context,
                          removeTop: true,
                          child: child ?? const SizedBox(),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      const SyncStatusBanner(),
                      Expanded(child: child ?? const SizedBox()),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
