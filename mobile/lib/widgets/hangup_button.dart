import 'package:flutter/material.dart';

class HangupButton extends StatelessWidget {
  const HangupButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '挂断电话',
      child: SizedBox(
        width: 76,
        height: 76,
        child: FilledButton(
          key: const Key('hangup_button'),
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            backgroundColor: const Color(0xFFE84545),
            foregroundColor: Colors.white,
          ),
          child: const Icon(Icons.call_end_rounded, size: 36),
        ),
      ),
    );
  }
}
