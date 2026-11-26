import 'dart:math' as math;

import 'package:bkdash_sanitary_ware/core/formatting/money.dart';
import 'package:bkdash_sanitary_ware/features/reports/models/report_models.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// The colours of the category slices (repeated when there are more).
const List<Color> kCategoryColors = <Color>[
  Color(0xFF0D9488),
  Color(0xFF0284C7),
  Color(0xFFD97706),
  Color(0xFF7C3AED),
  Color(0xFFE11D48),
  Color(0xFF65A30D),
  Color(0xFF64748B),
];

/// Share of each category in the sales, as a donut chart with a legend.
class CategoryPieChart extends StatelessWidget {
  const CategoryPieChart({super.key, required this.categories});

  final List<CategorySales> categories;

  /// The biggest categories are listed; the rest are merged into an "Other" slice.
  static const int _maxSlices = 6;

  List<CategorySales> get _slices {
    if (categories.length <= _maxSlices) return categories;
    final head = categories.take(_maxSlices - 1).toList();
    final rest = categories.skip(_maxSlices - 1);
    return [
      ...head,
      CategorySales(
        category: 'أخرى',
        sales: Money.sum(rest.map((c) => c.sales)),
        profit: Money.sum(rest.map((c) => c.profit)),
        pieces: rest.fold(0, (sum, c) => sum + c.pieces),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slices = _slices;
    final total = Money.sum(slices.map((slice) => slice.sales));
    double percent(CategorySales slice) =>
        total.isPositive ? slice.sales.cents * 100 / total.cents : 0;

    return Column(
      children: [
        SizedBox(
          height: 190,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 38,
                sections: [
                  for (var i = 0; i < slices.length; i++)
                    PieChartSectionData(
                      value: math.max(slices[i].sales.cents / 100, 0.01),
                      color: kCategoryColors[i % kCategoryColors.length],
                      radius: 56,
                      title: percent(slices[i]) >= 6
                          ? '${percent(slices[i]).toStringAsFixed(0)}%'
                          : '',
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < slices.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: kCategoryColors[i % kCategoryColors.length],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(slices[i].category)),
                Text(
                  '${percent(slices[i]).toStringAsFixed(1)}%  ',
                  style: theme.textTheme.bodySmall,
                  textDirection: TextDirection.ltr,
                ),
                Text(
                  slices[i].sales.format(),
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
