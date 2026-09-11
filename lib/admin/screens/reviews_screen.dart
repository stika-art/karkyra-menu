import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/reviews_service.dart';

enum ReviewFilter { all, five, four, low }

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  bool _loading = true;
  List<ReviewItem> _reviews = [];
  ReviewFilter _selectedFilter = ReviewFilter.all;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    setState(() => _loading = true);
    final data = await ReviewsService.loadReviews();
    if (mounted) {
      setState(() {
        _reviews = data;
        _loading = false;
      });
    }
  }

  Future<void> _confirmDelete(ReviewItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Удалить отзыв?',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Отзыв от ${item.guestName} (${item.rating}★) будет удалён из системы. Это действие нельзя отменить.',
          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: GoogleFonts.outfit(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Удалить',
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (ok == true) {
      final success = await ReviewsService.deleteReview(item.id);
      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Отзыв успешно удалён из системы ✅', style: GoogleFonts.outfit()),
            backgroundColor: Colors.green,
          ),
        );
        _loadReviews();
      }
    }
  }

  List<ReviewItem> get _filteredReviews {
    switch (_selectedFilter) {
      case ReviewFilter.all:
        return _reviews;
      case ReviewFilter.five:
        return _reviews.where((r) => r.rating == 5).toList();
      case ReviewFilter.four:
        return _reviews.where((r) => r.rating == 4).toList();
      case ReviewFilter.low:
        return _reviews.where((r) => r.rating <= 3).toList();
    }
  }

  double get _averageRating {
    if (_reviews.isEmpty) return 5.0;
    final sum = _reviews.fold<int>(0, (acc, r) => acc + r.rating);
    return sum / _reviews.length;
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} мин назад';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} ч назад';
    } else {
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      final hour = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$day.$month в $hour:$min';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredReviews;
    final fiveCount = _reviews.where((r) => r.rating == 5).length;
    final fourCount = _reviews.where((r) => r.rating == 4).length;
    final lowCount = _reviews.where((r) => r.rating <= 3).length;

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: Column(
        children: [
          _buildHeader(),
          _buildFilterChips(fiveCount: fiveCount, fourCount: fourCount, lowCount: lowCount),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
                : RefreshIndicator(
                    onRefresh: _loadReviews,
                    color: const Color(0xFFD4A043),
                    backgroundColor: const Color(0xFF1E1E1E),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _buildKpiSection(fiveCount: fiveCount, lowCount: lowCount),
                        const SizedBox(height: 20),
                        if (filtered.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(40),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.rate_review_outlined, color: Colors.white24, size: 48),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Отзывов по данному фильтру нет',
                                    style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ...filtered.map((item) => _buildReviewCard(item)),
                        const SizedBox(height: 30),
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
                'Отзывы гостей',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Рейтинг, оценки столов и модерация отзывов',
                style: GoogleFonts.outfit(
                  color: Colors.white38,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: _loadReviews,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFD4A043)),
            tooltip: 'Обновить список',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips({
    required int fiveCount,
    required int fourCount,
    required int lowCount,
  }) {
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chip('Все (${_reviews.length})', ReviewFilter.all),
            _chip('5 звезд ($fiveCount)', ReviewFilter.five),
            _chip('4 звезды ($fourCount)', ReviewFilter.four),
            _chip(
              '1-3 звезды ($lowCount)',
              ReviewFilter.low,
              hasWarning: lowCount > 0,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, ReviewFilter filter, {bool hasWarning = false}) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFD4A043)
              : (hasWarning ? Colors.redAccent.withOpacity(0.12) : const Color(0xFF242424)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFD4A043)
                : (hasWarning ? Colors.redAccent.withOpacity(0.4) : Colors.white12),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isSelected
                ? Colors.black
                : (hasWarning ? Colors.redAccent : Colors.white70),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildKpiSection({required int fiveCount, required int lowCount}) {
    final avg = _averageRating;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 650;
        final cardWidth = isWide ? (constraints.maxWidth - 24) / 3 : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            Container(
              width: cardWidth,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD4A043).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A043).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.star_rounded, color: Color(0xFFD4A043), size: 28),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _reviews.isEmpty ? '—' : '${avg.toStringAsFixed(1)} / 5.0',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFFD4A043),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Средняя оценка заведения',
                        style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: cardWidth,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.thumb_up_alt_rounded, color: Colors.green, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$fiveCount',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Отличных отзывов (5★)',
                        style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: cardWidth,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: lowCount > 0 ? Colors.redAccent.withOpacity(0.4) : Colors.white10,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: lowCount > 0
                          ? Colors.redAccent.withOpacity(0.15)
                          : Colors.grey.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: lowCount > 0 ? Colors.redAccent : Colors.grey,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$lowCount',
                        style: GoogleFonts.outfit(
                          color: lowCount > 0 ? Colors.redAccent : Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Низких оценок (1–3★)',
                        style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReviewCard(ReviewItem item) {
    final isNegative = item.rating <= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isNegative ? Colors.redAccent.withOpacity(0.35) : Colors.white10,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4A043).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.tableId.toLowerCase().contains('delivery') || item.tableId == 'Доставка'
                      ? 'Доставка'
                      : (item.tableId.isEmpty || item.tableId == '0' ? 'Онлайн' : 'Стол №${item.tableId}'),
                  style: GoogleFonts.outfit(
                    color: const Color(0xFFD4A043),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.guestName,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(item.createdAt),
                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(width: 6),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _confirmDelete(item),
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                tooltip: 'Удалить отзыв',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (i) {
              final active = i < item.rating;
              return Icon(
                active ? Icons.star_rounded : Icons.star_border_rounded,
                color: active
                    ? (isNegative ? Colors.orangeAccent : const Color(0xFFD4A043))
                    : Colors.white24,
                size: 18,
              );
            }),
          ),
          if (item.comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              item.comment,
              style: GoogleFonts.outfit(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
