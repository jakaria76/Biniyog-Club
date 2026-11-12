import 'package:flutter/material.dart';

import '../page/investor/dashboard/investor_dashboard_page.dart';

/// Login er por prothom screen.
/// Purono shada floating bar (Overview / Investments / Projects / Portfolio)
/// ar nei — notun curved bottom navbar (Home / Projects / Groups /
/// Invested / Profile) InvestorDashboardPage er bhitorei ache.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const InvestorDashboardPage();
}