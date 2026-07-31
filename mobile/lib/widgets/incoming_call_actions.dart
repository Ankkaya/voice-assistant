import 'package:flutter/material.dart';

class IncomingCallActions extends StatelessWidget {
  const IncomingCallActions({
    required this.onDecline,
    required this.onAccept,
    super.key,
  });

  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CallAction(
          key: const Key('decline_call_button'),
          label: '拒绝',
          icon: Icons.call_end_rounded,
          color: const Color(0xFFE5484D),
          onPressed: onDecline,
        ),
        const SizedBox(width: 72),
        _ShakingAcceptAction(onPressed: onAccept),
      ],
    );
  }
}

class _ShakingAcceptAction extends StatefulWidget {
  const _ShakingAcceptAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_ShakingAcceptAction> createState() => _ShakingAcceptActionState();
}

class _ShakingAcceptActionState extends State<_ShakingAcceptAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _turns;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
    _turns = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0), weight: 22),
      TweenSequenceItem(tween: Tween(begin: 0, end: -0.035), weight: 8),
      TweenSequenceItem(tween: Tween(begin: -0.035, end: 0.035), weight: 12),
      TweenSequenceItem(tween: Tween(begin: 0.035, end: -0.025), weight: 12),
      TweenSequenceItem(tween: Tween(begin: -0.025, end: 0.025), weight: 12),
      TweenSequenceItem(tween: Tween(begin: 0.025, end: 0), weight: 8),
      TweenSequenceItem(tween: ConstantTween(0), weight: 26),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _turns,
      child: _CallAction(
        key: const Key('accept_call_button'),
        label: '接听',
        icon: Icons.call_rounded,
        color: const Color(0xFF31B768),
        onPressed: widget.onPressed,
      ),
    );
  }
}

class _CallAction extends StatelessWidget {
  const _CallAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 8,
                shadowColor: color.withValues(alpha: 0.4),
              ),
              child: Icon(icon, size: 35),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
