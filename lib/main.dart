import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'admin/admin_app.dart';
import 'guest/delivery_screen.dart';
import 'services/settings_service.dart';
import 'services/menu_data_service.dart';
import 'services/favorites_provider.dart';

List<Category> get categories => MenuDataService.categories;
List<MenuItem> get menuItems => MenuDataService.items;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация Supabase
  await Supabase.initialize(
    url: 'https://vgzdpbwcenckmjtgfvfw.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZnemRwYndjZW5ja21qdGdmdmZ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY2NDkxODAsImV4cCI6MjA5MjIyNTE4MH0.pFmPP9A9Tov4b6URS-LP5b3lYyB0fVXTKDvLY_MR120',
  );

  // Запускаем загрузку данных в фоне, не дожидаясь ответа от сервера в main(),
  // чтобы приложение не висело на индикаторе загрузки браузера.
  SettingsService.load();
  MenuDataService.load();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarBrightness: Brightness.dark,
    ),
  );
  
  // Роут на админку: ?admin=1
  final params = Uri.base.queryParameters;
  if (params.containsKey('admin')) {
    runApp(const AdminApp());
    return;
  }

  // Определяем режим: стол или доставка
  final String? tableParam = params['table'];
  final String tableId = tableParam ?? '1';
  final bool isDeliveryMode = tableParam == null;
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider(tableId: tableId)),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
      ],
      child: MenuApp(isDeliveryMode: isDeliveryMode),
    ),
  );
}

class MenuApp extends StatelessWidget {
  final bool isDeliveryMode;
  const MenuApp({super.key, this.isDeliveryMode = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Каркыра — Ресторан',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scrollBehavior: AppScrollBehavior(),
      home: MenuHomeScreen(isDeliveryMode: isDeliveryMode),
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
  const MenuHomeScreen({super.key, this.isDeliveryMode = false});

  @override
  State<MenuHomeScreen> createState() => _MenuHomeScreenState();
}

class _MenuHomeScreenState extends State<MenuHomeScreen> {
  String selectedCategoryId = '0'; // '0' is 'Все'
  String? activeQuickFilter; // To track Top, New, etc.
  final ScrollController _categoryScrollController = ScrollController();
  final List<VideoPlayerController> _videoControllers = [];
  final PageController _bannerPageController = PageController();
  int _currentVideoIndex = 0;
  bool _isMuted = true;

  // _videoAssets list removed since we use dynamic bannerUrl

  @override
  void initState() {
    super.initState();
    _initializeVideos();
  }

  void _initializeVideos() async {
    final asset = MenuDataService.bannerUrl ?? 'assets/videos/test.mp4';
    final controller = asset.startsWith('assets/')
        ? VideoPlayerController.asset(asset)
        : VideoPlayerController.networkUrl(Uri.parse(asset));
      try {
        await controller.initialize();
        controller.setLooping(false); 
        controller.setVolume(0);
        
        controller.addListener(() {
          if (controller.value.position >= controller.value.duration && 
              !controller.value.isPlaying) {
             _playNextVideo();
          }
        });
        
        setState(() {
          _videoControllers.add(controller);
        });
      } catch (e) {
        print('Error initializing $asset: $e');
      }

    // We only have one dynamic video banner string now.
    if (_videoControllers.isNotEmpty) {
      _videoControllers[0].play();
    }
    setState(() {});
  }

  void _playNextVideo() {
    if (_videoControllers.isEmpty) return;
    
    int nextIndex = (_currentVideoIndex + 1) % _videoControllers.length;
    _bannerPageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOutCubic,
    );
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      for (var controller in _videoControllers) {
        controller.setVolume(_isMuted ? 0 : 1.0);
      }
    });
  }

  @override
  void dispose() {
    for (var controller in _videoControllers) {
      controller.dispose();
    }
    _categoryScrollController.dispose();
    _bannerPageController.dispose();
    super.dispose();
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
      backgroundColor: AppTheme.backgroundColor,
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
              // Отдельная кнопка вызова официанта в правом нижнем углу
              Positioned(
                bottom: 30,
                right: 20,
                child: _buildFloatingWaiterButton(),
              ),
            ],
          ),
        ),
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
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4A043),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (cart.totalItems > 0) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('${cart.totalItems}',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text('Заказать',
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
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
                        builder: (context) => const SharedCartScreen(),
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
        if (_videoControllers.isNotEmpty) {
          if (info.visibleFraction == 0) {
            _videoControllers[_currentVideoIndex].pause();
          } else {
            // Restore playback only if it's the currently focused video
            _videoControllers[_currentVideoIndex].play();
          }
        }
      },
      child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12), 
      height: screenHeight * 0.55, 
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(40), // Large premium rounding only at the bottom
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Video Carousel
          _videoControllers.isEmpty
              ? Image.network('assets/images/restaurant_banner.png', fit: BoxFit.cover)
              : PageView.builder(
                  controller: _bannerPageController,
                  onPageChanged: (index) {
                    setState(() => _currentVideoIndex = index);
                    for (var i = 0; i < _videoControllers.length; i++) {
                      if (i == index) {
                        _videoControllers[i].play();
                      } else {
                        _videoControllers[i].pause();
                      }
                    }
                  },
                  itemCount: _videoControllers.length,
                  itemBuilder: (context, index) {
                    final controller = _videoControllers[index];
                    if (!controller.value.isInitialized) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white24));
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
                      Colors.black.withOpacity(0.2), // Light darkening for logo
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withOpacity(0.05), // Subtle depth
                      Colors.black.withOpacity(0.15), // Very clean bottom fade
                    ],
                    stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Pagination Dots
          if (_videoControllers.length > 1)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_videoControllers.length, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentVideoIndex == index ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _currentVideoIndex == index 
                          ? Colors.white 
                          : Colors.white.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          // Sound Toggle Button
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

  Widget _buildFloatingWaiterButton() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6D3F).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: const Color(0xFFFF6D3F),
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          onTap: () {
            // Logic for calling waiter
          },
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Вызвать официанта',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
                    child: _buildSmartImage(item.images[0]),
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
                  if (item.isHit)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6D3F),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Хит',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
                                      ? Colors.white
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
                                          ? Image.network(
                                              imagePath,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.restaurant, color: Colors.grey, size: 24),
                                            )
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
  const SharedCartScreen({super.key});

  @override
  State<SharedCartScreen> createState() => _SharedCartScreenState();
}

