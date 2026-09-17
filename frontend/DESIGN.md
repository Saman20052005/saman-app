# Design System - Flutter Health AI App

> Export từ Stitch - Design System Documentation for AI Code Generation
> File này giúp AI (Copilot/WX) hiểu design system để generate code Flutter chính xác

## 1. Color System

### Primary Colors
```dart
// Primary Palette
static const Color primary50 = Color(0xFFE8F5E9);
static const Color primary100 = Color(0xFFC8E6C9);
static const Color primary200 = Color(0xFFA5D6A7);
static const Color primary300 = Color(0xFF81C784);
static const Color primary400 = Color(0xFF66BB6A);
static const Color primary500 = Color(0xFF4CAF50);  // Main Primary
static const Color primary600 = Color(0xFF43A047);
static const Color primary700 = Color(0xFF388E3C);
static const Color primary800 = Color(0xFF2E7D32);
static const Color primary900 = Color(0xFF1B5E20);
```

### Secondary Colors
```dart
// Secondary (Accent) Palette
static const Color secondary50 = Color(0xFFFFF3E0);
static const Color secondary100 = Color(0xFFFFE0B2);
static const Color secondary200 = Color(0xFFFFCC80);
static const Color secondary300 = Color(0xFFFFB74D);
static const Color secondary400 = Color(0xFFFFA726);
static const Color secondary500 = Color(0xFFFF9800);  // Main Secondary
static const Color secondary600 = Color(0xFFFB8C00);
static const Color secondary700 = Color(0xFFF57C00);
static const Color secondary800 = Color(0xFFEF6C00);
static const Color secondary900 = Color(0xFFE65100);
```

### Semantic Colors
```dart
// Semantic Colors
static const Color success = Color(0xFF4CAF50);
static const Color warning = Color(0xFFFF9800);
static const Color error = Color(0xFFE53935);
static const Color info = Color(0xFF2196F3);

// Neutral Colors
static const Color neutral0 = Color(0xFFFFFFFF);
static const Color neutral50 = Color(0xFFFAFAFA);
static const Color neutral100 = Color(0xFFF5F5F5);
static const Color neutral200 = Color(0xFFEEEEEE);
static const Color neutral300 = Color(0xFFE0E0E0);
static const Color neutral400 = Color(0xFFBDBDBD);
static const Color neutral500 = Color(0xFF9E9E9E);
static const Color neutral600 = Color(0xFF757575);
static const Color neutral700 = Color(0xFF616161);
static const Color neutral800 = Color(0xFF424242);
static const Color neutral900 = Color(0xFF212121);
```

### Background Colors
```dart
// Background Colors
static const Color backgroundPrimary = Color(0xFFFFFFFF);
static const Color backgroundSecondary = Color(0xFFF5F5F5);
static const Color backgroundTertiary = Color(0xFFEEEEEE);
static const Color surfaceLight = Color(0xFFFFFFFF);
static const Color surfaceDark = Color(0xFF212121);
```

## 2. Typography System

### Font Family
```dart
// Primary Font
static const String fontPrimary = 'Roboto';
static const String fontSecondary = 'Inter';
```

### Text Styles
```dart
// Display Styles
static const TextStyle displayLarge = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 57,
  fontWeight: FontWeight.w400,
  letterSpacing: -0.25,
  height: 1.12,
);

static const TextStyle displayMedium = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 45,
  fontWeight: FontWeight.w400,
  letterSpacing: 0,
  height: 1.16,
);

static const TextStyle displaySmall = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 36,
  fontWeight: FontWeight.w400,
  letterSpacing: 0,
  height: 1.22,
);

// Headline Styles
static const TextStyle headlineLarge = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 32,
  fontWeight: FontWeight.w400,
  letterSpacing: 0,
  height: 1.25,
);

static const TextStyle headlineMedium = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 28,
  fontWeight: FontWeight.w400,
  letterSpacing: 0,
  height: 1.29,
);

static const TextStyle headlineSmall = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 24,
  fontWeight: FontWeight.w400,
  letterSpacing: 0,
  height: 1.33,
);

// Title Styles
static const TextStyle titleLarge = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 22,
  fontWeight: FontWeight.w400,
  letterSpacing: 0,
  height: 1.27,
);

static const TextStyle titleMedium = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 16,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.15,
  height: 1.50,
);

static const TextStyle titleSmall = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 14,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.1,
  height: 1.43,
);

// Body Styles
static const TextStyle bodyLarge = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 16,
  fontWeight: FontWeight.w400,
  letterSpacing: 0.5,
  height: 1.50,
);

static const TextStyle bodyMedium = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 14,
  fontWeight: FontWeight.w400,
  letterSpacing: 0.25,
  height: 1.43,
);

static const TextStyle bodySmall = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 12,
  fontWeight: FontWeight.w400,
  letterSpacing: 0.4,
  height: 1.33,
);

// Label Styles
static const TextStyle labelLarge = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 14,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.1,
  height: 1.43,
);

static const TextStyle labelMedium = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 12,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.5,
  height: 1.33,
);

static const TextStyle labelSmall = TextStyle(
  fontFamily: 'Roboto',
  fontSize: 11,
  fontWeight: FontWeight.w500,
  letterSpacing: 0.5,
  height: 1.45,
);
```

