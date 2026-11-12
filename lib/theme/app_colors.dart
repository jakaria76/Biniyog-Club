import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════
// BINIYOG CLUB — website er globals.css er rong (light mode)
// Website OKLCH e rong rakhe; nicher shob hex segulo theke hubohu
// convert kora (sRGB). Kono rong bodlate hole website er token o
// ek shathe bodlate hobe.
//
//   Primary   = Brand teal (logo rgb(0,140,100))
//   Secondary = Finance slate blue
//   Accent    = Harvest amber gold
// ═══════════════════════════════════════════════════════════
class BC {
  BC._();

  // ── Brand teal (--brand-50 … --brand-900)
  static const Color brand50 = Color(0xFFEBFBF6);
  static const Color brand100 = Color(0xFFCFF5EB);
  static const Color brand200 = Color(0xFF9EE8D6);
  static const Color brand300 = Color(0xFF5FD0B8);
  static const Color brand400 = Color(0xFF23AE95);
  static const Color brand500 = Color(0xFF008C75);
  static const Color brand600 = Color(0xFF006D59);
  static const Color brand700 = Color(0xFF004F3F);
  static const Color brand800 = Color(0xFF00352A);
  static const Color brand900 = Color(0xFF002119);

  // ── Finance slate blue (--finance-*)
  static const Color finance50 = Color(0xFFEDF7FE);
  static const Color finance100 = Color(0xFFD4ECFD);
  static const Color finance500 = Color(0xFF0070AB);
  static const Color finance600 = Color(0xFF00568A);
  static const Color finance700 = Color(0xFF003F69);

  // ── Harvest amber gold (--harvest-*)
  static const Color harvest50 = Color(0xFFFFF7E6);
  static const Color harvest100 = Color(0xFFFFEBC2);
  static const Color harvest400 = Color(0xFFFAB72A);
  static const Color harvest500 = Color(0xFFE39B00);
  static const Color harvest600 = Color(0xFFBE7E00);

  // ── Surface
  static const Color background = Color(0xFFFCFCF9); // --background
  static const Color foreground = Color(0xFF030507); // --foreground
  static const Color card = Color(0xFFFFFFFF); // --card
  static const Color primary = Color(0xFF006D59); // --primary (brand-600)
  static const Color primaryForeground = Color(0xFFFBFBFB);
  static const Color secondary = Color(0xFFE0F6F0); // --secondary
  static const Color secondaryForeground = Color(0xFF004F3F);
  static const Color muted = Color(0xFFF4F4EF); // --muted
  static const Color mutedForeground = Color(0xFF1A2026); // --muted-foreground
  static const Color accent = Color(0xFFFFF0D4); // --accent
  static const Color accentForeground = Color(0xFF3D2A02);
  static const Color destructive = Color(0xFFE7000B); // --destructive
  static const Color border = Color(0xFFD9DFE5); // --border / --input
  static const Color ring = primary;
  static const Color placeholder = Color(0xFFD5D8DA);

  // ── Status
  static const Color success = Color(0xFF007E68);
  static const Color successMuted = Color(0xFFDAF6EE);
  static const Color warning = Color(0xFFDF9200);
  static const Color warningForeground = Color(0xFF201301);
  static const Color warningMuted = Color(0xFFFFF3D8);
  static const Color info = Color(0xFF006AA5);
  static const Color infoMuted = Color(0xFFDDF2FF);

  // ── Charts (--chart-1 … --chart-5)
  static const Color chart1 = Color(0xFF008C75);
  static const Color chart2 = Color(0xFF006AA5);
  static const Color chart3 = Color(0xFFE39B00);
  static const Color chart4 = Color(0xFF0095AE);
  static const Color chart5 = Color(0xFFE7000B);

  // ── Sidebar (--sidebar-*)
  static const Color sidebar = Color(0xFF01150F);
  static const Color sidebarForeground = Color(0xFFE0EBE7);
  static const Color sidebarPrimary = Color(0xFF56D0AF);
  static const Color sidebarAccent = Color(0xFF08221B);
  static const Color sidebarBorder = Color(0x12FFFFFF); // white 7%

  // ── Ek-i hue er halka/gaar rup (website token er L bodle; app er gradient/chip er jonno)
  static const Color destructiveMuted = Color(0xFFFFE9E5);
  static const Color destructiveLight = Color(0xFFF75E53);
  static const Color destructiveDeep = Color(0xFFA20710);
  static const Color chart4Muted = Color(0xFFDEF5F9);
  static const Color chart4Light = Color(0xFF66CFE1);
  static const Color chart4Deep = Color(0xFF006374);
  static const Color financeLight = Color(0xFF87C6F2);
  static const Color destructiveOnDark = Color(0xFFF8A59B);
  static const Color neutral = Color(0xFF8B9095);

  /// Website er .gradient-brand (135°: brand-600 → brand-400)
  static const LinearGradient gradientBrand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand600, brand400],
  );

  /// Website er .gradient-finance (finance-700 → finance-500)
  static const LinearGradient gradientFinance = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [finance700, finance500],
  );

  /// Website er chart rong (CHART_COLORS)
  static const List<Color> charts = [chart1, chart2, chart3, chart4, chart5];
}