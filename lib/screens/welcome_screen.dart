import 'dart:async';
import 'package:flutter/material.dart';

class WelcomeScreen extends StatefulWidget {
  final VoidCallback onStart;

  const WelcomeScreen({
    super.key,
    required this.onStart,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  Timer? timer;

  @override
  void initState() {
    super.initState();

    timer = Timer(
      const Duration(milliseconds: 1800),
      widget.onStart,
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void skip() {
    timer?.cancel();
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: skip,
      child: Scaffold(
        body: SizedBox.expand(
          child: Image.asset(
            "assets/images/splash.png",
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
