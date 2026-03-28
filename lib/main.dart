import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/camera_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ResizerApp());
}

class ResizerApp extends StatelessWidget {
  const ResizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Resizer',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.dark(
          primary: Colors.blue.shade400,
          secondary: Colors.blue.shade200,
        ),
      ),
      home: const CameraScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
