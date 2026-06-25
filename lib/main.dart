import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/shared/splash_screen.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

bool firebaseInitFailed = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  
  MapboxOptions.setAccessToken(const String.fromEnvironment('MAPBOX_TOKEN', defaultValue: 'pk.eyJ1IjoiamF5Y2VlcmVjYW5hIiwiYSI6ImNtcTljamszcDAxZ2gycXBocmQxczhxN3kifQ.19WWZ3DXdaSG-LG2_zGpbg'));
  
  debugPrint("Running app...");
  runApp(const SafePathsApp());
}

class SafePathsApp extends StatelessWidget {
  const SafePathsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafePaths',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const SplashScreen(),
    );
  }
}
