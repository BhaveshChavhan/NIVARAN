import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'services/safety_service.dart';
import 'services/local_storage_service.dart';
import 'services/mesh_service.dart';
import 'services/mesh_call_service.dart';
import 'services/theme_service.dart';
import 'services/blockchain_service.dart';
import 'services/user_service.dart';
import 'services/sos_background_service.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/evidence_service.dart';
import 'services/night_mode_provider.dart';
import 'screens/night_mode_screen.dart';
import 'services/notification_service.dart';

import 'services/weather_service.dart';
import 'services/offline_map_service.dart';
import 'services/wearable_service.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  await NotificationService.showPersistentSOS();
  await LocalStorageService.init();
  
  await Supabase.initialize(
    url: 'https://lffrcldhbesywswwjqnu.supabase.co',
    anonKey: 'sb_publishable_arkbVnMWBz7syDVEDEOGRQ_xr_GyHsO',
  );
  
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const NivaranApp());
}

class NivaranApp extends StatelessWidget {
  const NivaranApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeService()),
        ChangeNotifierProvider(create: (context) => BlockchainService()),
        ChangeNotifierProvider(create: (context) => WeatherService()), // Registered WeatherService
        ChangeNotifierProvider(create: (context) => UserService()),
        ChangeNotifierProvider(create: (context) => AuthService()),
        ChangeNotifierProvider(create: (context) => EvidenceService()),
        ChangeNotifierProvider(create: (context) => SOSBackgroundServiceBridge()),
        ChangeNotifierProxyProvider<UserService, MeshService>(
          create: (context) => MeshService(),
          update: (context, user, previous) {
            final mesh = previous ?? MeshService();
            if (user.profile != null) {
              if (user.profile!.name.isNotEmpty) {
                mesh.updateUserName(user.profile!.name);
              }
              if (user.profile!.email.isNotEmpty) {
                mesh.updateUserEmail(user.profile!.email);
              }
            }
            return mesh;
          },
        ),
        ChangeNotifierProvider(create: (context) => OfflineMapService()),
        ChangeNotifierProxyProvider4<BlockchainService, UserService, WeatherService, MeshService, SafetyService>(
          create: (context) => SafetyService(),
          update: (context, blockchain, user, weather, mesh, safety) {
            final currentSafety = safety ?? SafetyService();
            currentSafety.updateBlockchainService(blockchain);
            currentSafety.updateWeatherService(weather); // Added weather service link
            currentSafety.updateMeshService(mesh); // Added mesh service link
            currentSafety.updateOfflineMapService(context.read<OfflineMapService>()); // Offline map & zone sync link
            
            // Link native background service triggers to our safety service
            final bridge = context.read<SOSBackgroundServiceBridge>();
            bridge.onSOSTriggered = () => currentSafety.activateSOS();
            if (!bridge.serviceRunning) bridge.startService();
            
            if (user.profile != null) {
              currentSafety.updateUserContext(user.profile!.name, user.profile!.email);
            }
            return currentSafety;
          },
        ),
        ChangeNotifierProxyProvider<MeshService, MeshCallService>(
          create: (context) => MeshCallService(context.read<MeshService>()),
          update: (context, mesh, previous) => previous ?? MeshCallService(mesh),
        ),
        ChangeNotifierProvider(create: (context) => NightModeProvider()),
        ChangeNotifierProvider(create: (context) => WearableService.instance),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, _) {
          return MaterialApp(
            title: 'NIVARAN',
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: scaffoldMessengerKey,
            debugShowCheckedModeBanner: false,
            themeMode: themeService.themeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: const SplashScreen(),
            routes: {
              '/night-mode': (context) => const NightModeScreen(),
            },
          );
        },
      ),
    );
  }
}

