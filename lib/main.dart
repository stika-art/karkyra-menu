import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'guest/banner_carousel.dart';
import 'waiter/waiter_app.dart' as waiter;

Future<String?> scanQrCodeFromCameraGlobal() {
  final completer = Completer<String?>();
  if (kIsWeb) {
    try {
      js.context.callMethod('scanQrCode', [
        js.allowInterop((result) {
          completer.complete(result?.toString());
        })
      ]);
    } catch (e) {
      debugPrint('JS Scanner failed: $e');
      completer.complete(null);
    }
  } else {
    completer.complete(null);
  }
  return completer.future;
}

String? parseTableFromQr(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  
  try {
    final uri = Uri.parse(trimmed);
    if (uri.queryParameters.containsKey('table')) {
      final val = uri.queryParameters['table']?.trim();
      if (val != null && val.isNotEmpty) return val;
    }
  } catch (_) {}

  final regExp = RegExp(r'(?:table|stol|стол)[=_ ]?([a-zA-Z0-9_-]+)', caseSensitive: false);
  final match = regExp.firstMatch(trimmed);
  if (match != null) {
    return match.group(1);
  }

  return trimmed;
}

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
    
    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString('device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = 'u_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('device_id', deviceId);
    }

    final params = Uri.base.queryParameters;
    final bool isDeliveryMode = !params.containsKey('table');
    final String tableId = isDeliveryMode ? 'delivery_$deviceId' : (params['table'] ?? '1');

    final String fullUrl = Uri.base.toString().toLowerCase();
    final String path = Uri.base.path.toLowerCase();
    final String fragment = Uri.base.fragment.toLowerCase();

    final bool isWaiterRoute = fullUrl.contains('waiter') ||
        path.contains('waiter') ||
        fragment.contains('waiter') ||
        params.containsKey('waiter') ||
        params.containsKey('waiters') ||
        params['role'] == 'waiter' ||
        params['role'] == 'waiters';

    // Обработка ссылки «Иду к столу!» из Telegram
    if (params.containsKey('accept_call')) {
      final callId = params['accept_call']!;
      runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF121212),
        ),
        home: _AcceptCallPage(callId: callId),
      ));
    } else if (params.containsKey('accept_order')) {
      final tableId = params['accept_order']!;
      runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF121212),
        ),
        home: _AcceptOrderPage(tableId: tableId),
      ));
    } else if (isWaiterRoute) {
      runApp(const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: waiter.WaiterApp(),
      ));
    } else if (fullUrl.contains('admin') || params.containsKey('admin') || path.contains('admin') || fragment.contains('admin')) {
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
      title: 'Bonum — Ресторан',
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
  bool _isMenuLoading = false;
  RealtimeChannel? _waiterCallChannel;
  bool _isWaiterComing = false;
  bool _isAskingName = false;
  late bool _isDeliveryActive;

  @override
  void initState() {
    super.initState();
    _isDeliveryActive = widget.isDeliveryMode;
    _initSession();
    _loadMenuData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final cart = Provider.of<CartProvider>(context, listen: false);
        cart.onOrderConfirmed = () {
          // После отправки заказа остаемся в корзине стола
        };
      }
    });
  }

  void _initSession() async {
    if (widget.isDeliveryMode) return;
    
    final prefs = await SharedPreferences.getInstance();
    final key = 'table_${widget.tableId}_first_joined';
    await prefs.setString(key, DateTime.now().toIso8601String());
  }

  void _expireSessionAndRedirect() {
    setState(() {
      _isDeliveryActive = true;
    });
    
    // Переписываем URL в адресной строке браузера на "/" без перезагрузки страницы
    if (kIsWeb) {
      try {
        js.context.callMethod('eval', ["window.history.replaceState({}, '', '/')"]);
        debugPrint('URL successfully rewritten to / (Delivery Mode)');
      } catch (e) {
        debugPrint('URL rewrite failed: $e');
      }
    }
  }



  void _startBuiltInScan() async {
    final scannedResult = await scanQrCodeFromCameraGlobal();
    if (scannedResult != null && scannedResult.isNotEmpty) {
      try {
        final table = parseTableFromQr(scannedResult);
        
        if (table != null && (table == widget.tableId || table == 'table_${widget.tableId}')) {
          // Успешно подтверждено! Сбрасываем таймер и возвращаем режим стола
          _initSession(); // Перезапустит 30-минутный таймер и обновит SharedPreferences
          setState(() {
            _isDeliveryActive = false;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Присутствие за столом №$table успешно подтверждено! Приятного аппетита!',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                backgroundColor: const Color(0xFF4CAF50),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Неверный QR-код. Пожалуйста, отсканируйте код именно вашего стола №${widget.tableId}!',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Scan parsing error: $e');
      }
    }
  }

  @override
  void dispose() {
    _waiterCallChannel?.unsubscribe();
    _categoryScrollController.dispose();
    super.dispose();
  }




  Future<void> _loadMenuData() async {
    try {
      await MenuDataService.load().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('LOAD MENU ERROR: $e');
    } finally {
      if (mounted) {
        setState(() {
          _banners = MenuDataService.banners;
          _isMenuLoading = false;
        });
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _askUserName();
        });
      }
    }
  }

  void _askUserName() async {
    if (_isAskingName) return;
    
    // Ждем секунду, чтобы CartProvider успел загрузить имя из SharedPreferences
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final cart = Provider.of<CartProvider>(context, listen: false);
    
    // Если имя уже есть в памяти — ничего не показываем
    if (cart.userName != null && cart.userName!.isNotEmpty) return;

    if (!mounted) return;
    
    setState(() => _isAskingName = true);
    
    final controller = TextEditingController();
    String? localError;
    
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) => false,
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
                    if (localError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        localError!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: Colors.redAccent, 
                          fontSize: 12, 
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final name = controller.text.trim();
                          if (name.isEmpty) {
                            setDialogState(() => localError = "Пожалуйста, введите имя");
                            return;
                          }
                          if (name.length < 2) {
                            setDialogState(() => localError = "Имя должно быть не менее 2 символов");
                            return;
                          }
                          
                          // Проверяем уникальность имени за этим столом
                          final nameExists = cart.participants.any((p) {
                            final pName = p['user_name']?.toString().toLowerCase().trim();
                            return pName == name.toLowerCase() && p['device_id'] != cart.deviceId;
                          });
                          
                          if (nameExists) {
                            setDialogState(() => localError = "Имя '$name' уже занято за вашим столом.\nПожалуйста, добавьте к имени цифру или фамилию (например, $name 2).");
                            return;
                          }
                          
                          cart.setUserName(name);
                          Navigator.pop(ctx);
                          if (mounted) {
                            setState(() => _isAskingName = false);
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
          );
        },
      ),
    ).then((_) {
      controller.dispose();
      if (mounted) {
        setState(() => _isAskingName = false);
      }
    });
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
                        BannerCarousel(banners: _banners),
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
                'BONUM',
                style: GoogleFonts.forum(
                  color: Colors.white,
                  fontSize: 28,
                  height: 1.0,
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
          Transform.translate(
            offset: const Offset(0, -5),
            child: Text(
              'CAFE',
              textAlign: TextAlign.center,
              style: GoogleFonts.oswald(
                color: Colors.white38,
                fontSize: 11,
                height: 1.0,
                fontWeight: FontWeight.w500,
                letterSpacing: 4.0,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.access_time_rounded, color: Color(0xFFD4A043), size: 10),
              const SizedBox(width: 4),
              Text(
                'СЕГОДНЯ: ${SettingsService.getTodaySchedule()}',
                style: GoogleFonts.outfit(
                  color: Colors.white54,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (!_isDeliveryActive)
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
                  final waiterChatId = await TelegramService.getWaiterChatId(widget.tableId);
                  // В общий чат — без кнопки
                  await TelegramService.notifyWaiterCall(tableId: widget.tableId);
                  // Персонально официанту — с кнопкой «Иду!»
                  if (waiterChatId != null && waiterChatId.isNotEmpty) {
                    await TelegramService.notifyWaiterCall(
                      tableId: widget.tableId,
                      callId: callId.toString(),
                      customChatId: waiterChatId,
                    );
                  }
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
                final isDelivery = _isDeliveryActive;
                
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
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SharedCartScreen(tableNumber: Provider.of<CartProvider>(context, listen: false).tableId),
                      ),
                    );
                    
                    if (result == 'show_delivery') {
                      if (context.mounted) {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const DeliveryScreen(),
                        );
                      }
                    }
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
                      '${item.price.toInt()} сом',
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
    
    final totalParticipants = cart.participants.length;
 
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (totalParticipants > 1 && hasUnconfirmedItems) ...[
              Text(
                "ГОСТИ ЗА СТОЛОМ",
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.black38,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: totalParticipants,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, idx) {
                    final p = cart.participants[idx];
                    final isMe = p['device_id'] == cart.deviceId;
                    final name = isMe ? "Вы" : (p['user_name'] ?? "Гость ${p['guest_number'] ?? idx + 1}");
                    
                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A043).withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFD4A043).withOpacity(0.15),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 14,
                            color: Color(0xFFD4A043),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            name,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                          if (!isMe) ...[
                            GestureDetector(
                              onTap: () => _showRemoveParticipantDialog(context, cart, p),
                              behavior: HitTestBehavior.opaque,
                              child: const Padding(
                                padding: EdgeInsets.only(left: 6, right: 2),
                                child: Icon(
                                  Icons.cancel_rounded,
                                  size: 16,
                                  color: Colors.black38,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
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
              onPressed: (hasUnconfirmedItems) ? () => _onPressOrder(context, cart) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A043),
                foregroundColor: Colors.black,
                disabledBackgroundColor: isConfirmed ? const Color(0xFFE09E00).withOpacity(0.7) : Colors.grey.shade300,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                isConfirmed ? "ЗАКАЗ ПРИНЯТ" : 
                hasUnconfirmedItems ? "ЗАКАЗАТЬ" : "КОРЗИНА ПУСТА",
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveParticipantDialog(BuildContext context, CartProvider cart, Map<String, dynamic> participant) {
    final name = participant['user_name'] ?? "Гость ${participant['guest_number']}";
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_remove_rounded, color: Colors.redAccent, size: 32),
              ),
              const SizedBox(height: 20),
              Text(
                "УДАЛИТЬ ГОСТЯ?",
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Вы действительно хотите удалить гостя '$name'?\nЭто поможет, если он ушел или вкладка зависла.",
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text("ОТМЕНА", style: GoogleFonts.outfit(color: Colors.white54, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        cart.removeParticipant(participant['device_id']);
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: Text("УДАЛИТЬ", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
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

  void _onPressOrder(BuildContext context, CartProvider cart) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(24, 24, 24, 28 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A043).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFFD4A043), size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  "ПОДТВЕРЖДЕНИЕ ЗАКАЗА",
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Чтобы отправить заказ на кухню стола №${widget.tableNumber}, пожалуйста, отсканируйте QR-код на вашем столе для подтверждения присутствия в ресторане.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  "Если вы находитесь дома, оформите как доставку!",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _scanTableQr(context, cart);
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text("ОТКРЫТЬ КАМЕРУ (ПОДТВЕРДИТЬ СТОЛ)"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A043),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pop(context, 'show_delivery');
                    },
                    icon: const Icon(Icons.delivery_dining_rounded),
                    label: const Text("ОФОРМИТЬ КАК ДОСТАВКУ"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _scanTableQr(BuildContext context, CartProvider cart) async {
    final result = await scanQrCodeFromCameraGlobal();
    if (result != null && result.isNotEmpty) {
      try {
        final table = parseTableFromQr(result);
        
        if (table != null && (table == widget.tableNumber || table == 'table_${widget.tableNumber}')) {
          await cart.confirmOrder();
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Заказ успешно отправлен на кухню стола №$table! Приятного аппетита!',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                backgroundColor: const Color(0xFF4CAF50),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Неверный QR-код. Пожалуйста, отсканируйте код именно вашего стола №${widget.tableNumber}!',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Scan parsing error: $e');
      }
    }
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

  Map<String, dynamic>? _getBookingForTable(String tableId) {
    for (var b in _activeBookings) {
      if (b['table_id']?.toString() == tableId) {
        return b;
      }
    }
    return null;
  }

  void _selectAndShowBooking(Map<String, dynamic> table) {
    final booking = _getBookingForTable(table['id'].toString());
    
    if (booking != null) {
      final time = booking['booking_time'] ?? '';
      final endTime = booking['end_time'] ?? '';
      final label = table['label'] ?? 'Стол';
      
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.event_busy_rounded, color: Colors.redAccent, size: 24),
              ),
              const SizedBox(width: 12),
              Text('Стол №$label забронирован', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Этот стол уже забронирован на текущее время:', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 12),
              if (time.isNotEmpty)
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, color: Color(0xFFD4A043), size: 16),
                    const SizedBox(width: 8),
                    Text('Время брони: $time ${endTime.isNotEmpty ? "— $endTime" : ""}', 
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              if (endTime.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('⏳ Примерно освободится в $endTime', 
                    style: GoogleFonts.outfit(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A043), foregroundColor: Colors.black),
              child: const Text('Понятно', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
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
      _load();
      setState(() => _tempSelectedTableId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

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
                    margin: const EdgeInsets.symmetric(horizontal: 20),
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
                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Container(
                        width: 360,
                        height: 600,
                        decoration: BoxDecoration(
                          color: const Color(0xFF141414),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 40, offset: const Offset(0, 20))],
                        ),
                        child: _loading 
                          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
                          : _selectedFloorId == null
                            ? Center(child: Text('Схема залов не настроена', style: GoogleFonts.outfit(color: Colors.white38)))
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: InteractiveViewer(
                                  minScale: 0.8,
                                  maxScale: 3.5,
                                  child: SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        _buildHallScheme(),
                                        _buildExtraTablesList(),
                                        const SizedBox(height: 40), 
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LegendItem(color: const Color(0xFF4CAF50), label: 'Свободно'),
                      const SizedBox(width: 20),
                      _LegendItem(color: const Color(0xFFF44336), label: 'Забронировано'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    'Нажмите на свободный стол (зеленый) для бронирования',
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
    final placedTables = floorTables.where((t) => (t['pos_x'] as num) > 0 || (t['pos_y'] as num) > 0).toList();
    final planUrl = floor['plan_url'];

    return SizedBox(
      width: 360,
      height: 600,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xFF141414),
              child: planUrl != null && planUrl.toString().isNotEmpty
                  ? Image.network(
                      planUrl,
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)));
                      },
                      errorBuilder: (_, __, ___) => _buildGridFallback(),
                    )
                  : _buildGridFallback(),
            ),
          ),
          ...placedTables.map((table) {
            final double w = (table['width'] ?? 80).toDouble();
            final double h = (table['height'] ?? 80).toDouble();
            final double rotation = (table['rotation'] ?? 0).toDouble();
            double x = (table['pos_x'] as num).toDouble();
            double y = (table['pos_y'] as num).toDouble();

            final booking = _getBookingForTable(table['id'].toString());
            final bool isBooked = booking != null;
            final endTime = booking?['end_time'] ?? '';

            return Positioned(
              left: x - (w / 2),
              top: y - (h / 2),
              child: Transform.rotate(
                angle: rotation * (3.1415926535 / 180),
                child: GestureDetector(
                  onTap: () => _selectAndShowBooking(table),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: w,
                    height: h,
                    decoration: BoxDecoration(
                      color: (isBooked ? const Color(0xFFF44336) : const Color(0xFF4CAF50)).withOpacity(0.7),
                      borderRadius: BorderRadius.circular(w == h ? 50 : 12),
                      boxShadow: [
                        BoxShadow(
                          color: (isBooked ? const Color(0xFFF44336) : const Color(0xFF4CAF50)).withOpacity(0.4),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: w < 40 
                        ? Icon(
                            isBooked ? Icons.event_busy_rounded : Icons.chair_alt_rounded,
                            color: Colors.white.withOpacity(0.8),
                            size: w * 0.5,
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isBooked ? Icons.event_busy_rounded : Icons.chair_alt_rounded,
                                color: Colors.white.withOpacity(0.9),
                                size: w * 0.35,
                              ),
                              if (w >= 45) 
                                Flexible(
                                  child: Text(
                                    table['label'] ?? '',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white, 
                                      fontWeight: FontWeight.bold, 
                                      fontSize: (w * 0.15).clamp(8, 12),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (isBooked && endTime.isNotEmpty && w >= 55)
                                Flexible(
                                  child: Text(
                                    'до $endTime',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white.withOpacity(0.9), 
                                      fontWeight: FontWeight.bold, 
                                      fontSize: 8,
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
      ),
    );
  }

  Widget _buildExtraTablesList() {
    final floorTables = _tables.where((t) => t['floor_id'] == _selectedFloorId).toList();
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
            children: extraTables.map((table) {
              final booking = _getBookingForTable(table['id'].toString());
              final bool isBooked = booking != null;
              final endTime = booking?['end_time'] ?? '';

              return GestureDetector(
                onTap: () => _selectAndShowBooking(table),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 70, height: 70,
                  decoration: BoxDecoration(
                    color: isBooked ? const Color(0xFFF44336) : const Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                    boxShadow: [
                      if (_tempSelectedTableId == table['id'])
                        BoxShadow(color: const Color(0xFFD4A043).withOpacity(0.4), blurRadius: 10)
                      else
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        table['label'] ?? '',
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (isBooked && endTime.isNotEmpty)
                        Text(
                          'до $endTime',
                          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 8),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
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
  
  String _preorderType = 'onsite'; // onsite, dishes, banquet
  List<Map<String, dynamic>> _banquetSets = [];
  String? _selectedBanquetId;
  final List<MenuItem> _selectedDishes = [];
  bool _loadingBanquets = false;

  @override
  void initState() {
    super.initState();
    _loadBanquetSets();
  }

  Future<void> _loadBanquetSets() async {
    setState(() => _loadingBanquets = true);
    try {
      final res = await Supabase.instance.client.from('banquet_menu').select();
      if (mounted) setState(() => _banquetSets = List<Map<String, dynamic>>.from(res));
    } catch (e) {
      debugPrint('Load banquets error: $e');
    } finally {
      if (mounted) setState(() => _loadingBanquets = false);
    }
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
                  icon: const Icon(Icons.circle, color: Colors.black),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(primary: Colors.black),
                          ),
                          child: child!,
                        ),
                      ),
                    );
                    if (picked != null) {
                      final hh = picked.hour.toString().padLeft(2, '0');
                      final mm = picked.minute.toString().padLeft(2, '0');
                      setState(() => _timeController.text = '$hh:$mm');
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
                  icon: const Icon(Icons.circle, color: Colors.black),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: const TimeOfDay(hour: 21, minute: 0),
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(primary: Colors.black),
                          ),
                          child: child!,
                        ),
                      ),
                    );
                    if (picked != null) {
                      final hh = picked.hour.toString().padLeft(2, '0');
                      final mm = picked.minute.toString().padLeft(2, '0');
                      setState(() => _endTimeController.text = '$hh:$mm');
                    }
                  },
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              ),
            ),
            const SizedBox(height: 30),
            Text('ВАРИАНТ МЕНЮ', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 16),
            _buildPreorderTypeOption('onsite', 'Закажем когда придем', Icons.restaurant_rounded),
            const SizedBox(height: 8),
            _buildPreorderTypeOption('dishes', 'Выбрать блюда из меню', Icons.shopping_basket_rounded),
            const SizedBox(height: 8),
            _buildPreorderTypeOption('banquet', 'Банкетное меню', Icons.celebration_rounded),
            
            if (_preorderType == 'dishes') ...[
              const SizedBox(height: 20),
              _buildDishesPicker(),
            ],
            if (_preorderType == 'banquet') ...[
              const SizedBox(height: 20),
              _buildBanquetPicker(),
            ],
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
                    'status': 'confirmed',
                    'preorder_type': _preorderType,
                    'preorder_details': _getPreorderSummary(),
                  });

                  // 2. Помечаем стол как забронированный
                  await Supabase.instance.client
                      .from('restaurant_tables')
                      .update({'is_booked': true})
                      .eq('id', widget.table['id']);

                  // 3. Уведомляем в Telegram с полной информацией
                  final preorderInfo = _getPreorderSummary();
                  final msg = '📅 <b>БРОНЬ СТОЛА!</b>\n\n'
                      '🪑 Стол: <b>№${widget.table['label']}</b>\n'
                      '👤 Гость: <b>${_nameController.text}</b>\n'
                      '📞 Телефон: <b>$fullPhone</b>\n'
                      '👥 Гостей: <b>$guests</b>\n'
                      '⏰ Время: <b>${_timeController.text} — ${_endTimeController.text}</b>\n'
                      '${preorderInfo.isNotEmpty ? '\n🍽 <b>Предзаказ:</b> $preorderInfo' : ''}';

                  if (SettingsService.telegramNotify) {
                    final waiterChatId = await TelegramService.getWaiterChatId(widget.table['id'].toString());
                    // Отправляем и общий чат, и персонально официанту
                    await TelegramService.sendMessage(msg);
                    if (waiterChatId != null && waiterChatId.isNotEmpty) {
                      await TelegramService.sendMessage(msg, customChatId: waiterChatId);
                    }
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

  Widget _buildPreorderTypeOption(String type, String label, IconData icon) {
    final isSelected = _preorderType == type;
    return GestureDetector(
      onTap: () => setState(() => _preorderType = type),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.black : Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.black54),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: GoogleFonts.outfit(
                color: isSelected ? Colors.white : Colors.black,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              )),
            ),
            if (isSelected) const Icon(Icons.check_circle_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildDishesPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ВЫБЕРИТЕ БЛЮДА', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._selectedDishes.map((d) => Chip(
              label: Text(d.title),
              onDeleted: () => setState(() => _selectedDishes.remove(d)),
              backgroundColor: Colors.grey.shade100,
              labelStyle: GoogleFonts.outfit(fontSize: 12),
            )),
            ActionChip(
              label: const Text('+ Добавить'),
              onPressed: _showDishSelectionDialog,
              backgroundColor: const Color(0xFFD4A043).withOpacity(0.1),
              labelStyle: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBanquetPicker() {
    if (_loadingBanquets) return const Center(child: CircularProgressIndicator());
    if (_banquetSets.isEmpty) return const Text('Нет доступных банкетных сетов', style: TextStyle(fontSize: 12, color: Colors.black38));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ВЫБЕРИТЕ БАНКЕТНЫЙ СЕТ', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
        const SizedBox(height: 12),
        ..._banquetSets.map((s) {
          final isSelected = _selectedBanquetId == s['id'];
          return GestureDetector(
            onTap: () => setState(() => _selectedBanquetId = s['id']),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFD4A043).withOpacity(0.1) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? const Color(0xFFD4A043) : Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: s['image_url'] != null && s['image_url'].toString().isNotEmpty
                        ? Image.network(s['image_url'], width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_,__,___) => _banquetPh())
                        : _banquetPh(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s['title'], style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            Text(s['price'].toString() + ' сом/чел', style: GoogleFonts.outfit(fontSize: 12, color: Colors.black54)),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => _showBanquetDetails(s),
                              child: Text('Посмотреть состав', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFFD4A043), fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isSelected) const Icon(Icons.check_circle, color: Color(0xFFD4A043)),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  void _showDishSelectionDialog() {
    final allItems = MenuDataService.items;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выберите блюдо'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: allItems.length,
            itemBuilder: (_, i) {
              final item = allItems[i];
              return ListTile(
                title: Text(item.title),
                subtitle: Text(item.price.toString() + ' сом'),
                onTap: () {
                  setState(() => _selectedDishes.add(item));
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  String _getPreorderSummary() {
    if (_preorderType == 'onsite') return 'Заказ на месте';
    if (_preorderType == 'dishes') {
      if (_selectedDishes.isEmpty) return 'Блюда не выбраны';
      final lines = _selectedDishes.map((d) => '• ${d.title} — ${d.price.toInt()} сом').join('\n');
      final total = _selectedDishes.fold<double>(0, (sum, d) => sum + d.price);
      return '\n$lines\n💰 Итого: ${total.toInt()} сом';
    }
    if (_preorderType == 'banquet') {
      final s = _banquetSets.firstWhere((x) => x['id'] == _selectedBanquetId, orElse: () => {});
      if (s.isEmpty) return 'Банкет не выбран';
      return 'Банкет: ${s['title']} (${s['price']} сом/чел × $guests = ${(s['price'] as num) * guests} сом)';
    }
    return '';
  }

  Widget _banquetPh() {
    return Container(
      width: 50, height: 50, 
      color: Colors.grey.shade100, 
      child: const Icon(Icons.celebration_rounded, color: Colors.black12, size: 24),
    );
  }

  void _showBanquetDetails(Map set) async {
    final List<dynamic> dishIds = set['dish_ids'] ?? [];
    if (dishIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('В этом сете пока нет блюд')));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder(
        future: Supabase.instance.client.from('menu_items_db').select().inFilter('id', dishIds),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final dishes = snap.data as List? ?? [];
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text('Состав: ${set['title']}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: dishes.length,
                itemBuilder: (_, i) {
                  final d = dishes[i];
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildSmartImage(d['photo_url'] ?? '', width: 40, height: 40),
                    ),
                    title: Text(d['title'], style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold)),
                    subtitle: Text(d['description'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть', style: TextStyle(color: Colors.black))),
            ],
          );
        },
      ),
    );
  }

  void _showError(String msg) {
    setState(() => _localError = msg);
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

/// Мини-страница для официанта — открывается по ссылке из Telegram.
/// Автоматически принимает вызов и показывает подтверждение.
class _AcceptCallPage extends StatefulWidget {
  final String callId;
  const _AcceptCallPage({required this.callId});

  @override
  State<_AcceptCallPage> createState() => _AcceptCallPageState();
}

class _AcceptCallPageState extends State<_AcceptCallPage> {
  bool _loading = true;
  bool _success = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _acceptCall();
  }

  Future<void> _acceptCall() async {
    try {
      final ok = await TelegramService.acceptWaiterCall(widget.callId);
      if (mounted) {
        setState(() {
          _loading = false;
          _success = ok;
          if (!ok) _error = 'Не удалось принять вызов';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Ошибка: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_loading) ...[
                const CircularProgressIndicator(color: Color(0xFFD4A043)),
                const SizedBox(height: 24),
                Text(
                  'Принимаю вызов...',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 16),
                ),
              ] else if (_success) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.green, size: 64),
                ),
                const SizedBox(height: 24),
                Text(
                  'ВЫЗОВ ПРИНЯТ ✅',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Гость видит, что вы уже идёте!',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 16),
                ),
                const SizedBox(height: 32),
                Text(
                  'Можете закрыть эту страницу',
                  style: GoogleFonts.outfit(color: Colors.white24, fontSize: 14),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 64),
                ),
                const SizedBox(height: 24),
                Text(
                  _error ?? 'Ошибка',
                  style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 18),
                ),
                const SizedBox(height: 16),
                Text(
                  'Возможно, вызов уже был принят',
                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Мини-страница для официанта — открывается по ссылке из Telegram.
/// Автоматически принимает заказ и показывает подтверждение.
class _AcceptOrderPage extends StatefulWidget {
  final String tableId;
  const _AcceptOrderPage({required this.tableId});

  @override
  State<_AcceptOrderPage> createState() => _AcceptOrderPageState();
}

class _AcceptOrderPageState extends State<_AcceptOrderPage> {
  bool _loading = true;
  bool _success = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _acceptOrder();
  }

  Future<void> _acceptOrder() async {
    try {
      final ok = await TelegramService.acceptTableOrder(widget.tableId);
      if (mounted) {
        setState(() {
          _loading = false;
          _success = ok;
          if (!ok) _error = 'Не удалось принять заказ';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Ошибка: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_loading) ...[
                const CircularProgressIndicator(color: Color(0xFFD4A043)),
                const SizedBox(height: 24),
                Text(
                  'Принимаю заказ...',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 16),
                ),
              ] else if (_success) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.green, size: 64),
                ),
                const SizedBox(height: 24),
                Text(
                  'ЗАКАЗ ПРИНЯТ ✅',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Гости увидят, что их заказ готовится!',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 16),
                ),
                const SizedBox(height: 32),
                Text(
                  'Можете закрыть эту страницу',
                  style: GoogleFonts.outfit(color: Colors.white24, fontSize: 14),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 64),
                ),
                const SizedBox(height: 24),
                Text(
                  _error ?? 'Ошибка',
                  style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 18),
                ),
                const SizedBox(height: 16),
                Text(
                  'Возможно, заказ уже был принят',
                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