## 3. Spacing System

### Spacing Scale (8px base)
```dart
// Spacing Constants (based on 8px grid)
static const double spacing0 = 0;
static const double spacing1 = 4;    // 0.5 * 8
static const double spacing2 = 8;    // 1 * 8
static const double spacing3 = 12;   // 1.5 * 8
static const double spacing4 = 16;   // 2 * 8
static const double spacing5 = 24;   // 3 * 8
static const double spacing6 = 32;   // 4 * 8
static const double spacing7 = 40;   // 5 * 8
static const double spacing8 = 48;   // 6 * 8
static const double spacing9 = 64;   // 8 * 8
static const double spacing10 = 80;   // 10 * 8
static const double spacing11 = 96;   // 12 * 8
static const double spacing12 = 120;  // 15 * 8
```

### Common Layout Spacing
```dart
// Page Padding
static const double pagePaddingHorizontal = 16;
static const double pagePaddingVertical = 24;

// Section Spacing
static const double sectionSpacing = 24;
static const double subsectionSpacing = 16;
static const double elementSpacing = 12;
static const double tightSpacing = 8;
```

## 4. Component Tokens

### Border Radius
```dart
// Border Radius Scale
static const double radiusNone = 0;
static const double radiusSmall = 4;
static const double radiusMedium = 8;
static const double radiusLarge = 12;
static const double radiusXLarge = 16;
static const double radius2XLarge = 24;
static const double radiusFull = 9999;  // Circular
```

### Elevations (Shadows)
```dart
// Elevation 0
static const List<BoxShadow> elevation0 = [];

// Elevation 1
static const List<BoxShadow> elevation1 = [
  BoxShadow(
    color: Color(0x1F000000),
    offset: Offset(0, 1),
    blurRadius: 3,
  ),
  BoxShadow(
    color: Color(0x24000000),
    offset: Offset(0, 1),
    blurRadius: 1,
  ),
];

// Elevation 2
static const List<BoxShadow> elevation2 = [
  BoxShadow(
    color: Color(0x1F000000),
    offset: Offset(0, 2),
    blurRadius: 4,
  ),
  BoxShadow(
    color: Color(0x24000000),
    offset: Offset(0, 1),
    blurRadius: 2,
  ),
];

// Elevation 3
static const List<BoxShadow> elevation3 = [
  BoxShadow(
    color: Color(0x1F000000),
    offset: Offset(0, 4),
    blurRadius: 8,
  ),
  BoxShadow(
    color: Color(0x24000000),
    offset: Offset(0, 1),
    blurRadius: 3,
  ),
];
```

### Button Styles
```dart
// Primary Button
static final ButtonStyle primaryButton = ElevatedButton.styleFrom(
  backgroundColor: primary500,
  foregroundColor: neutral0,
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  textStyle: labelLarge,
);

// Secondary Button
static final ButtonStyle secondaryButton = ElevatedButton.styleFrom(
  backgroundColor: secondary500,
  foregroundColor: neutral0,
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  textStyle: labelLarge,
);

// Outlined Button
static final ButtonStyle outlinedButton = OutlinedButton.styleFrom(
  foregroundColor: primary500,
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  side: const BorderSide(color: primary500, width: 1),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  textStyle: labelLarge,
);

// Text Button
static final ButtonStyle textButton = TextButton.styleFrom(
  foregroundColor: primary500,
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  textStyle: labelLarge,
);
```

