import 'package:flutter/material.dart';

// ==================== COLOR SYSTEM ====================
// Chỉ sử dụng các màu dưới đây, không thêm bất kỳ màu nào khác.
const Color kBgPrimary = Color(0xFF0B0B0C); // Nền chính
const Color kBgCard = Color(0xFF141416); // Card lớn
const Color kBgCardSub = Color(0xFF1C1C20); // Card phụ
const Color kBorder = Color(0xFF2A2A2F); // Viền, divider
const Color kTextPrimary = Color(0xFFF5F5F5); // Chữ chính
const Color kTextSecondary = Color(0xFFA1A1AA); // Chữ phụ
const Color kHighlight = Color(0xFFFFFFFF); // Highlight, accent (trắng thuần)

// ==================== TYPOGRAPHY ====================
// Số liệu lớn (calories target, weight)
const TextStyle kNumberLarge = TextStyle(
  fontSize: 48,
  fontWeight: FontWeight.w700,
  color: kTextPrimary,
  letterSpacing: -1.5,
);

// Nhãn phụ (đơn vị, label)
const TextStyle kLabelSmall = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  color: kTextSecondary,
  letterSpacing: 0.8,
);

// Title section
const TextStyle kTitleSection = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
  color: kTextPrimary,
);

// Body text
const TextStyle kBodyText = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w400,
  color: kTextSecondary,
);

// ==================== SHADOWS ====================
const List<BoxShadow> kCardShadow = [
  BoxShadow(
    color: Colors.black54,
    blurRadius: 20,
    offset: Offset(0, 8),
  ),
];

// ==================== THEME DATA ====================
// Tạo ThemeData để sử dụng xuyên suốt app (tuỳ chọn, có thể dùng trực tiếp các hằng)
final ThemeData monochromeTheme = ThemeData.dark().copyWith(
  scaffoldBackgroundColor: kBgPrimary,
  cardColor: kBgCard,
  dividerColor: kBorder,
  primaryColor: kHighlight,
  colorScheme: const ColorScheme.dark(
    primary: kHighlight,
    onPrimary: kBgPrimary,
    surface: kBgCard,
    onSurface: kTextPrimary,
    background: kBgPrimary,
    onBackground: kTextPrimary,
    secondary: kBgCardSub,
    onSecondary: kTextSecondary,
  ),
  textTheme: const TextTheme(
    displayLarge: kNumberLarge,
    titleMedium: kTitleSection,
    bodyMedium: kBodyText,
    labelSmall: kLabelSmall,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: kBgPrimary,
    elevation: 0,
    titleTextStyle: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: kTextPrimary,
    ),
    iconTheme: IconThemeData(color: kTextPrimary),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: kBgCard,
    selectedItemColor: kTextPrimary,
    unselectedItemColor: kTextSecondary,
    type: BottomNavigationBarType.fixed,
    elevation: 0,
  ),
);
