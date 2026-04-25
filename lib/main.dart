import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
// import 'data/mock_data.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'models/menu_item.dart';
import 'models/category.dart';
import 'services/cart_provider.dart';
import 'models/cart_item.dart';
import 'admin/admin_app.dart' as admin;
import 'guest/delivery_screen.dart';
import 'services/settings_service.dart';
import 'services/menu_data_service.dart';
import 'services/favorites_provider.dart';
import 'services/telegram_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:js' as js;

List<Category> get categories {
  // Получаем список из базы и убираем оттуда категорию с id '0', если она там есть
  final dbCats = MenuDataService.categories.where((c) => c.id != '0').toList();
  
  // Всегда добавляем нашу виртуальную категорию "Все блюда" в начало
  return [
    Category(id: '0', title: 'Все блюда', emoji: '🍽️'),
    ...dbCats,
  ];
}
List<MenuItem> get menuItems => MenuDataService.items;

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Инициализация Supabase (ТЕПЕРЬ С AWAIT, чтобы избежать краша при перезагрузке)
    try {
      await Supabase.initialize(
        url: 'https://vgzdpbwcenckmjtgfvfw.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZnemRwYndjZW5ja21qdGdmdmZ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY2NDkxODAsImV4cCI6MjA5MjIyNTE4MH0.pFmPP9A9Tov4b6URS-LP5b3lYyB0fVXTKDvLY_MR120',
      );
    } catch (e) {
      debugPrint('Supabase init error: $e');
    }

    // Фоновая загрузка данных
    SettingsService.load();
    MenuDataService.load();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarBrightness: Brightness.dark,
      ),
    );
    
    final params = Uri.base.queryParameters;
    final String tableId = params['table'] ?? '1';
    final bool isDeliveryMode = !params.containsKey('table');

    if (params.containsKey('admin')) {
      runApp(const admin.AdminApp());
    } else {
      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => CartProvider(tableId: tableId)),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
          ],
          child: MenuApp(isDeliveryMode: isDeliveryMode, tableId: tableId),
        ),
      );
    }
  }, (error, stack) {
    debugPrint('GLOBAL ERROR: $error');
    debugPrint('STACK: $stack');
  });
}


class MenuApp extends StatelessWidget {
  final bool isDeliveryMode;
  final String tableId;
  const MenuApp({super.key, this.isDeliveryMode = false, required this.tableId});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Каркыра — Ресторан',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scrollBehavior: AppScrollBehavior(),
      home: MenuHomeScreen(isDeliveryMode: isDeliveryMode, tableId: tableId),
    );
  }
}

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class MenuHomeScreen extends StatefulWidget {
  final bool isDeliveryMode;
  final String tableId;
  const MenuHomeScreen({super.key, this.isDeliveryMode = false, required this.tableId});

  @override
  State<MenuHomeScreen> createState() => _MenuHomeScreenState();
}

class _MenuHomeScreenState extends State<MenuHomeScreen> {
  String selectedCategoryId = '0'; 
  String? activeQuickFilter; // To track Top, New, etc.
  final ScrollController _categoryScrollController = ScrollController();
  List<Map<String, String>> _banners = [];
  final Map<int, VideoPlayerController> _videoControllers = {};
  final PageController _bannerPageController = PageController();
  int _currentVideoIndex = 0;
  bool _isMuted = true;
  Timer? _imageTimer;
  RealtimeChannel? _waiterCallChannel;
  bool _isMenuLoading = false; // Отключаем экран загрузки навсегда
  bool _isWaiterComing = false;

  // _videoAssets list removed since we use dynamic bannerUrl

  @override
  void initState() {
    super.initState();
    _loadMenuData();
  }

