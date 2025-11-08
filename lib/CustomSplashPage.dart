// You'll need these imports in main.dart:
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:loader_overlay/loader_overlay.dart';

import 'main.dart';
// NOTE: Make sure these packages are still in pubspec.yaml if you need Lottie here.

class CustomSplashPage extends StatefulWidget {
  const CustomSplashPage({super.key});

  @override
  State<CustomSplashPage> createState() => _CustomSplashPageState();
}

class _CustomSplashPageState extends State<CustomSplashPage> {
  @override
  void initState() {
    super.initState();
    // Start the routing process after the delay
    _startAppInitialization();
  }

  void _startAppInitialization() async {
    // 💡 CRITICAL: Wait for a guaranteed 2 seconds for stability
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      // Navigate, forcing the new route to replace the splash page entirely
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthGate()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show your Lottie animation full screen during the waiting period
    return Scaffold(
      backgroundColor: Colors.white, // Match your app background
      body: Center(
        child: Lottie.asset(
          'assets/Loaders/App_Loader.json', // Use your Lottie file path
          width: 150,
          height: 150,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}