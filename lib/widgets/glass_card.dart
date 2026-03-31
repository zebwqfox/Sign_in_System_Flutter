import 'package:flutter/material.dart';

@Deprecated('Use Card instead. Liquid Glass has been removed.')
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.radius = 24,
    this.margin,
    this.side,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? margin;
  final BorderSide? side;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: side ?? BorderSide.none,
      ),
      child: child,
    );
  }
}