  Future<void> _loadMenuData() async {
    try {
      // Ставим таймаут, чтобы не висеть вечно если интернет плохой
      await MenuDataService.load().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('LOAD MENU ERROR: $e');
    } finally {
      if (mounted) {
        _banners = MenuDataService.banners;
        debugPrint('BANNER DEBUG: Loaded ${_banners.length} banners from service');
        for(var b in _banners) debugPrint('  - Banner: ${b['type']} | URL: ${b['url']}');
        
        _initializeVideos();
        _startCurrentMedia();
        setState(() => _isMenuLoading = false);
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _askUserName();
        });
      }
    }
  }

  void _initializeVideos() {
    debugPrint('BANNER DEBUG: Starting _initializeVideos. Banners empty? ${_banners.isEmpty}');
    if (_banners.isEmpty) return;
    
    // Инициализируем только текущее и следующее видео для экономии ресурсов
    final indicesToInit = {
      _currentVideoIndex,
      if (_banners.length > 1) (_currentVideoIndex + 1) % _banners.length
    };

    for (var i in indicesToInit) {
      if (_videoControllers.containsKey(i)) continue; // Уже инициализировано
      
      final banner = _banners[i];
      if (banner['type'] == 'video') {
        final url = banner['url']!;
        final controller = url.startsWith('assets/')
            ? VideoPlayerController.asset(url)
            : VideoPlayerController.networkUrl(Uri.parse(url));
            
        _videoControllers[i] = controller;
        
        controller.initialize().then((_) {
          debugPrint('BANNER DEBUG: Video initialized successfully: $url');
          controller.setLooping(false);
          controller.setVolume(_isMuted ? 0 : 1.0);
          
          if (mounted) {
            setState(() {}); 
            if (i == _currentVideoIndex) {
              debugPrint('BANNER DEBUG: Starting initial play for index $i');
              controller.play();
              // Повторная попытка для надежности на случай блокировки браузером
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted && !controller.value.isPlaying && i == _currentVideoIndex) {
                  debugPrint('BANNER DEBUG: Autoplay blocked? Retrying play for index $i');
                  controller.play();
                }
              });
            }
          }
          
          controller.addListener(() {
            if (_currentVideoIndex == i && mounted) {
              final pos = controller.value.position;
              final dur = controller.value.duration;
              if (pos >= dur && dur > Duration.zero && !controller.value.isPlaying) {
                debugPrint('BANNER DEBUG: Video finished at index $i, moving to next');
                _playNextVideo();
              }
            }
          });
        }).catchError((e) {
          debugPrint('BANNER DEBUG: ERROR initializing video $url: $e');
        });
      } else {
        debugPrint('BANNER DEBUG: Index $i is an image, skipping video init');
      }
    }
  }

  void _startCurrentMedia() {
    _imageTimer?.cancel();
    debugPrint('BANNER DEBUG: _startCurrentMedia called for index $_currentVideoIndex');
    if (_banners.isEmpty) {
      debugPrint('BANNER DEBUG: _banners list is empty, nothing to start');
      return;
    }
    
    final current = _banners[_currentVideoIndex];
    debugPrint('BANNER DEBUG: Current media type: ${current['type']}');
    
    if (current['type'] == 'video') {
      final controller = _videoControllers[_currentVideoIndex];
      if (controller != null) {
        debugPrint('BANNER DEBUG: Playing video controller at index $_currentVideoIndex');
        controller.seekTo(Duration.zero);
        controller.play();
      } else {
        debugPrint('BANNER DEBUG: WARNING! Controller for index $_currentVideoIndex is NULL');
      }
    } else {
      // Это изображение, ждем 5 секунд и переключаем
      _imageTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) _playNextVideo();
      });
    }
  }

  void _playNextVideo() {
    if (_banners.isEmpty) return;
    
    int nextIndex = (_currentVideoIndex + 1) % _banners.length;
    _bannerPageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOutCubic,
    );
  }

  void _onBannerChanged(int index) {
    if (_banners.isEmpty) return;
    _imageTimer?.cancel();
    
    // Останавливаем предыдущее видео
    final prevController = _videoControllers[_currentVideoIndex];
    if (prevController != null) {
      prevController.pause();
    }
    
    setState(() {
      _currentVideoIndex = index;
    });
    
    // Подгружаем видео для текущего и следующего слайда
    _initializeVideos();
    
    // Запускаем новое медиа (видео или таймер фото)
    _startCurrentMedia();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _videoControllers.forEach((_, controller) {
        controller.setVolume(_isMuted ? 0 : 1.0);
      });
    });
  }

  @override
  void dispose() {
    _imageTimer?.cancel();
    _waiterCallChannel?.unsubscribe();
    _videoControllers.forEach((_, controller) => controller.dispose());
    _categoryScrollController.dispose();
    _bannerPageController.dispose();
    super.dispose();
  }

  void _askUserName() async {
    // Ждем секунду, чтобы CartProvider успел загрузить имя из SharedPreferences
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final cart = Provider.of<CartProvider>(context, listen: false);
    
    // Если имя уже есть в памяти — ничего не показываем
    if (cart.userName != null && cart.userName!.isNotEmpty) return;

    if (!mounted) return;
    
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: Dialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A043).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_outline_rounded, color: Color(0xFFD4A043), size: 32),
                ),
                const SizedBox(height: 24),
                Text(
                  "ДОБРО ПОЖАЛОВАТЬ",
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Как нам к вам обращаться?",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: GoogleFonts.outfit(color: Colors.white),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: "Ваше имя",
                    hintStyle: GoogleFonts.outfit(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final name = controller.text.trim();
                      if (name.length >= 2) {
                        cart.setUserName(name);
                        Navigator.pop(ctx);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A043),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: Text(
                      "НАЧАТЬ",
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onCategorySelected(int index, String categoryId) {
    if (index < 0 || index >= categories.length) return;
    setState(() {
      selectedCategoryId = categoryId;
      activeQuickFilter = null; // Clear quick filter when specific category is clicked
    });
    
    // Spring centering logic
    if (_categoryScrollController.hasClients) {
      // Estimate centering - about 130 per item including padding
      double targetOffset = (index * 135.0) - (MediaQuery.of(context).size.width / 2) + 65;
      
      // Clamp to scroll bounds
      targetOffset = targetOffset.clamp(
        0.0, 
        _categoryScrollController.position.maxScrollExtent
      );

      _categoryScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutBack, // This gives the "spring" effect
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;
    
    return Scaffold(
      backgroundColor: Colors.grey.shade50, // Светлый фон, чуть темнее белого
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
          child: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  _buildAppBar(),
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _buildBanner(),
                        // Используем отрицательный отступ, чтобы блок "наехал" на баннер и скрыл стык
                        Transform.translate(
                          offset: const Offset(0, -2),
                          child: _buildQuickCategories(),
                        ),
                      ],
                    ),
                  ),
                  _buildCategoryTabs(),
                  _buildMenuGrid(),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
                ],
              ),
              Positioned(
                top: 80, // Matches toolbarHeight of SliverAppBar
                left: 0,
                right: 0,
                height: 40,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _HeaderCurvePainter(),
                  ),
                ),
              ),
              if (_isWaiterComing) _buildWaiterPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaiterPanel() {
    return Positioned(
      top: 100,
      left: 20,
      right: 20,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, (1 - value) * -50),
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))
                  ],
                  border: Border.all(color: const Color(0xFFD4A043).withOpacity(0.3), width: 1),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
                      child: const Icon(Icons.check_circle, color: Colors.green, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Официант в пути!',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black),
                          ),
                          Text(
                            'Пожалуйста, ожидайте, он скоро будет у вас.',
                            style: GoogleFonts.outfit(color: Colors.black87, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                      onPressed: () => setState(() => _isWaiterComing = false),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: Colors.black,
      elevation: 0,
      centerTitle: true,
      toolbarHeight: 80,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Center(
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white54, width: 1.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TableBookingScreen()),
              ),
              child: const Icon(Icons.event_seat_rounded, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 24),
              Text(
                'КАРКЫРА',
                style: GoogleFonts.forum(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 6.0,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Color(0xFF2196F3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 8),
              ),
            ],
          ),
          const SizedBox(height: 0),
          Text(
            'РЕСТО-ЧАЙКАНА',
            textAlign: TextAlign.center,
            style: GoogleFonts.oswald(
              color: Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 4.0,
            ),
          ),
        ],
      ),
      actions: [
        if (!widget.isDeliveryMode)
          IconButton(
            onPressed: () async {
              try {
                // 1. Отправляем в базу
                final res = await Supabase.instance.client.from('waiter_calls').insert({
                  'table_id': widget.tableId,
                  'status': 'pending',
                }).select().single();

                final callId = res['id'];

                // 2. Подписываемся на ответ официанта
                _waiterCallChannel?.unsubscribe();
                _waiterCallChannel = Supabase.instance.client
                    .channel('waiter_response_$callId')
                    .onPostgresChanges(
                      event: PostgresChangeEvent.update,
                      schema: 'public',
                      table: 'waiter_calls',
                      filter: PostgresChangeFilter(
                        type: PostgresChangeFilterType.eq,
                        column: 'id',
                        value: callId,
                      ),
                      callback: (payload) {
                        final newStatus = payload.newRecord['status'];
                        if (newStatus == 'accepted' && mounted) {
                          setState(() => _isWaiterComing = true);
                          
                          // Звук (через системный клик + JS beep для веба)
                          SystemSound.play(SystemSoundType.click);
                          if (kIsWeb) {
                            try {
                              js.context.callMethod('eval', ["new Audio('https://assets.mixkit.io/active_storage/sfx/2568/2568-preview.mp3').play()"]);
                            } catch (_) {}
                          }
                          
                          _waiterCallChannel?.unsubscribe();
                        }
                      },
                    );
                _waiterCallChannel?.subscribe();

                if (SettingsService.telegramNotify) {
                  await TelegramService.notifyWaiterCall(tableId: widget.tableId);
                }
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Официант вызван к столу №${widget.tableId}'),
                      backgroundColor: const Color(0xFFD4A043),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Call error: $e');
              }
            },
            icon: const Icon(Icons.notifications_active_rounded, color: Color(0xFFD4A043)),
            tooltip: 'Вызвать официанта',
          ),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Consumer<CartProvider>(
              builder: (context, cart, child) {
                final isDelivery = widget.isDeliveryMode;
                
                if (isDelivery) {
                  // Режим доставки — показываем кнопку "Заказать"
                  return GestureDetector(
                    onTap: cart.totalItems == 0 ? null : () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const DeliveryScreen(),
                      );
                    },
                    child: AnimatedOpacity(
                      opacity: cart.totalItems > 0 ? 1.0 : 0.4,
                      duration: const Duration(milliseconds: 200),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.topRight,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24, width: 1),
                            ),
                            child: const Icon(Icons.local_taxi_rounded, color: Colors.white, size: 22),
                          ),
                          if (cart.totalItems > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF6D3F),
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                child: Text(
                                  '${cart.totalItems}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }

                // Обычный режим — иконка корзины
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SharedCartScreen(tableNumber: Provider.of<CartProvider>(context, listen: false).tableId),
                      ),
                    );
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topRight,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 22),
                      ),
                      if (cart.totalItems > 0)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF6D3F),
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            child: Text(
                              '${cart.totalItems}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBanner() {
    final screenHeight = MediaQuery.of(context).size.height;
    return VisibilityDetector(
      key: const Key('main_banner_detector'),
      onVisibilityChanged: (info) {
        if (_banners.isNotEmpty) {
          final current = _banners[_currentVideoIndex];
          if (current['type'] == 'video') {
            final controller = _videoControllers[_currentVideoIndex];
            if (controller != null && controller.value.isInitialized) {
              if (info.visibleFraction == 0) {
                controller.pause();
              } else {
                controller.play();
              }
            }
          }
        }
      },
      child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12), 
      height: screenHeight * 0.55, 
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(40),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Media Carousel
          _banners.isEmpty
              ? Container(color: Colors.grey.shade200)
              : PageView.builder(
                  controller: _bannerPageController,
                  onPageChanged: _onBannerChanged,
                  itemCount: _banners.length,
                  itemBuilder: (context, index) {
                    final banner = _banners[index];
                    if (banner['type'] == 'video') {
                      final controller = _videoControllers[index];
                      if (controller == null || !controller.value.isInitialized) {
                        return _buildBannerPlaceholder(banner);
                      }
                      return IgnorePointer(
                        ignoring: true,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: controller.value.size.width,
                            height: controller.value.size.height,
                            child: VideoPlayer(controller),
                          ),
                        ),
                      );
                    } else {
                      // Изображение
                      return Image.network(
                        banner['url']!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      );
                    }
                  },
                ),
          // Ultra-soft gradient overlay
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.2),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.05),
                      Colors.black.withOpacity(0.15),
                    ],
                    stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Pagination Dots
          if (_banners.length > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_banners.length, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentVideoIndex == index ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _currentVideoIndex == index 
                          ? const Color(0xFFD4A043) 
                          : Colors.white.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          // Sound Toggle Button
          if (_banners.isNotEmpty && _banners[_currentVideoIndex]['type'] == 'video')
            Positioned(
              bottom: 20,
              right: 20,
              child: GestureDetector(
                onTap: _toggleMute,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white12, width: 1),
                  ),
                  child: Icon(
                    _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
        ],
      ),
    ));
  }

  Widget _buildQuickCategories() {
    final quickCats = [
      {'id': 'favorites', 'title': 'Избранное', 'icon': Icons.favorite_rounded, 'colors': [const Color(0xFFFF5252), const Color(0xFFD50000)]},
      {'id': 'top', 'title': 'Топ', 'icon': Icons.whatshot_rounded, 'colors': [const Color(0xFFFF8C00), const Color(0xFFFF4500)]},
      {'id': 'new', 'title': 'Новинки', 'icon': Icons.auto_awesome_rounded, 'colors': [const Color(0xFFFFD700), const Color(0xFFFFA500)]},
      {'id': 'chef', 'title': 'От шефа', 'icon': Icons.restaurant_menu_rounded, 'colors': [const Color(0xFFD4AF37), const Color(0xFF8B4513)]},
      {'id': 'promo', 'title': 'Акции', 'icon': Icons.local_offer_rounded, 'colors': [const Color(0xFF00C9FF), const Color(0xFF92FE9D)]},
      {'id': 'hits', 'title': 'Хиты', 'icon': Icons.workspace_premium_rounded, 'colors': [const Color(0xFFEE9CA7), const Color(0xFFFFD1FF)]},
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 24, bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: quickCats.asMap().entries.map((entry) {
          final index = entry.key;
          final cat = entry.value;
          final colors = cat['colors'] as List<Color>;
          final isSelected = activeQuickFilter == cat['id'];
          
          return GestureDetector(
            onTap: () {
              setState(() {
                activeQuickFilter = cat['id'] as String;
                selectedCategoryId = 'none'; // Unselect bottom categories
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 72,
              height: 100,
              margin: EdgeInsets.only(right: index == quickCats.length - 1 ? 0 : 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: isSelected ? Border.all(color: colors[0], width: 2) : null,
                boxShadow: [
                  BoxShadow(
                    color: isSelected ? (colors[0]).withOpacity(0.3) : (colors[0]).withOpacity(0.1),
                    spreadRadius: isSelected ? 2 : 0,
                    blurRadius: isSelected ? 20 : 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: Icon(
                      cat['icon'] as IconData,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cat['title'] as String,
                    style: GoogleFonts.outfit(
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 12,
                      color: isSelected ? colors[0] : const Color(0xFF2D2D2D),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _CategoryHeaderDelegate(
        child: Container(
          color: const Color(0xFFF8F8F8),
          height: 75,
          child: ListView.builder(
            controller: _categoryScrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final isSelected = cat.id == selectedCategoryId;
              return GestureDetector(
                onTap: () => _onCategorySelected(index, cat.id),
                behavior: HitTestBehavior.opaque,
                child: AnimatedScale(
                  scale: isSelected ? 1.05 : 1.0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.elasticOut,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.black : Colors.transparent,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: isSelected ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ] : [],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      cat.title,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMenuGrid() {
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = screenWidth > 1200 ? 5 : (screenWidth > 800 ? 3 : 2);
    
    // Сложная фильтрация: либо через быстрый фильтр (Топ, Новинки), либо через категорию
    List<MenuItem> filteredItems;
    if (activeQuickFilter != null) {
      if (activeQuickFilter == 'favorites') {
        final favs = Provider.of<FavoritesProvider>(context);
        filteredItems = menuItems.where((item) => favs.isFavorite(item.id)).toList();
      } else if (activeQuickFilter == 'top') {
        filteredItems = menuItems.where((item) => item.isTop).toList();
      } else if (activeQuickFilter == 'hits') {
        filteredItems = menuItems.where((item) => item.isHit).toList();
      } else if (activeQuickFilter == 'new') {
        filteredItems = menuItems.where((item) => item.isNew).toList();
      } else if (activeQuickFilter == 'chef') {
        filteredItems = menuItems.where((item) => item.isChefChoice).toList();
      } else if (activeQuickFilter == 'promo') {
        filteredItems = menuItems.where((item) => item.isPromo).toList();
      } else {
        filteredItems = menuItems;
      }
    } else {
      filteredItems = selectedCategoryId == '0' 
          ? menuItems 
          : menuItems.where((item) => item.categoryId == selectedCategoryId).toList();
    }

    if (filteredItems.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(Icons.restaurant_menu_rounded, color: Colors.grey, size: 48),
              SizedBox(height: 16),
              Text(
                'Блюда в этой категории скоро появятся',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.65,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = filteredItems[index];
          final cart = Provider.of<CartProvider>(context, listen: false);
          return GestureDetector(
            onTap: () => _showItemDetails(item),
            child: _MenuItemCard(item: item, cart: cart),
          );
        }, childCount: filteredItems.length),
      ),
    );
  }


  void _showItemDetails(MenuItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (context) => _MenuItemDetailSheet(item: item),
    );
  }



  // Removing the old bottom bar as it's no longer needed in this separate design
  Widget _buildBottomBar() {
    return const SizedBox.shrink();
  }
}

class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final CartProvider cart;
  const _MenuItemCard({required this.item, required this.cart});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return _buildSmartImage(item.images[0], width: constraints.maxWidth, height: constraints.maxHeight);
                      }
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Consumer<FavoritesProvider>(
                      builder: (ctx, favs, child) {
                        final isFav = favs.isFavorite(item.id);
                        return GestureDetector(
                          onTap: () => favs.toggleFavorite(item.id),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              size: 20,
                              color: isFav ? Colors.red : Colors.grey.shade400,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 44, // Чтобы не перекрывать кнопку избранного
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (item.isTop) _buildBadge('Топ', const Color(0xFF8B4513)),
                        if (item.isNew) _buildBadge('Новинка', const Color(0xFFFFC107)),
                        if (item.isChefChoice) _buildBadge('От шефа', const Color(0xFF556B2F)),
                        if (item.isPromo) _buildBadge('Акция', const Color(0xFF00ACC1)),
                        if (item.isHit) _buildBadge('Хит', const Color(0xFFFF6D3F)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Colors.black,
                  ),
                ),
                if (item.weight != null)
                  Text(
                    item.weight!,
                    style: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${item.price.toInt()} ₽',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: Colors.black,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        cart.addToCart(item.id, 1);
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${item.title} добавлено в корзину'),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFF1A1A1A),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.add, size: 24),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _CategoryHeaderDelegate({required this.child});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  double get maxExtent => 75;
  @override
  double get minExtent => 75;
  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      true;
}

class _HeaderCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;

    // Left inverted corner
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, 40, 40)),
        Path()..addOval(Rect.fromCircle(center: const Offset(40, 40), radius: 40)),
      ),
      paint,
    );

    // Right inverted corner
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(size.width - 40, 0, 40, 40)),
        Path()..addOval(Rect.fromCircle(center: Offset(size.width - 40, 40), radius: 40)),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MenuItemDetailSheet extends StatefulWidget {
  final MenuItem item;
  const _MenuItemDetailSheet({required this.item});

  @override
  State<_MenuItemDetailSheet> createState() => _MenuItemDetailSheetState();
}

class _MenuItemDetailSheetState extends State<_MenuItemDetailSheet> {
  int count = 1;
  int _currentImageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final animation = ModalRoute.of(context)?.animation;
    
    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Stack(
        children: [
          // 1. MAIN CONTENT (The "Curved Panel" that slides up)
          SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image Slider
                SizedBox(
                  height: 600,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      PageView.builder(
                        itemCount: widget.item.images.length,
                        onPageChanged: (index) {
                          setState(() {
                            _currentImageIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          return _buildSmartImage(widget.item.images[index]);
                        },
                      ),
                      // Image Index Indicator (Dots)
                      if (widget.item.images.length > 1)
                        Positioned(
                          bottom: 20,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: widget.item.images.asMap().entries.map((entry) {
                              return Container(
                                width: 8.0,
                                height: 8.0,
                                margin: const EdgeInsets.symmetric(horizontal: 4.0),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentImageIndex == entry.key
                                      ? const Color(0xFFD4A043)
                                      : Colors.white.withOpacity(0.5),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              widget.item.title,
                              style: GoogleFonts.outfit(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          if (widget.item.weight != null)
                            Text(
                              widget.item.weight!,
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.item.description,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                          height: 1.5,
                        ),
                      ),
                      Text(
                        'Ингредиенты',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 130, 
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.item.ingredients.length,
                          itemBuilder: (context, index) {
                            String ingredient = widget.item.ingredients[index];
                            String? imagePath = widget.item.ingredientImages[ingredient];
                            return Container(
                              width: 100,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade100),
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                      child: Container(
                                        width: double.infinity,
                                        color: Colors.white,
                                        child: imagePath != null 
                                          ? _buildSmartImage(imagePath)
                                          : const Icon(Icons.restaurant, color: Colors.grey, size: 24),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                    child: Text(
                                      ingredient,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Пищевая ценность',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildNutritionItem('Ккал', widget.item.calories?.toString() ?? '-'),
                            _buildNutritionItem('Белки', '${widget.item.proteins ?? '-'}г'),
                            _buildNutritionItem('Жиры', '${widget.item.fats ?? '-'}г'),
                            _buildNutritionItem('Углев.', '${widget.item.carbs ?? '-'}г'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Острота',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Row(
                            children: List.generate(5, (index) {
                              return Icon(
                                Icons.whatshot,
                                color: index < widget.item.spiciness ? Colors.red : Colors.grey.shade300,
                                size: 24,
                              );
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 120), // Space for bottom button
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // 2. FIXED BLACK HEADER (Fades in "on site")
          if (animation != null)
            AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                // Counteracting the bottom sheet slide to make it appear "on site"
                final double screenHeight = MediaQuery.of(context).size.height;
                final double translation = (1 - animation.value) * screenHeight;
                
                return Transform.translate(
                  offset: Offset(0, -translation), // Pin to top of screen
                  child: Opacity(
                    opacity: animation.value,
                    child: SizedBox(
                      height: 55, // 35px black + 20px curve
                      width: double.infinity,
                      child: Stack(
                        children: [
                          Container(
                            height: 35,
                            color: Colors.black,
                          ),
                          Positioned(
                            top: 35,
                            left: 0,
                            right: 0,
                            height: 20,
                            child: CustomPaint(
                              painter: _HeaderCurvePainter(),
                            ),
                          ),
                          // Handle inside the black bar
                          Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              margin: const EdgeInsets.only(top: 8),
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          
          // 3. FLOATING BUTTONS
          Positioned(
            top: 70, // Positioned over the photo
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
                Consumer<FavoritesProvider>(
                  builder: (ctx, favs, child) {
                    final isFav = favs.isFavorite(widget.item.id);
                    return GestureDetector(
                      onTap: () => favs.toggleFavorite(widget.item.id),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded, 
                          color: isFav ? Colors.red : Colors.white, 
                          size: 20,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          
          // 4. BOTTOM ORDER PANEL
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    // Counter
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          _buildCountButton(Icons.remove, () {
                            if (count > 1) setState(() => count--);
                          }),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              count.toString(),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          _buildCountButton(Icons.add, () {
                            setState(() => count++);
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Add to cart button
                    Expanded(
                      child: Consumer<CartProvider>(
                        builder: (context, cart, child) {
                          return ElevatedButton(
                            onPressed: () {
                              // Добавляем в общую корзину через Supabase
                              cart.addToCart(widget.item.id, count);
                              
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Добавлено в общую корзину: ${widget.item.title}'),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Colors.black,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            child: Text(
                              'Добавить — ${(widget.item.price * count).toInt()} сом',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildCountButton(IconData icon, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4),
          ],
        ),
        child: Icon(icon, size: 20, color: Colors.black),
      ),
    );
  }
}

class SharedCartScreen extends StatefulWidget {
  final String tableNumber;
  const SharedCartScreen({super.key, required this.tableNumber});

  @override
  State<SharedCartScreen> createState() => _SharedCartScreenState();
}

class _SharedCartScreenState extends State<SharedCartScreen> {
  String _splitMode = 'all'; // 'all', 'equal', 'mine'
  int _guestCount = 1;
  bool _isGuestCountManual = false; // Отслеживаем, менял ли пользователь число вручную

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    Future.delayed(Duration.zero, () {
      Stream.periodic(const Duration(seconds: 1)).listen((_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Consumer<CartProvider>(
        builder: (context, cart, child) {
          if (cart.isLoading) {
            return const Center(child: CircularProgressIndicator(color: Colors.black));
          }
          
          return Column(
            children: [
              Stack(
                children: [
                  Container(
                    height: 180,
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(60),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Text(
                              "КОРЗИНА СТОЛА № ${widget.tableNumber}",
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(width: 48), // Заглушка вместо кнопки обновления для центровки
                          ],
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Row(
                            children: [
                              _buildHeaderModeButton('mine', 'За себя', Icons.person_outline),
                              _buildHeaderModeButton('equal', 'Поровну', Icons.groups_outlined),
                              _buildHeaderModeButton('all', 'За всех', Icons.account_balance_wallet_outlined),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 10),

              if (cart.errorMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                  margin: const EdgeInsets.only(bottom: 10),
                  color: Colors.amber.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.sync_problem_rounded, color: Colors.amber.shade900, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          cart.errorMessage!,
                          style: TextStyle(
                            color: Colors.amber.shade900, 
                            fontSize: 12, 
                            fontWeight: FontWeight.w500
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (cart.items.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          "Корзина пуста",
                          style: GoogleFonts.outfit(color: Colors.grey, fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                _buildCartBody(cart),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCartBody(CartProvider cart) {
    // Автоматически обновляем количество гостей, если режим "Поровну" и пользователь не менял его вручную
    if (_splitMode == 'equal' && !_isGuestCountManual) {
      final actualParticipants = cart.participants.length;
      // Если участников 0 (в начале загрузки), ставим минимум 1
      final targetCount = actualParticipants > 0 ? actualParticipants : 1;
      if (_guestCount != targetCount) {
        // Используем WidgetsBinding, чтобы избежать ошибки setState во время билда
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _guestCount = targetCount);
        });
      }
    }

    double totalForTable = 0;
    double totalForMe = 0;
    for (var item in cart.items) {
      final foundItems = menuItems.where((m) => m.id == item.menuItemId);
      if (foundItems.isEmpty) continue;
      
      final menuItem = foundItems.first;
      double price = menuItem.price * item.quantity;
      totalForTable += price;
      if (item.addedBy == cart.deviceId) {
        totalForMe += price;
      }
    }

    double displayTotal = totalForTable;
    if (_splitMode == 'mine') displayTotal = totalForMe;
    if (_splitMode == 'equal') displayTotal = totalForTable / _guestCount;

    return Expanded(
      child: Column(
        children: [
          if (_splitMode == 'equal')
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Кол-во гостей: ", style: GoogleFonts.outfit()),
                  _buildCountBtn(Icons.remove, () {
                    if (_guestCount > 1) {
                      setState(() {
                        _guestCount--;
                        _isGuestCountManual = true;
                      });
                    }
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text("$_guestCount", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ),
                  _buildCountBtn(Icons.add, () {
                    setState(() {
                      _guestCount++;
                      _isGuestCountManual = true;
                    });
                  }),
                ],
              ),
            ),
          Expanded(
            child: () {
              final orderingItems = cart.items.where((it) => it.status == 'ordering').toList();
              final confirmedItems = cart.items.where((it) => it.status != 'ordering').toList();

              // Функция группировки с сортировкой (Вы — первые)
              List<Map<String, dynamic>> group(List<CartItem> list) {
                final Map<String, Map<String, dynamic>> g = {};
                for (var it in list) {
                  final key = "${it.menuItemId}_${it.status}_${it.addedBy}";
                  if (g.containsKey(key)) {
                    g[key]!['quantity'] += it.quantity;
                  } else {
                    g[key] = {'item': it, 'quantity': it.quantity};
                  }
                }
                
                final result = g.values.toList();
                // Сортировка: сначала текущий пользователь
                result.sort((a, b) {
                  final aIsMe = (a['item'] as CartItem).addedBy == cart.deviceId;
                  final bIsMe = (b['item'] as CartItem).addedBy == cart.deviceId;
                  if (aIsMe && !bIsMe) return -1;
                  if (!aIsMe && bIsMe) return 1;
                  return 0;
                });
                return result;
              }

              final groupedOrdering = group(orderingItems);
              final groupedConfirmed = group(confirmedItems);

              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  if (groupedOrdering.isNotEmpty) ...[
                    _buildSectionHeader("НОВЫЕ ПОЗИЦИИ"),
                    ...groupedOrdering.map((g) => _buildCartCard(g['item'], g['quantity'], cart)),
                  ],
                  if (groupedConfirmed.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildSectionHeader("УЖЕ ЗАКАЗАНО"),
                    ...groupedConfirmed.map((g) => _buildCartCard(g['item'], g['quantity'], cart)),
                  ],
                ],
              );
            }(),
          ),
          _buildTotalPanel(totalForTable, displayTotal, cart),
        ],
      ),
    );
  }
 
  Widget _buildTotalPanel(double totalForTable, double displayTotal, CartProvider cart) {
    bool hasUnconfirmedItems = cart.items.any((item) => item.status == 'ordering');
    bool isConfirmed = !hasUnconfirmedItems && cart.items.isNotEmpty;
    
    final readyCount = cart.participants.where((p) => p['is_ready'] == true).length;
    final totalParticipants = cart.participants.length;
 
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _splitMode == 'mine' ? "К ОПЛАТЕ (ВАША ДОЛЯ)" : 
                      _splitMode == 'equal' ? "К ОПЛАТЕ (ПОРОВНУ)" : "ОБЩИЙ ИТОГ",
                      style: GoogleFonts.forum(fontSize: 14, letterSpacing: 1),
                    ),
                    if (_splitMode != 'all')
                      Text("Всего стола: ${totalForTable.toInt()} сом", style: TextStyle(fontSize: 12, color: Colors.black87)),
                  ],
                ),
                Text("${displayTotal.toInt()} сом", style: GoogleFonts.outfit(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.black)),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: (hasUnconfirmedItems) ? () => cart.toggleReady() : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: cart.isReady ? const Color(0xFFD4A043) : Colors.black,
                disabledBackgroundColor: isConfirmed ? const Color(0xFFE09E00).withOpacity(0.7) : Colors.grey.shade300,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                isConfirmed ? "ЗАКАЗ ПРИНЯТ" : 
                (cart.isReady && totalParticipants > 1) ? "ОЖИДАНИЕ ОСТАЛЬНЫХ ($readyCount/$totalParticipants)" :
                hasUnconfirmedItems ? "ЗАКАЗАТЬ" : "КОРЗИНА ПУСТА",
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderModeButton(String mode, String label, IconData icon) {
    bool isActive = _splitMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _splitMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? Colors.white.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isActive ? Colors.white : Colors.white.withOpacity(0.5)),
              const SizedBox(height: 2),
              Text(
                label, 
                style: GoogleFonts.outfit(
                  fontSize: 10, 
                  color: isActive ? Colors.white : Colors.white.withOpacity(0.5), 
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal
                )
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
        child: Icon(icon, size: 14),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 15, bottom: 10),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: Colors.black45,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCartCard(CartItem cartItem, int displayQuantity, CartProvider cart) {
    final foundItems = menuItems.where((m) => m.id == cartItem.menuItemId);
    if (foundItems.isEmpty) return const SizedBox.shrink();
    
    final menuItem = foundItems.first;
    final isMine = cartItem.addedBy == cart.deviceId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isMine ? Border.all(color: const Color(0xFFFFD166), width: 1) : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _buildSmartImage(
              menuItem.images.isNotEmpty ? menuItem.images.first : '', 
              width: 55, height: 55
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(menuItem.title, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.black, fontSize: 14)),
                Consumer<CartProvider>(
                  builder: (context, cart, child) {
                    final participant = cart.participants.firstWhere(
                      (p) => p['device_id'] == cartItem.addedBy,
                      orElse: () => {},
                    );
                    final isReady = isMine ? cart.isReadyLocally : (participant['is_ready'] == true);
                    return Row(
                      children: [
                        Text(
                          isMine ? "Вы (${cart.userName ?? 'Гость'})" : (participant['user_name'] ?? "Гость"),
                          style: GoogleFonts.outfit(
                            color: isMine ? const Color(0xFFE09E00) : Colors.black54, 
                            fontSize: 10,
                            fontWeight: isMine ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        if (isReady) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.check_circle, color: Colors.green, size: 10),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("x$displayQuantity", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(
                "${(menuItem.price * displayQuantity).toInt()} сом", 
                style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontSize: 11, fontWeight: FontWeight.bold)
              ),
              if (cartItem.status == 'confirmed')
                Text("Ожидает подтверждения", style: GoogleFonts.outfit(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
              if (cartItem.status == 'processing')
                Text("Принято, готовим", style: GoogleFonts.outfit(color: Colors.blue, fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          ),
          if (cartItem.status == 'ordering')
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
              onPressed: () => cart.removeFromCart(cartItem.id),
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class TableMapItem {
  final String id;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool isCabin;
  final int floor;
  final String label;

  TableMapItem({
    required this.id,
    required this.x,
    required this.y,
    this.width = 60,
    this.height = 60,
    this.isCabin = false,
    required this.floor,
    required this.label,
  });
}

class TableBookingScreen extends StatefulWidget {
  const TableBookingScreen({super.key});

  @override
  State<TableBookingScreen> createState() => _TableBookingScreenState();
}

class _TableBookingScreenState extends State<TableBookingScreen> {
  List<Map<String, dynamic>> _floors = [];
  List<Map<String, dynamic>> _tables = [];
  List<Map<String, dynamic>> _activeBookings = [];
  String? _selectedFloorId;
  String? _tempSelectedTableId;
  bool _loading = true;
  final TransformationController _transformCtrl = TransformationController();
  RealtimeChannel? _tablesRealtime;

  void initState() {
    super.initState();
    _load();
    _initRealtime();
  }

  void _initRealtime() {
    _tablesRealtime = Supabase.instance.client
        .channel('public:restaurant_tables')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'restaurant_tables',
          callback: (payload) {
            if (mounted) {
              setState(() {
                final newRecord = payload.newRecord;
                final idx = _tables.indexWhere((t) => t['id'] == newRecord['id']);
                if (idx != -1) {
                  _tables[idx] = Map<String, dynamic>.from(newRecord);
                } else {
                  _load(); // Если не нашли в списке, перезагружаем всё
                }
              });
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_tables',
          callback: (payload) {
             if (payload.eventType != PostgresChangeEvent.update) {
               _load();
             }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _tablesRealtime?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final fRes = await Supabase.instance.client.from('floors').select().order('sort_order');
      final tRes = await Supabase.instance.client.from('restaurant_tables').select().eq('is_active', true);
      final bRes = await Supabase.instance.client.from('bookings').select().inFilter('status', ['confirmed', 'accepted']);
      
      if (mounted) {
        setState(() {
          _floors = List<Map<String, dynamic>>.from(fRes);
          _tables = List<Map<String, dynamic>>.from(tRes);
          _activeBookings = List<Map<String, dynamic>>.from(bRes);
          if (_floors.isNotEmpty && _selectedFloorId == null) {
            _selectedFloorId = _floors.first['id'];
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectAndShowBooking(Map<String, dynamic> table) {
    if (table['is_booked'] == true) {
      // Ищем время когда освободится
      final booking = _activeBookings.firstWhere(
        (b) => b['table_id'].toString() == table['id'].toString(),
        orElse: () => {},
      );
      final endTime = booking['end_time'];
      final message = endTime != null 
          ? 'Этот стол занят до $endTime' 
          : 'Этот стол сейчас занят';
          
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _tempSelectedTableId = table['id']);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BookingSheet(table: table),
    ).then((_) {
      // Обновляем данные с сервера, чтобы увидеть красный стол
      _load();
      // Сбрасываем временный выбор
      setState(() => _tempSelectedTableId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      body: Stack(
        children: [
          Container(
            height: 240,
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(80)),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Text(
                        'БРОНИРОВАНИЕ',
                        style: GoogleFonts.forum(color: Colors.white, fontSize: 24, letterSpacing: 4),
                      ),
                    ],
                  ),
                ),
                if (_floors.length > 1)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: _floors.map((f) => _FloorBtn(
                        label: (f['name'] as String).toUpperCase(),
                        isSel: _selectedFloorId == f['id'],
                        onTap: () => setState(() => _selectedFloorId = f['id']),
                      )).toList(),
                    ),
                  ),
                const SizedBox(height: 30),
                Center(
                  child: Container(
                    width: 360,
                    height: 600,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 40, offset: const Offset(0, 20))],
                    ),
                    child: _loading 
                      ? const Center(child: CircularProgressIndicator(color: Colors.black12))
                      : _selectedFloorId == null
                        ? Center(child: Text('Схема залов не настроена', style: GoogleFonts.outfit(color: Colors.black26)))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(40),
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  _buildHallScheme(),
                                  _buildExtraTablesList(),
                                  const SizedBox(height: 100), 
                                ],
                              ),
                            ),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LegendItem(color: const Color(0xFF4CAF50), label: 'Свободно'),
                      const SizedBox(width: 20),
                      _LegendItem(color: const Color(0xFFF44336), label: 'Занято'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Text(
                    'Выберите подходящее место для перехода к бронированию',
                    style: GoogleFonts.outfit(color: Colors.grey, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHallScheme() {
    if (_floors.isEmpty || _selectedFloorId == null) return const SizedBox.shrink();
    
    final floor = _floors.firstWhere((f) => f['id'] == _selectedFloorId);
    final floorTables = _tables.where((t) => t['floor_id'] == _selectedFloorId).toList();
    // Берем только те, у которых есть координаты
    final placedTables = floorTables.where((t) => (t['pos_x'] as num) > 0 || (t['pos_y'] as num) > 0).toList();
    final planUrl = floor['plan_url'];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Фон: Схема или сетка
        if (planUrl != null && planUrl.toString().isNotEmpty)
          Image.network(
            planUrl,
            fit: BoxFit.fill,
            alignment: Alignment.center,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return Container(width: 1000, height: 800, color: Colors.grey.shade50);
            },
            errorBuilder: (_, __, ___) => _buildGridFallback(),
          )
        else
          _buildGridFallback(),
        // Размещенные столы
        ...placedTables.map((table) {
          final double w = (table['width'] ?? 80).toDouble();
          final double h = (table['height'] ?? 80).toDouble();
          final double rotation = (table['rotation'] ?? 0).toDouble();
          double x = (table['pos_x'] as num).toDouble();
          double y = (table['pos_y'] as num).toDouble();

          // Ретро-совместимость с относительными координатами
          if (x < 2.0 && y < 2.0) { x *= 1000; y *= 1000; }

          return Positioned(
            left: x - (w / 2),
            top: y - (h / 2),
            child: Transform.rotate(
              angle: rotation * (3.1415926535 / 180),
              child: GestureDetector(
                onTap: () => _selectAndShowBooking(table),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: w, height: h,
                  decoration: BoxDecoration(
                    color: (table['is_booked'] == true ? const Color(0xFFF44336) : const Color(0xFF4CAF50)).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(w == h ? 50 : 12),
                    boxShadow: [
                      BoxShadow(
                        color: (table['is_booked'] == true ? const Color(0xFFF44336) : const Color(0xFF4CAF50)).withOpacity(0.4),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: w < 40 
                      ? Icon(
                          table['is_booked'] == true ? Icons.person_off_rounded : Icons.chair_alt_rounded,
                          color: Colors.white.withOpacity(0.8),
                          size: w * 0.5,
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              table['is_booked'] == true ? Icons.person_off_rounded : Icons.chair_alt_rounded,
                              color: Colors.white.withOpacity(0.8),
                              size: w * 0.35,
                            ),
                            if (w >= 45) 
                              Flexible(
                                child: Text(
                                  table['label'] ?? '',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white.withOpacity(0.9), 
                                    fontWeight: FontWeight.bold, 
                                    fontSize: (w * 0.15).clamp(8, 12),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildExtraTablesList() {
    final floorTables = _tables.where((t) => t['floor_id'] == _selectedFloorId).toList();
    // Те, у кого нет координат
    final extraTables = floorTables.where((t) => (t['pos_x'] as num) <= 0 && (t['pos_y'] as num) <= 0).toList();
    
    if (extraTables.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Colors.black12),
          const SizedBox(height: 10),
          Text('ДРУГИЕ СТОЛЫ', style: GoogleFonts.forum(fontSize: 14, letterSpacing: 2, color: Colors.black38)),
          const SizedBox(height: 15),
          Wrap(
            spacing: 15,
            runSpacing: 15,
            children: extraTables.map((table) => GestureDetector(
              onTap: () => _selectAndShowBooking(table),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 70, height: 70,
                decoration: BoxDecoration(
                  color: table['is_booked'] == true ? const Color(0xFFF44336) : const Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                  boxShadow: [
                    if (_tempSelectedTableId == table['id'])
                      BoxShadow(color: const Color(0xFFD4A043).withOpacity(0.4), blurRadius: 10)
                    else
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5),
                  ],
                ),
                child: Center(
                  child: Text(
                    table['label'] ?? '',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGridFallback() {
    return Container(
      width: 1000, height: 1000,
      color: Colors.grey.shade50,
      child: CustomPaint(painter: _GridPainter()),
    );
  }
}

class _FloorBtn extends StatelessWidget {
  final String label;
  final bool isSel;
  final VoidCallback onTap;
  const _FloorBtn({required this.label, required this.isSel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSel ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: isSel ? Colors.black : Colors.white60,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.03)..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 20) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 20) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool border;
  const _LegendItem({required this.color, required this.label, this.border = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: border ? Border.all(color: Colors.black12) : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }
}

class _BookingSheet extends StatefulWidget {
  final Map<String, dynamic> table;
  const _BookingSheet({required this.table});
  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  int guests = 2;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _timeController = TextEditingController(text: '19:00');
  final TextEditingController _endTimeController = TextEditingController(text: '21:00');
  bool _isSubmitting = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _timeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(44)),
      ),
      padding: EdgeInsets.fromLTRB(32, 32, 32, 32 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 30),
            Text('${widget.table['label']}'.toUpperCase(), style: GoogleFonts.forum(fontSize: 16, letterSpacing: 2, color: Colors.grey)),
            Text('ОФОРМИТЬ БРОНЬ', style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 30),
            
            Text('ВАШЕ ИМЯ *', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Имя',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              ),
            ),
            const SizedBox(height: 20),
            
            Text('НОМЕР ТЕЛЕФОНА *', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '700 123 456',
                prefixText: '+996 ',
                prefixStyle: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              ),
            ),
            const SizedBox(height: 30),

            Text('КОЛИЧЕСТВО ГОСТЕЙ', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 16),
            Row(
              children: [
                _CountBtn(icon: Icons.remove, onTap: () => setState(() => guests = guests > 1 ? guests - 1 : 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24), 
                  child: Text(
                    '$guests', 
                    style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)
                  )
                ),
                _CountBtn(icon: Icons.add, onTap: () => setState(() => guests++)),
              ],
            ),
            const SizedBox(height: 30),
            Text('ВРЕМЯ ПРИБЫТИЯ', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 16),
            TextField(
              controller: _timeController,
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '19:00',
                filled: true,
                fillColor: Colors.grey.shade50,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.access_time_rounded, color: Colors.black),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                      builder: (context, child) => Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(primary: Colors.black),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setState(() => _timeController.text = picked.format(context));
                    }
                  },
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              ),
            ),
            const SizedBox(height: 20),
            Text('ВРЕМЯ УХОДА', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 16),
            TextField(
              controller: _endTimeController,
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '21:00',
                filled: true,
                fillColor: Colors.grey.shade50,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.access_time_rounded, color: Colors.black),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: const TimeOfDay(hour: 21, minute: 0),
                      builder: (context, child) => Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(primary: Colors.black),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setState(() => _endTimeController.text = picked.format(context));
                    }
                  },
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              ),
            ),
            const SizedBox(height: 12),
            if (_localError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_localError!, style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _isSubmitting ? null : () async {
                final phone = _phoneController.text.trim();
                if (_nameController.text.isEmpty || phone.isEmpty) {
                  _showError('Пожалуйста, заполните Имя и Номер телефона');
                  return;
                }
                if (phone.length != 9) {
                  _showError('Введите 9 цифр номера после +996');
                  return;
                }

                setState(() => _isSubmitting = true);

                try {
                  final fullPhone = '+996$phone';
                  
                  // 1. Сохраняем бронь в базу
                  await Supabase.instance.client.from('bookings').insert({
                    'table_id': widget.table['id'],
                    'customer_name': _nameController.text.trim(),
                    'customer_phone': fullPhone,
                    'guests_count': guests,
                    'booking_time': _timeController.text.trim(),
                    'end_time': _endTimeController.text.trim(),
                    'status': 'confirmed'
                  });

                  // 2. Помечаем стол как забронированный
                  await Supabase.instance.client
                      .from('restaurant_tables')
                      .update({'is_booked': true})
                      .eq('id', widget.table['id']);

                  // 3. Уведомляем администратора в Telegram
                  final msg = '📅 *БРОНЬ СТОЛА!*\n\n'
                      '🪑 Стол: *№${widget.table['label']}*\n'
                      '👤 Гость: *${_nameController.text}*\n'
                      '📞 Телефон: * $fullPhone *\n'
                      '👥 Гостей: * $guests *\n'
                      '⏰ Время: * ${_timeController.text} *';

                  if (SettingsService.telegramNotify) {
                    await TelegramService.sendMessage(msg);
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Бронь для ${_nameController.text} подтверждена'), 
                        backgroundColor: Colors.black,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('Booking error: $e');
                  _showError('Ошибка бронирования. Попробуйте позже.');
                } finally {
                  if (mounted) setState(() => _isSubmitting = false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black, 
                foregroundColor: Colors.white, 
                minimumSize: const Size(double.infinity, 70), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: _isSubmitting 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('ПОДТВЕРДИТЬ', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 2)),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String msg) {
    setState(() => _localError = msg);
    // Автоматически скрываем ошибку через 3 секунды
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _localError = null);
    });
  }
}

class _CountBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CountBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade50, shape: BoxShape.circle), child: Icon(icon, size: 20)),
    );
  }
}

Widget _buildSmartImage(String url, {double? width, double? height}) {
  final placeholder = Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.restaurant_rounded, 
              color: Colors.grey.shade300, 
              size: (width != null && width < 100) ? 24 : 48
            ),
            if (width == null || width > 120) ...[
              const SizedBox(height: 12),
              Text(
                'НЕТ ИЗОБРАЖЕНИЯ',
                style: GoogleFonts.outfit(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  if (url.startsWith('assets/')) {
    // Если путь уже содержит assets/, Flutter Image.asset может дублировать его в вебе
    // Очищаем путь для корректной загрузки
    final cleanPath = url.replaceFirst('assets/assets/', 'assets/');
    return Image.asset(
      cleanPath, 
      width: width, 
      height: height, 
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
  
  return Image.network(
    url, 
    width: width, 
    height: height, 
    fit: BoxFit.cover, 
    loadingBuilder: (context, child, loadingProgress) {
      if (loadingProgress == null) return child;
      return Container(
        width: width,
        height: height,
        color: Colors.grey.shade50,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black12),
          ),
        ),
      );
    },
    errorBuilder: (context, error, stackTrace) => placeholder,
  );
}

  Widget _buildBannerPlaceholder(Map<String, String> banner) {
    final previewUrl = banner['preview_url'] ?? banner['url'];
    // Если нет даже ссылки, показываем пустой светлый блок
    if (previewUrl == null) return Container(color: Colors.grey.shade200);
    
    return Container(
      color: Colors.grey.shade200,
      child: Image.network(
        previewUrl,
        fit: BoxFit.cover,
        // Добавляем прозрачность при загрузке для мягкости
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey.shade200),
      ),
    );
  }
