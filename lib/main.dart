import 'package:flutter/material.dart';
import 'screens/home_map_screen.dart';

void main() {
  runApp(const EcoPulseApp());
}

class EcoPulseApp extends StatelessWidget {
  const EcoPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoPulse Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
      ),
      home: const HomeMapScreen(),
    );
  }
}