### Input Field Styles
```dart
// Text Field Decoration
static InputDecoration textFieldDecoration({String? hint, String? label}) {
  return InputDecoration(
    hintText: hint,
    labelText: label,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: neutral300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: neutral300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: primary500, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: error, width: 1),
    ),
    filled: true,
    fillColor: neutral50,
  );
}
```

## 5. Layout Guidelines

### Screen Breakpoints
```dart
// Responsive Breakpoints
static const double mobileBreakpoint = 0;
static const double tabletBreakpoint = 600;
static const double desktopBreakpoint = 1024;
static const double wideDesktopBreakpoint = 1440;
```

### Container Widths
```dart
// Max Content Widths
static const double contentMaxWidth = 1200;
static const double formMaxWidth = 480;
static const double cardMaxWidth = 360;
```

### Grid System
```dart
// Grid Configuration
static const int gridColumnsMobile = 4;
static const int gridColumnsTablet = 8;
static const int gridColumnsDesktop = 12;
static const double gridGutter = 16;
static const double gridMargin = 16;
```

## 6. Animation & Motion

### Duration Tokens
```dart
// Animation Durations
static const Duration durationInstant = Duration(milliseconds: 0);
static const Duration durationFast = Duration(milliseconds: 100);
static const Duration durationNormal = Duration(milliseconds: 200);
static const Duration durationSlow = Duration(milliseconds: 300);
static const Duration durationSlower = Duration(milliseconds: 400);
static const Duration durationSlowest = Duration(milliseconds: 500);
```

### Easing Curves
```dart
// Standard Easings
static const Curve easeStandard = Curves.easeInOut;
static const Curve easeDecelerate = Curves.decelerate;
static const Curve easeAccelerate = Curves.easeIn;
static const Curve easeSharp = Curves.easeInOutCubic;
static const Curve easeBounce = Curves.elasticOut;
```

## 7. Icon System

### Icon Sizes
```dart
// Icon Size Scale
static const double iconXS = 12;
static const double iconSM = 16;
static const double iconMD = 24;
static const double iconLG = 32;
static const double iconXL = 48;
static const double icon2XL = 64;
```

### Icon Colors
```dart
// Default Icon Colors
static const Color iconPrimary = neutral800;
static const Color iconSecondary = neutral500;
static const Color iconDisabled = neutral400;
static const Color iconInverse = neutral0;
static const Color iconAccent = primary500;
```

## 8. AI Code Generation Rules

### Naming Conventions
```
- Widgets: PascalCase (e.g., PrimaryButton, UserProfileCard)
- Files: snake_case (e.g., primary_button.dart, user_profile_card.dart)
- Constants: lowerCamelCase (e.g., primaryColor, defaultPadding)
- Private members: _prefix (e.g., _internalState, _buildHeader)
```

### Component Structure
```dart
// Mẫu cấu trúc Widget chuẩn
class ComponentName extends StatelessWidget {
  final Type property1;
  final Type? optionalProperty;
  
  const ComponentName({
    super.key,
    required this.property1,
    this.optionalProperty,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // Sử dụng tokens từ AppTheme
      padding: const EdgeInsets.all(AppTheme.spacing4),
      decoration: BoxDecoration(
        color: AppTheme.backgroundPrimary,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: AppTheme.elevation1,
      ),
      child: // ...
    );
  }
}
```

### Theme Usage
```dart
// Luôn lấy theme từ context hoặc AppTheme singleton
final theme = Theme.of(context);
final colorScheme = theme.colorScheme;
final textTheme = theme.textTheme;

// Hoặc sử dụng trực tiếp từ Design Tokens
final primaryColor = AppTheme.primary500;
final titleStyle = AppTheme.titleLarge;
```

## 9. Export Notes

- File này được export từ Stitch Design System
- Cập nhật: $(date)
- Version: 1.0.0
- Sync với: Figma File [link]

## 10. AI Instructions

Khi generate code Flutter, AI cần:
1. **Sử dụng design tokens** từ file này, không hardcode giá trị
2. **Tuân thủ naming convention** đã định nghĩa
3. **Áp dụng spacing system** (8px grid)
4. **Sử dụng typography scale** đúng context (title, body, label)
5. **Áp dụng color system** - semantic colors cho trạng thái, primary cho CTA
6. **Tạo responsive UI** theo breakpoints
7. **Thêm animation** với duration và easing tokens
8. **Comment giải thích** khi sử dụng token không phổ biến
