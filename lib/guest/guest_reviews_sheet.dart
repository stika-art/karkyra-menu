import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/reviews_service.dart';

/// Открывает модальное окно со всеми отзывами гостей и рейтингом заведения
void showGuestReviewsSheet(
  BuildContext context, {
  String tableId = '',
  required Function(BuildContext context, {String tableId}) onLeaveReview,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => GuestReviewsSheetContent(
      tableId: tableId,
      onLeaveReview: onLeaveReview,
    ),
  );
}

class GuestReviewsSheetContent extends StatefulWidget {
  final String tableId;
  final Function(BuildContext context, {String tableId}) onLeaveReview;

  const GuestReviewsSheetContent({
    super.key,
    required this.tableId,
    required this.onLeaveReview,
  });

  @override
  State<GuestReviewsSheetContent> createState() => _GuestReviewsSheetContentState();
}

class _GuestReviewsSheetContentState extends State<GuestReviewsSheetContent> {
  bool _isLoading = true;
  List<ReviewItem> _reviewsList = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final list = await ReviewsService.loadReviews();
    if (mounted) {
      setState(() {
        _reviewsList = list;
        _isLoading = false;
      });
    }
  }

  double get _averageRating {
    if (_reviewsList.isEmpty) return 5.0;
    final sum = _reviewsList.fold<num>(0, (prev, el) => prev + el.rating);
    return (sum / _reviewsList.length * 10).roundToDouble() / 10;
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    final padMin = dt.minute.toString().padLeft(2, '0');
    final padHour = dt.hour.toString().padLeft(2, '0');

    if (diff.inDays == 0 && dt.day == now.day) {
      return 'Сегодня в ' + padHour + ':' + padMin;
    } else if (diff.inDays <= 1 && dt.day == now.day - 1) {
      return 'Вчера в ' + padHour + ':' + padMin;
    } else {
      const months = [
        'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
        'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
      ];
      final m = months[(dt.month - 1).clamp(0, 11)];
      return dt.day.toString() + ' ' + m + ', ' + padHour + ':' + padMin;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final avg = _averageRating;
    final count = _reviewsList.length;

    return Container(
      height: screenHeight * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF19191B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // Заголовок и кнопка закрытия
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ОТЗЫВЫ ГОСТЕЙ',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
                      Text(
                        'Bonum Cafe • Рейтинг и впечатления',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFFD4A043),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  tooltip: 'Закрыть',
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Плашка среднего рейтинга и кнопка оставить отзыв
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFD4A043).withOpacity(0.18),
                    const Color(0xFF262626),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFD4A043).withOpacity(0.4),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  // Крупный балл
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            avg.toStringAsFixed(1),
                            style: GoogleFonts.outfit(
                              color: const Color(0xFFD4A043),
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.star_rounded, color: Color(0xFFD4A043), size: 24),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        count == 0
                            ? 'Первые отзывы'
                            : '$count ' + (count == 1 ? 'отзыв' : (count < 5 ? 'отзыва' : 'отзывов')),
                        style: GoogleFonts.outfit(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Кнопка Оставить отзыв
                  ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      widget.onLeaveReview(context, tableId: widget.tableId);
                    },
                    icon: const Icon(Icons.rate_review_rounded, size: 16, color: Colors.black),
                    label: Text(
                      'Оценить',
                      style: GoogleFonts.outfit(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4A043),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),

          // Список отзывов
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFD4A043)),
                  )
                : _reviewsList.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4A043).withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.star_rounded,
                                  color: Color(0xFFD4A043),
                                  size: 44,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Пока нет отзывов',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Будьте первым гостем, кто поделится своими впечатлениями о сервисе и блюдах!',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        itemCount: _reviewsList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _reviewsList[index];
                          final initial = item.guestName.isNotEmpty
                              ? item.guestName.characters.first.toUpperCase()
                              : 'Г';

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF242426),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.06),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Верх карточки: Аватар, имя, стол, дата
                                Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFD4A043).withOpacity(0.2),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFFD4A043).withOpacity(0.5),
                                          width: 1,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        initial,
                                        style: GoogleFonts.outfit(
                                          color: const Color(0xFFD4A043),
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.guestName,
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            _formatDate(item.createdAt),
                                            style: GoogleFonts.outfit(
                                              color: Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (item.tableId.isNotEmpty && item.tableId != '0')
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.08),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.white12),
                                        ),
                                        child: Text(
                                          'Стол №' + item.tableId,
                                          style: GoogleFonts.outfit(
                                            color: const Color(0xFFD4A043),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                // Звездочки оценки
                                Row(
                                  children: List.generate(5, (starIdx) {
                                    final filled = starIdx < item.rating;
                                    return Icon(
                                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                                      color: filled ? const Color(0xFFD4A043) : Colors.white24,
                                      size: 17,
                                    );
                                  }),
                                ),

                                // Текст комментария
                                if (item.comment.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    item.comment,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white.withOpacity(0.88),
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
