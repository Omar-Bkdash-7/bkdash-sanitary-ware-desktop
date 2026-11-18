import 'package:flutter/material.dart';

/// The brand mark: a gradient tile with a water drop, optionally with the name.
class BkdashLogo extends StatelessWidget {
  const BkdashLogo({
    super.key,
    this.size = 40,
    this.showText = true,
    this.isDark = false,
  });

  final double size;
  final bool showText;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * 0.15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.3),
            gradient: const LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF059669), Color(0xFF06B6D4)],
              begin: Alignment.bottomRight,
              end: Alignment.topLeft,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D9488).withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const FittedBox(
            child: Icon(Icons.water_drop_rounded, color: Colors.white),
          ),
        ),
        if (showText) ...[
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'بكداش للأدوات الصحية',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Text(
                'BKDASH SANITARY WARE',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.tealAccent : const Color(0xFF0F766E),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
