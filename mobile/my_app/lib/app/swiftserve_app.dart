import 'package:flutter/material.dart';

import 'auth_gate.dart';

class SwiftServeApp extends StatelessWidget {
  const SwiftServeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SwiftServe',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1D1E21)),
        scaffoldBackgroundColor: const Color(0xFFF8F9FB),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}