class _SharedCartScreenState extends State<SharedCartScreen> {
  String _splitMode = 'all'; // 'all', 'equal', 'mine'
  int _guestCount = 2;

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
                              icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Text(
                              "КОРЗИНА СТОЛА №${cart.tableId}",
                              style: GoogleFonts.forum(
                                color: Colors.white,
                                fontSize: 18,
                                letterSpacing: 4,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                              onPressed: () => cart.clearTable(),
                            ),
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
    double totalForTable = 0;
    double totalForMe = 0;
    for (var item in cart.items) {
      final menuItem = menuItems.firstWhere((m) => m.id == item.menuItemId);
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
                      setState(() => _guestCount--);
                    }
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text("$_guestCount", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                  ),
                  _buildCountBtn(Icons.add, () => setState(() => _guestCount++)),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              key: ValueKey('cart_list_${cart.items.length}'),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: cart.items.length,
              itemBuilder: (context, index) {
                final cartItem = cart.items[index];
                final menuItem = menuItems.firstWhere((m) => m.id == cartItem.menuItemId);
                final isMine = cartItem.addedBy == cart.deviceId;

                return Container(
                  margin: const EdgeInsets.only(bottom: 15),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: isMine ? Border.all(color: const Color(0xFFFFD166), width: 1) : null,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10),
                    ],
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _buildSmartImage(menuItem.images.first, width: 60, height: 60),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(menuItem.title, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.black)),
                            Consumer<CartProvider>(
                              builder: (context, cart, child) {
                                final participant = cart.participants.firstWhere(
                                  (p) => p['device_id'] == cartItem.addedBy,
                                  orElse: () => {},
                                );
                                final number = participant['guest_number'];
                                final isMe = cartItem.addedBy == cart.deviceId;
                                
                                return Text(
                                  isMe ? "Вы (Гость №${cart.myGuestNumber ?? '?'})" : "Гость №${number ?? '?'}",
                                  style: GoogleFonts.outfit(
                                    color: isMe ? const Color(0xFFE09E00) : Colors.black, 
                                    fontSize: 11,
                                    fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("x${cartItem.quantity}", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                          if (cartItem.status == 'confirmed')
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_outline, size: 12, color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text(
                                    "Заказано", 
                                    style: GoogleFonts.outfit(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      // Кнопка удаления (доступна всем для общего стола)
                      if (cartItem.status == 'ordering')
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
                          onPressed: () {
                            debugPrint('--- UI: Click delete on ${cartItem.id}');
                            cart.removeFromCart(cartItem.id);
                          },
                        )
                      else if (isMine && cartItem.status == 'confirmed')
                        const SizedBox(width: 48), // Место, где был бы крестик
                    ],
                  ),
                );
              },
            ),
          ),
          _buildTotalPanel(totalForTable, displayTotal, cart),
        ],
      ),
    );
  }
 
  Widget _buildTotalPanel(double totalForTable, double displayTotal, CartProvider cart) {
    bool hasUnconfirmedItems = cart.items.any((item) => item.status == 'ordering');
    bool isConfirmed = !hasUnconfirmedItems && cart.items.isNotEmpty;
 
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
                      _splitMode == 'equal' ? "К ОПЛАТЕ (ПОРАВНУ)" : "ОБЩИЙ ИТОГ",
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
              onPressed: hasUnconfirmedItems ? () => cart.confirmOrder() : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isConfirmed ? const Color(0xFFE09E00) : Colors.black,
                disabledBackgroundColor: isConfirmed ? const Color(0xFFE09E00).withOpacity(0.7) : Colors.grey.shade300,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                isConfirmed ? "ЗАКАЗ ПОДТВЕРЖДЕН" : 
                hasUnconfirmedItems ? "ДОЗАКАЗАТЬ (${cart.items.where((i) => i.status == 'ordering').length})" : "ОФОРМИТЬ ЗАКАЗ"
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
  int _selectedFloor = 1;
  
  final List<TableMapItem> _tables = [
    // Floor 1
    TableMapItem(id: '1', x: 40, y: 80, floor: 1, label: '1'),
    TableMapItem(id: '2', x: 120, y: 80, floor: 1, label: '2'),
    TableMapItem(id: '3', x: 200, y: 80, floor: 1, label: '3'),
    TableMapItem(id: '4', x: 40, y: 160, floor: 1, label: '4'),
    TableMapItem(id: '5', x: 120, y: 160, floor: 1, label: '5'),
    TableMapItem(id: '6', x: 200, y: 160, floor: 1, label: '6'),
    // Cabins Floor 1
    TableMapItem(id: 'C1', x: 20, y: 320, floor: 1, width: 130, height: 90, isCabin: true, label: 'Кабинка 1'),
    TableMapItem(id: 'C2', x: 170, y: 320, floor: 1, width: 130, height: 90, isCabin: true, label: 'Кабинка 2'),
    
    // Floor 2
    TableMapItem(id: 'V1', x: 20, y: 40, floor: 2, width: 130, height: 130, isCabin: true, label: 'VIP 1'),
    TableMapItem(id: 'V2', x: 170, y: 40, floor: 2, width: 130, height: 130, isCabin: true, label: 'VIP 2'),
    TableMapItem(id: '10', x: 40, y: 220, floor: 2, label: '10'),
    TableMapItem(id: '11', x: 120, y: 220, floor: 2, label: '11'),
    TableMapItem(id: '12', x: 200, y: 220, floor: 2, label: '12'),
    TableMapItem(id: 'C3', x: 20, y: 400, floor: 2, width: 280, height: 110, isCabin: true, label: 'Семейная зона'),
  ];

  void _showBookingSheet(TableMapItem table) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BookingSheet(table: table),
    );
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
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      _FloorBtn(label: '1 ЭТАЖ', isSel: _selectedFloor == 1, onTap: () => setState(() => _selectedFloor = 1)),
                      _FloorBtn(label: '2 ЭТАЖ', isSel: _selectedFloor == 2, onTap: () => setState(() => _selectedFloor = 2)),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(40),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 40, offset: const Offset(0, 20))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(painter: _GridPainter()),
                          ),
                          ..._tables.where((t) => t.floor == _selectedFloor).map((table) => Positioned(
                            left: table.x,
                            top: table.y,
                            child: GestureDetector(
                              onTap: () => _showBookingSheet(table),
                              child: Container(
                                width: table.width,
                                height: table.height,
                                decoration: BoxDecoration(
                                  color: table.isCabin ? Colors.white : const Color(0xFF151515),
                                  borderRadius: BorderRadius.circular(table.isCabin ? 16 : 50),
                                  border: table.isCabin ? Border.all(color: Colors.black12, width: 2) : null,
                                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 5))],
                                ),
                                child: Center(
                                  child: Text(
                                    table.label,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.outfit(
                                      color: table.isCabin ? Colors.black : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: table.isCabin ? 12 : 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )),
                          Positioned(
                            bottom: 25,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _LegendItem(color: const Color(0xFF151515), label: 'Стол'),
                                const SizedBox(width: 30),
                                _LegendItem(color: Colors.white, label: 'Кабинка', border: true),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
  final TableMapItem table;
  const _BookingSheet({required this.table});
  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  int guests = 2;
  String time = '19:00';
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
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
            Text(widget.table.isCabin ? 'КАБИНКА' : 'СТОЛ №${widget.table.label}', style: GoogleFonts.forum(fontSize: 16, letterSpacing: 2, color: Colors.grey)),
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
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '+996 --- -- -- --',
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
                Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text('$guests', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold))),
                _CountBtn(icon: Icons.add, onTap: () => setState(() => guests++)),
              ],
            ),
            const SizedBox(height: 30),
            Text('ВРЕМЯ ПРИБЫТИЯ', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['18:00', '19:00', '20:00', '21:00', '22:00'].map((t) => GestureDetector(
                  onTap: () => setState(() => time = t),
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(color: time == t ? Colors.black : Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
                    child: Text(t, style: GoogleFonts.outfit(color: time == t ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                  ),
                )).toList(),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                if (_nameController.text.isEmpty || _phoneController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Пожалуйста, заполните Имя и Номер телефона'),
                      backgroundColor: Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Бронь для ${_nameController.text} подтверждена'), 
                    backgroundColor: Colors.black,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black, 
                foregroundColor: Colors.white, 
                minimumSize: const Size(double.infinity, 70), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: Text('ПОДТВЕРДИТЬ', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 2)),
            ),
          ],
        ),
      ),
    );
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
  if (url.startsWith('assets/')) {
    return Image.asset(url, width: width, height: height, fit: BoxFit.cover);
  }
  return Image.network(url, width: width, height: height, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: width, height: height, color: Colors.white12));
}
