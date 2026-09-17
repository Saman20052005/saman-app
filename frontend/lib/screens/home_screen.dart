// [File: lib/screens/home_screen.dart]
// UI REDESIGN: Monochrome Performance — Light + Dark adaptive
// Logic giữ nguyên 100%, chỉ thay lớp UI

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui' as ui;
import '../config/app_translations.dart';
import '../config/theme_provider.dart';
import '../config/app_theme.dart'; // ← Design token extension
import '../utils/auth_helper.dart';
import 'nutrition/nutrition_screen.dart';
import '../presentation/screens/workout_home_screen.dart';
import 'plan_screen.dart';
import 'login/login_screen.dart';
import 'report_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // ✅ Đã xoá _bgColor / _cardColor hardcode → dùng context extension

  Map<String, String>? _profile;
  bool _isLoading = true;
  Map<String, dynamic>? _weather;
  bool _weatherLoading = true;

  // Carousel state
  late final PageController _carouselController;
  int _carouselPage = 0;

  final List<Map<String, String>> _newsItems = [
    {
      'title': 'Maximizing Hypertrophy: Science-Backed Tips',
      'image':
          'https://lh3.googleusercontent.com/aida-public/AB6AXuAiPZwXXkhrmKjt3mlsW4_PyPPNi1qquSEYDP3t79SO-0j7W4ZGxcQ_ZOLdQdfXqX-BHXTLA2dlViixt0hThHgTkqVFs9vaefU7_Ris9DzvnllLQVlc89BdO_NoB6-UX4JwTNYdLm2P0hSzIIexg7u08OZux4CGtYnmwTjEJTNbIQ427EmIlr6pEwIg20K2C39ODz_3IrPEIcVKF41aMV4BNY2MEePXrsaqrvU1YKS93Q3hye65U2EpGozDkRdDfAirpOitaV1QE44',
    },
    {
      'title': 'Recovery Essentials: Nutrition & Sleep',
      'image':
          'https://lh3.googleusercontent.com/aida-public/AB6AXuA141aziigjFgVJuAvYydU6ZMLc4U3M3xjLa5UnEnJ1V0rmsSMrbSfQ6VxLYK9LLS8196fGWs2VJBw_RCOCFXIqtdRho2e6prPD8fEWPoiXZPmIlSGuFCeJLbL8pIvyv7CKM-YLLFrdACv6FbXuPfVhTEu4h26dqKPSITS8JwIZKl5y1p4rL1ifmoV3-rDqyi3YxegHLodGCikK6_ZZIAwEtYlfMwHTvW0aQMsxCE4MMuY3XKsIQnRXA7QPnItDu1rlWgEPs2M17xg',
    },
    {
      'title': 'Fueling Performance: Pre-Workout Foods',
      'image':
          'https://images.unsplash.com/photo-1514512364185-5d8ef22b7b34?auto=format&fit=crop&w=800&q=60',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadWeather();
    _carouselController = PageController(viewportFraction: 0.84)
      ..addListener(() {
        final page = _carouselController.page?.round() ?? 0;
        if (page != _carouselPage) {
          setState(() => _carouselPage = page);
        }
      });
  }

  @override
  void dispose() {
    _carouselController.dispose();
    super.dispose();
  }

  String tr(String key) {
    final locale = ref.read(languageProvider);
    return AppTranslations.text(key, locale);
  }

  // ─── Logic: giữ nguyên ─────────────────────────────────────────
  Future<void> _loadProfile() async {
    if (!mounted) return;
    final name = await AuthHelper.getUserName();
    final email = await AuthHelper.getUserEmail();
    setState(() {
      _profile = {
        'name': (name != null && name.isNotEmpty)
            ? name
            : (email?.split('@').first ?? 'User'),
        'email': email ?? '',
      };
      _isLoading = false;
    });
  }

  Future<void> _loadWeather() async {
    if (!mounted) return;
    setState(() {
      _weather = null;
      _weatherLoading = false;
    });

    /*
    try {
      const apiKey = '411234dfea313ecbc459850732c591d2';
      final url = Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?q=Ho Chi Minh City,VN&appid=$apiKey&units=metric&lang=vi',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (!mounted) return;
        setState(() {
          _weather = {
            'temp': data['main']['temp'].round(),
            'description': data['weather'][0]['description'],
            'icon': data['weather'][0]['icon'],
            'humidity': data['main']['humidity'],
            'feels_like': data['main']['feels_like'].round(),
          };
          _weatherLoading = false;
        });
      } else {
        throw Exception('API Error');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _weather = {
          'temp': 32,
          'description': 'Nắng nhẹ',
          'icon': '01d',
          'humidity': 70,
          'feels_like': 34,
        };
        _weatherLoading = false;
      });
    }
    */
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          tr('logout'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('logout')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  // ─── Build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    ref.watch(languageProvider);
    ref.watch(themeProvider);

    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: context.bgColor,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : CustomScrollView(
              slivers: [
                _buildHeader(colors),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // News carousel
                SliverToBoxAdapter(
                  child:
                      _buildNewsCarousel(colors).animate().fadeIn(delay: 80.ms),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),

                // Stats (weather + mini cards)
                SliverToBoxAdapter(
                  child: _buildStatsSection(
                    colors,
                  ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.08),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // Calorie chart
                SliverToBoxAdapter(
                  child:
                      _buildCalorieChart(colors).animate().fadeIn(delay: 60.ms),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 18)),

                // Quick access
                SliverToBoxAdapter(
                  child: _buildSectionLabel(tr('quick_access'), colors),
                ),
                SliverToBoxAdapter(
                  child: _buildInteractivePrompts(
                    colors,
                  ).animate().fadeIn(delay: 80.ms),
                ),
                SliverToBoxAdapter(
                  child: _buildQuickActions(
                    colors,
                  ).animate().fadeIn(delay: 140.ms),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // Bento feature grid
                SliverToBoxAdapter(
                  child: _buildSectionLabel(tr('discover'), colors),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  sliver: _buildBentoGrid(colors),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 48)),
              ],
            ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────────
  Widget _buildHeader(ColorScheme colors) {
    return SliverAppBar(
      backgroundColor: context.bgColor,
      expandedHeight: 80,
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        centerTitle: false,
        title: Text(
          '${tr('hello')}, ${_profile!['name']}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
      ),
      actions: [
        _buildHeaderIcon(Icons.notifications_outlined, colors, () {}),
        _buildHeaderIcon(Icons.logout_outlined, colors, _logout),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildHeaderIcon(
    IconData icon,
    ColorScheme colors,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      child: IconButton(
        icon: Icon(icon, color: colors.secondary, size: 22),
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: context.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // ─── Section label ──────────────────────────────────────────────
  Widget _buildSectionLabel(String label, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.secondary,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  // ─── Stats section ──────────────────────────────────────────────
  Widget _buildStatsSection(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Weather card
          _buildWeatherCard(colors),
          const SizedBox(height: 12),
          // Mini stat row
          IntrinsicHeight(
            child: Row(
              children: [
                _buildStatCard(
                  '1,850',
                  'Kcal',
                  Icons.local_fire_department_outlined,
                  colors,
                ),
                const SizedBox(width: 10),
                _buildStatCard(
                  '6,234',
                  tr('steps_label') != '' ? tr('steps_label') : 'Steps',
                  Icons.directions_walk_outlined,
                  colors,
                ),
                const SizedBox(width: 10),
                _buildStatCard(
                  '1.2L',
                  tr('water'),
                  Icons.water_drop_outlined,
                  colors,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherCard(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [context.cardShadow],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _weatherLoading || _weather == null
                    ? '--°'
                    : '${_weather!['temp']}°C',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: colors.onSurface,
                  height: 1,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _weatherLoading || _weather == null
                    ? 'Đang tải...'
                    : (_weather!['description'] as String).toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colors.secondary,
                  letterSpacing: 1.2,
                ),
              ),
              if (!_weatherLoading && _weather != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Cảm giác ${_weather!['feels_like']}° · Độ ẩm ${_weather!['humidity']}%',
                  style: TextStyle(fontSize: 11, color: colors.secondary),
                ),
              ],
            ],
          ),
          if (!_weatherLoading && _weather != null)
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: context.trackColor,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: Image.network(
                  'https://openweathermap.org/img/wn/${_weather!['icon']}@2x.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.wb_sunny_outlined,
                    size: 28,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String value,
    String label,
    IconData icon,
    ColorScheme colors,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [context.softShadow],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: colors.secondary),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: colors.secondary),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Interactive prompts ────────────────────────────────────────
  Widget _buildInteractivePrompts(ColorScheme colors) {
    final prompts = [
      {
        'title': tr('report'),
        'subtitle': 'Weekly Stats',
        'icon': Icons.bar_chart_rounded,
        'action': () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportScreen()),
            ),
      },
      {
        'title': tr('nutrition'),
        'subtitle': tr('what_to_eat'),
        'icon': Icons.restaurant_menu_outlined,
        'action': () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NutritionScreen()),
            ),
      },
      {
        'title': tr('workout'),
        'subtitle': tr('lets_train'),
        'icon': Icons.fitness_center_outlined,
        'action': () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WorkoutHomeScreen()),
            ),
      },
      {
        'title': tr('plans'),
        'subtitle': tr('new_challenge'),
        'icon': Icons.calendar_today_outlined,
        'action': () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreatePlanScreen()),
            ),
      },
    ];

    return SizedBox(
      height: 114,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: prompts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final p = prompts[index];
          return InkWell(
            onTap: p['action'] as VoidCallback,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 130,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [context.softShadow],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(
                    p['icon'] as IconData,
                    color: colors.onSurface,
                    size: 24,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['title'] as String,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: colors.onSurface,
                        ),
                      ),
                      Text(
                        p['subtitle'] as String,
                        style: TextStyle(fontSize: 11, color: colors.secondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Quick actions (pill chips) ─────────────────────────────────
  Widget _buildQuickActions(ColorScheme colors) {
    final actions = [
      {'label': tr('log_meal'), 'icon': Icons.add},
      {'label': tr('start_train'), 'icon': Icons.play_arrow_outlined},
      {'label': tr('water'), 'icon': Icons.water_drop_outlined},
      {'label': tr('note'), 'icon': Icons.edit_outlined},
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final a = actions[index];
          return InkWell(
            onTap: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(tr('coming_soon')))),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: context.trackColor),
              ),
              child: Row(
                children: [
                  Icon(
                    a['icon'] as IconData,
                    size: 16,
                    color: colors.onSurface,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    a['label'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── News Carousel ─────────────────────────────────────────────
  Widget _buildNewsCarousel(ColorScheme colors) {
    return SizedBox(
      height: 180,
      child: Column(
        children: [
          SizedBox(
            height: 140,
            child: PageView.builder(
              controller: _carouselController,
              itemCount: _newsItems.length,
              itemBuilder: (context, index) {
                final item = _newsItems[index];
                return Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 20 : 8,
                    right: index == _newsItems.length - 1 ? 20 : 8,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(item['title']!)),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [context.cardShadow],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              item['image']!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: context.trackColor),
                            ),
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.78),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 14,
                              right: 14,
                              bottom: 14,
                              child: Text(
                                item['title']!,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_newsItems.length, (i) {
              final active = i == _carouselPage;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 8 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color:
                      active ? Colors.white : colors.secondary.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ─── Calorie Chart ──────────────────────────────────────────────
  Widget _buildCalorieChart(ColorScheme colors) {
    final intake = [
      30.0,
      60.0,
      40.0,
      80.0,
      60.0,
      80.0,
      120.0,
      90.0,
      70.0,
      60.0
    ];
    final burn = [20.0, 30.0, 50.0, 40.0, 55.0, 65.0, 80.0, 70.0, 60.0, 50.0];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [context.cardShadow],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header + legend
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Intake vs. Burn',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface)),
                Row(
                  children: [
                    Row(children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('Intake', style: TextStyle(color: colors.secondary))
                    ]),
                    const SizedBox(width: 12),
                    Row(children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('Burn', style: TextStyle(color: colors.secondary))
                    ]),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: CustomPaint(
                painter: _CalorieChartPainter(
                    intake: intake, burn: burn, colors: colors),
                size: const Size(double.infinity, 200),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Bento grid (2x2) ─────────────────────────────────────────
  SliverGrid _buildBentoGrid(ColorScheme colors) {
    final items = [
      {
        'title': 'Workouts',
        'icon': Icons.fitness_center_outlined,
        'lines': ['Active: Full Body Power', 'Next: Leg Day (Tue)'],
        'action': 'Start Workout',
      },
      {
        'title': 'Nutrition Log',
        'icon': Icons.restaurant_outlined,
        'lines': [
          'Calories: 1,850 / 2,500',
          'Protein: 120g',
          'Carbs: 210g',
          'Fat: 55g'
        ],
        'action': 'Log Meal',
      },
      {
        'title': 'Progress Reports',
        'icon': Icons.bar_chart_rounded,
        'lines': ['Weight: -2.5kg this week', 'Body Fat: 18.5%'],
        'action': 'View Report',
      },
      {
        'title': 'My Plans',
        'icon': Icons.calendar_month_outlined,
        'lines': ['Current: 4-Week Shred', 'Week 2/4'],
        'action': 'Manage Plans',
      },
    ];

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      delegate: SliverChildBuilderDelegate((context, index) {
        final item = items[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [context.softShadow],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(item['icon'] as IconData,
                      size: 16, color: colors.secondary),
                  const SizedBox(width: 8),
                  Text(item['title'] as String,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: colors.secondary)),
                ],
              ),
              const SizedBox(height: 8),
              ...((item['lines'] as List<String>).map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(l,
                      style:
                          TextStyle(color: colors.onSurface, fontSize: 13))))),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(item['action'] as String))),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: context.trackColor.withOpacity(0.02),
                    side: BorderSide(color: context.trackColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(item['action'] as String,
                      style: TextStyle(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        );
      }, childCount: items.length),
    );
  }
}

// Top-level painter (must be top-level for Dart)
class _CalorieChartPainter extends CustomPainter {
  final List<double> intake;
  final List<double> burn;
  final ColorScheme colors;
  _CalorieChartPainter(
      {required this.intake, required this.burn, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final left = 44.0;
    final top = 8.0;
    final bottom = 28.0;
    final width = size.width - left - 8;
    final height = size.height - top - bottom;

    // grid lines
    final gridPaint = Paint()
      ..color = colors.secondary.withOpacity(0.12)
      ..strokeWidth = 1;
    const gridCount = 4;
    for (int i = 0; i <= gridCount; i++) {
      final y = top + i * (height / gridCount);
      canvas.drawLine(Offset(left, y), Offset(left + width, y), gridPaint);
    }

    // compute max
    double maxVal = 1;
    for (final v in intake) if (v > maxVal) maxVal = v;
    for (final v in burn) if (v > maxVal) maxVal = v;
    maxVal = (maxVal * 1.25).ceilToDouble();

    List<Offset> mapPoints(List<double> data) {
      final n = data.length;
      if (n == 0) return [];
      return List.generate(n, (i) {
        final x = left + (i / (n - 1)) * width;
        final y = top + (1 - (data[i] / maxVal)) * height;
        return Offset(x, y);
      });
    }

    final intakePts = mapPoints(intake);
    final burnPts = mapPoints(burn);

    // intake area
    final intakePath = Path();
    for (var i = 0; i < intakePts.length; i++) {
      if (i == 0)
        intakePath.moveTo(intakePts[i].dx, intakePts[i].dy);
      else
        intakePath.lineTo(intakePts[i].dx, intakePts[i].dy);
    }
    final area = Path.from(intakePath)
      ..lineTo(left + width, top + height)
      ..lineTo(left, top + height)
      ..close();

    final grad = ui.Gradient.linear(Offset(0, top), Offset(0, top + height), [
      const Color(0xFF10B981).withOpacity(0.28),
      const Color(0xFF10B981).withOpacity(0.0)
    ]);
    final areaPaint = Paint()..shader = grad;
    canvas.drawPath(area, areaPaint);

    // intake stroke with glow
    final glowPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(intakePath, glowPaint);

    final intakeStroke = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(intakePath, intakeStroke);

    // burn stroke
    final burnPath = Path();
    for (var i = 0; i < burnPts.length; i++) {
      if (i == 0)
        burnPath.moveTo(burnPts[i].dx, burnPts[i].dy);
      else
        burnPath.lineTo(burnPts[i].dx, burnPts[i].dy);
    }
    final burnPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(burnPath, burnPaint);

    // points
    final pointWhite = Paint()..color = Colors.white;
    final pointGreen = Paint()..color = const Color(0xFF10B981);
    for (final p in burnPts) canvas.drawCircle(p, 3, pointWhite);
    for (final p in intakePts) canvas.drawCircle(p, 3, pointGreen);

    // left axis labels
    final labels = ['200 kCal', '150 kCal', '100 kCal', '50 kCal', 'kCal'];
    final textStyle = TextStyle(color: colors.secondary, fontSize: 10);
    for (var i = 0; i < labels.length; i++) {
      final y = top + i * (height / (labels.length - 1));
      final tp = TextPainter(
          text: TextSpan(text: labels[i], style: textStyle),
          textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(4, y - tp.height / 2));
    }

    // x axis labels
    final xLabels = ['00:00', '06:00', '12:00', '18:00', '23:59'];
    for (var i = 0; i < xLabels.length; i++) {
      final x = left + (i / (xLabels.length - 1)) * width;
      final tp = TextPainter(
          text: TextSpan(text: xLabels[i], style: textStyle),
          textDirection: TextDirection.ltr);
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, top + height + 6));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
