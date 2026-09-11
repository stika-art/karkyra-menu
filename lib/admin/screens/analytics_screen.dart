import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/menu_data_service.dart';
import '../../models/menu_item.dart';

enum AnalyticsPeriod { today, yesterday, week, month, all }

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  AnalyticsPeriod _selectedPeriod = AnalyticsPeriod.today;
  bool _isLoading = true;

  List<Map<String, dynamic>> _rawTableOrders = [];
  List<Map<String, dynamic>> _rawDeliveryOrders = [];
  List<Map<String, dynamic>> _rawCalls = [];
  Map<String, String> _tableLabels = {};
  Map<String, Map<String, dynamic>> _menuMap = {};
  RealtimeChannel? _ordersSub;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _ordersSub?.unsubscribe();
    super.dispose();
  }

  void _subscribeRealtime() {
    try {
      _ordersSub = Supabase.instance.client
          .channel('public:orders_analytics_feed')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders_new',
            callback: (payload) {
              if (mounted) {
                _fetchData(silent: true);
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Realtime sub error in analytics: $e');
    }
  }

  Future<void> _fetchData({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      if (MenuDataService.items.isEmpty) {
        await MenuDataService.load();
      }

      // 1. Загружаем все блюда напрямую из базы (включая стоп-лист и архив) для 100% точности цен
      final menuItemsRes = await Supabase.instance.client
          .from('menu_items_db')
          .select('id, title, price, photo_url')
          .timeout(const Duration(seconds: 8));

      final Map<String, Map<String, dynamic>> mMap = {};
      for (var m in (menuItemsRes as List)) {
        mMap[m['id'].toString()] = Map<String, dynamic>.from(m);
      }

      final tableRes = await Supabase.instance.client
          .from('orders_new')
          .select()
          .neq('status', 'ordering')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));

      final deliveryRes = await Supabase.instance.client
          .from('delivery_orders')
          .select()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));

      final callsRes = await Supabase.instance.client
          .from('waiter_calls')
          .select()
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));

      final tablesRes = await Supabase.instance.client
          .from('restaurant_tables')
          .select('id, label');

      final Map<String, String> tMap = {};
      for (var t in (tablesRes as List)) {
        tMap[t['id'].toString()] = t['label']?.toString() ?? t['id'].toString();
      }

      if (mounted) {
        setState(() {
          _rawTableOrders = List<Map<String, dynamic>>.from(tableRes);
          _rawDeliveryOrders = List<Map<String, dynamic>>.from(deliveryRes);
          _rawCalls = List<Map<String, dynamic>>.from(callsRes);
          _tableLabels = tMap;
          _menuMap = mMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Analytics load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _filterByDate(String? createdAtStr) {
    if (createdAtStr == null) return false;
    final dt = DateTime.tryParse(createdAtStr)?.toLocal();
    if (dt == null) return false;

    final now = DateTime.now();
    switch (_selectedPeriod) {
      case AnalyticsPeriod.today:
        return dt.year == now.year && dt.month == now.month && dt.day == now.day;
      case AnalyticsPeriod.yesterday:
        final y = now.subtract(const Duration(days: 1));
        return dt.year == y.year && dt.month == y.month && dt.day == y.day;
      case AnalyticsPeriod.week:
        return dt.isAfter(now.subtract(const Duration(days: 7)));
      case AnalyticsPeriod.month:
        return dt.isAfter(now.subtract(const Duration(days: 30)));
      case AnalyticsPeriod.all:
        return true;
    }
  }

  String _getItemTitle(String? id) {
    if (id == null || id.isEmpty) return 'Блюдо';
    if (_menuMap.containsKey(id)) {
      final t = _menuMap[id]!['title']?.toString();
      if (t != null && t.isNotEmpty) return t;
    }
    final m = _findMenuItem(id);
    return m?.title ?? 'Блюдо #$id';
  }

  double _getItemPrice(String? id) {
    if (id == null || id.isEmpty) return 0.0;
    if (_menuMap.containsKey(id)) {
      final p = (_menuMap[id]!['price'] as num?)?.toDouble();
      if (p != null && p > 0) return p;
    }
    final m = _findMenuItem(id);
    return m?.price ?? 0.0;
  }

  String _getItemImage(String? id) {
    if (id == null || id.isEmpty) return '';
    if (_menuMap.containsKey(id)) {
      final img = _menuMap[id]!['photo_url']?.toString();
      if (img != null && img.isNotEmpty) return img;
    }
    final m = _findMenuItem(id);
    return (m != null && m.images.isNotEmpty) ? m.images.first : '';
  }

  MenuItem? _findMenuItem(String? id) {
    if (id == null) return null;
    try {
      return MenuDataService.items.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  String _formatMoney(double amount) {
    final rounded = amount.round();
    final str = rounded.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i > 0) buffer.write(' ');
    }
    final formatted = buffer.toString().split('').reversed.join('');
    return '$formatted сом';
  }

  @override
  Widget build(BuildContext context) {
    final filteredTableOrders = _rawTableOrders.where((o) {
      if (o['status'] == 'cancelled') return false;
      return _filterByDate(o['created_at']);
    }).toList();
    final filteredDeliveryOrders = _rawDeliveryOrders.where((d) {
      if (d['status'] == 'cancelled') return false;
      return _filterByDate(d['created_at']);
    }).toList();
    final filteredCalls = _rawCalls.where((c) => _filterByDate(c['created_at'])).toList();

    // Расчет выручки за столами
    double tableRevenue = 0;
    for (var o in filteredTableOrders) {
      final mId = o['menu_item_id']?.toString();
      final qty = (o['quantity'] as num?)?.toInt() ?? 1;
      final price = _getItemPrice(mId);
      tableRevenue += price * qty;
    }

    // Расчет выручки доставки
    double deliveryRevenue = 0;
    for (var d in filteredDeliveryOrders) {
      final t = (d['total'] as num?)?.toDouble() ?? 0.0;
      deliveryRevenue += t;
    }

    final totalRevenue = tableRevenue + deliveryRevenue;

    // Группировка заказов столов по сессиям (стол + временной интервал ~1 час)
    final Set<String> tableOrderSessions = {};
    for (var o in filteredTableOrders) {
      final tId = o['table_id']?.toString() ?? '';
      final dt = DateTime.tryParse(o['created_at']?.toString() ?? '')?.toLocal();
      final hourKey = dt != null ? '${dt.year}-${dt.month}-${dt.day}_${dt.hour}' : '';
      tableOrderSessions.add('${tId}_$hourKey');
    }
    final int tableOrderCount = tableOrderSessions.isEmpty ? (filteredTableOrders.isEmpty ? 0 : 1) : tableOrderSessions.length;
    final int deliveryOrderCount = filteredDeliveryOrders.length;
    final int totalOrders = tableOrderCount + deliveryOrderCount;

    final double avgCheck = totalOrders > 0 ? (totalRevenue / totalOrders) : 0.0;

    // Топ блюд (зал + доставка)
    final Map<String, _DishStat> dishStats = {};
    for (var o in filteredTableOrders) {
      final mId = o['menu_item_id']?.toString() ?? '';
      if (mId.isEmpty) continue;
      final qty = (o['quantity'] as num?)?.toInt() ?? 1;
      final price = _getItemPrice(mId);
      final rev = price * qty;

      if (!dishStats.containsKey(mId)) {
        dishStats[mId] = _DishStat(
          id: mId,
          title: _getItemTitle(mId),
          imageUrl: _getItemImage(mId),
          price: price,
          quantity: qty,
          revenue: rev,
        );
      } else {
        dishStats[mId]!.quantity += qty;
        dishStats[mId]!.revenue += rev;
      }
    }

    for (var d in filteredDeliveryOrders) {
      final items = d['items'];
      if (items is List) {
        for (var it in items) {
          if (it is Map) {
            final title = it['title']?.toString() ?? 'Блюдо';
            final qty = (it['qty'] as num?)?.toInt() ?? 1;
            final price = (it['price'] as num?)?.toDouble() ?? 0.0;
            final rev = price * qty;
            final key = 'del_$title';

            if (!dishStats.containsKey(key)) {
              dishStats[key] = _DishStat(
                id: key,
                title: title,
                imageUrl: '',
                price: price,
                quantity: qty,
                revenue: rev,
              );
            } else {
              dishStats[key]!.quantity += qty;
              dishStats[key]!.revenue += rev;
            }
          }
        }
      }
    }

    final topDishes = dishStats.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    final top5Dishes = topDishes.take(5).toList();

    // Статистика по столам
    final Map<String, _TableStat> tableStats = {};
    for (var o in filteredTableOrders) {
      final tId = o['table_id']?.toString() ?? 'Не указан';
      final qty = (o['quantity'] as num?)?.toInt() ?? 1;
      final price = _getItemPrice(o['menu_item_id']?.toString());
      final rev = price * qty;

      if (!tableStats.containsKey(tId)) {
        tableStats[tId] = _TableStat(
          tableId: tId,
          label: _tableLabels[tId] ?? tId,
          itemsCount: qty,
          revenue: rev,
        );
      } else {
        tableStats[tId]!.itemsCount += qty;
        tableStats[tId]!.revenue += rev;
      }
    }
    final topTables = tableStats.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: Column(
        children: [
          _buildHeader(),
          _buildPeriodSelector(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFD4A043)),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchData,
                    color: const Color(0xFFD4A043),
                    backgroundColor: const Color(0xFF1E1E1E),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _buildKpiGrid(
                          totalRevenue: totalRevenue,
                          totalOrders: totalOrders,
                          avgCheck: avgCheck,
                          callsCount: filteredCalls.length,
                        ),
                        const SizedBox(height: 24),
                        _buildRevenueSplitCard(
                          totalRevenue: totalRevenue,
                          tableRevenue: tableRevenue,
                          deliveryRevenue: deliveryRevenue,
                          tableOrdersCount: tableOrderCount,
                          deliveryOrdersCount: deliveryOrderCount,
                        ),
                        const SizedBox(height: 24),
                        _buildTopDishesCard(top5Dishes, totalRevenue),
                        const SizedBox(height: 24),
                        _buildTopTablesCard(topTables.take(6).toList(), tableRevenue),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
      color: const Color(0xFF1A1A1A),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Аналитика',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Выручка, средний чек и показатели продаж',
                style: GoogleFonts.outfit(
                  color: Colors.white38,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: _fetchData,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFD4A043)),
            tooltip: 'Обновить данные',
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _periodChip('Сегодня', AnalyticsPeriod.today),
            _periodChip('Вчера', AnalyticsPeriod.yesterday),
            _periodChip('7 дней', AnalyticsPeriod.week),
            _periodChip('30 дней', AnalyticsPeriod.month),
            _periodChip('Всё время', AnalyticsPeriod.all),
          ],
        ),
      ),
    );
  }

  Widget _periodChip(String label, AnalyticsPeriod period) {
    final isSelected = _selectedPeriod == period;
    return GestureDetector(
      onTap: () => setState(() => _selectedPeriod = period),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD4A043) : const Color(0xFF242424),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFD4A043) : Colors.white12,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildKpiGrid({
    required double totalRevenue,
    required int totalOrders,
    required double avgCheck,
    required int callsCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 650;
        final cardWidth = isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpiCard(
              title: 'Общая выручка',
              value: _formatMoney(totalRevenue),
              icon: Icons.payments_rounded,
              color: const Color(0xFFD4A043),
              width: cardWidth,
            ),
            _kpiCard(
              title: 'Всего заказов',
              value: '$totalOrders',
              icon: Icons.receipt_long_rounded,
              color: const Color(0xFF2196F3),
              width: cardWidth,
            ),
            _kpiCard(
              title: 'Средний чек',
              value: _formatMoney(avgCheck),
              icon: Icons.trending_up_rounded,
              color: const Color(0xFF4CAF50),
              width: cardWidth,
            ),
            _kpiCard(
              title: 'Вызовов официанта',
              value: '$callsCount',
              icon: Icons.notifications_active_rounded,
              color: const Color(0xFFFF9800),
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueSplitCard({
    required double totalRevenue,
    required double tableRevenue,
    required double deliveryRevenue,
    required int tableOrdersCount,
    required int deliveryOrdersCount,
  }) {
    final double tableRatio = totalRevenue > 0 ? (tableRevenue / totalRevenue) : 0.5;
    final double deliveryRatio = totalRevenue > 0 ? (deliveryRevenue / totalRevenue) : 0.5;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Каналы продаж',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Зал vs Доставка',
                style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(
                    flex: (tableRatio * 100).round().clamp(1, 99),
                    child: Container(color: const Color(0xFFD4A043)),
                  ),
                  Expanded(
                    flex: (deliveryRatio * 100).round().clamp(1, 99),
                    child: Container(color: const Color(0xFF2196F3)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFD4A043), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Зал ресторана', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            '${_formatMoney(tableRevenue)} • $tableOrdersCount заказов (${(tableRatio * 100).round()}%)',
                            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF2196F3), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Доставка', style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            '${_formatMoney(deliveryRevenue)} • $deliveryOrdersCount заказов (${(deliveryRatio * 100).round()}%)',
                            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopDishesCard(List<_DishStat> dishes, double totalRevenue) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Топ-5 блюд по выручке',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(Icons.emoji_events_rounded, color: Color(0xFFD4A043), size: 20),
            ],
          ),
          const SizedBox(height: 16),
          if (dishes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Нет данных о продажах за выбранный период',
                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                ),
              ),
            )
          else
            ...List.generate(dishes.length, (i) {
              final d = dishes[i];
              final share = totalRevenue > 0 ? (d.revenue / totalRevenue) : 0.0;
              final medals = ['🥇', '🥈', '🥉', '4', '5'];

              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            medals[i],
                            style: GoogleFonts.outfit(
                              fontSize: i < 3 ? 16 : 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 38,
                            height: 38,
                            color: const Color(0xFF2A2A2A),
                            child: d.imageUrl.isNotEmpty
                                ? Image.network(
                                    d.imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.restaurant, color: Colors.white24, size: 18),
                                  )
                                : const Icon(Icons.restaurant, color: Colors.white24, size: 18),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '${d.quantity} порций • ${_formatMoney(d.price)}/шт',
                                style: GoogleFonts.outfit(
                                  color: Colors.white38,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatMoney(d.revenue),
                          style: GoogleFonts.outfit(
                            color: const Color(0xFFD4A043),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: share.clamp(0.0, 1.0),
                        backgroundColor: Colors.white.withOpacity(0.06),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          i == 0 ? const Color(0xFFD4A043) : const Color(0xFFD4A043).withOpacity(0.6),
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTopTablesCard(List<_TableStat> tables, double totalTableRevenue) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Активность столов в зале',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(Icons.table_restaurant_rounded, color: Color(0xFFD4A043), size: 20),
            ],
          ),
          const SizedBox(height: 16),
          if (tables.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Нет заказов со столов за выбранный период',
                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                ),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: tables.map((t) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF262626),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4A043).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          t.label.contains('№') ? t.label : '№ ${t.label}',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFFD4A043),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatMoney(t.revenue),
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${t.itemsCount} позиций',
                            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _DishStat {
  final String id;
  final String title;
  final String imageUrl;
  final double price;
  int quantity;
  double revenue;

  _DishStat({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.price,
    required this.quantity,
    required this.revenue,
  });
}

class _TableStat {
  final String tableId;
  final String label;
  int itemsCount;
  double revenue;

  _TableStat({
    required this.tableId,
    required this.label,
    required this.itemsCount,
    required this.revenue,
  });
}
