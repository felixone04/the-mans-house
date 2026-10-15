import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'config.dart';
import 'data/backend.dart';
import 'data/demo_backend.dart';
import 'data/supabase_backend.dart';
import 'screens/splash_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');
  Intl.defaultLocale = 'it_IT';
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // icone scure sul cemento
    systemNavigationBarColor: AppColors.black,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  final Backend backend = AppConfig.hasSupabase ? SupabaseBackend() : DemoBackend();
  await backend.init();

  runApp(BarberApp(state: AppState(backend)));
}

class BarberApp extends StatelessWidget {
  const BarberApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: MaterialApp(
          title: "The Man's House",
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          scrollBehavior: const AppScrollBehavior(),
          locale: const Locale('it', 'IT'),
          supportedLocales: const [Locale('it', 'IT')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const SplashScreen(),
        ),
      );
}
