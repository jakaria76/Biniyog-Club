import 'package:flutter/material.dart';
import '../page/investor/dashboard/investor_dashboard_page.dart';
import '../page/investor/portfolio/investments_page.dart';
import '../page/investor/portfolio/portfolio_page.dart';
import '../page/investor/projects/my_projects_page.dart';
import '../services/language_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  static const Color primaryTeal = Color(0xFF047857);

  final List<Widget> _pages = const [
    InvestorDashboardPage(),
    InvestmentsPage(),
    MyProjectsPage(),
    PortfolioPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.currentLanguage,
      builder: (context, lang, child) {
        final List<Map<String, dynamic>> navItems = [
          {
            'label': LanguageService.tr('Overview', 'ওভারভিউ'),
            'icon': Icons.grid_view_outlined,
            'activeIcon': Icons.grid_view_rounded,
          },
          {
            'label': LanguageService.tr('Investments', 'ইনভেস্টমেন্টস'),
            'icon': Icons.pie_chart_outline_rounded,
            'activeIcon': Icons.pie_chart_rounded,
          },
          {
            'label': LanguageService.tr('Projects', 'প্রজেক্টস'),
            'icon': Icons.business_center_outlined,
            'activeIcon': Icons.business_center_rounded,
          },
          {
            'label': LanguageService.tr('Portfolio', 'পোর্টফোলিও'),
            'icon': Icons.donut_large_outlined,
            'activeIcon': Icons.donut_large_rounded,
          },
        ];

        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F6),
          body: IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
          bottomNavigationBar: _buildCompactModernNavigationBar(navItems),
        );
      },
    );
  }

  // Compact Floating Navigation Bar
  Widget _buildCompactModernNavigationBar(
      List<Map<String, dynamic>> navItems) {
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 20, bottom: 10, top: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 14,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(navItems.length, (index) {
              final item = navItems[index];
              final bool isSelected = _currentIndex == index;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.fastOutSlowIn,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primaryTeal.withAlpha(25)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: isSelected
                        ? Border.all(
                            color: primaryTeal.withAlpha(60), width: 1)
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSelected
                            ? item['activeIcon'] as IconData
                            : item['icon'] as IconData,
                        color: isSelected ? primaryTeal : Colors.grey[600],
                        size: 19,
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 5),
                        Text(
                          item['label'] as String,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: primaryTeal,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
