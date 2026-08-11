import 'package:flutter/material.dart';

class StartupPage extends StatelessWidget {
  const StartupPage({super.key});

  static const assetPath = 'assets/startup.png';

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xffb8f2b5),
      body: SizedBox.expand(
        child: Image(
          image: AssetImage(assetPath),
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
    );
  }
}
