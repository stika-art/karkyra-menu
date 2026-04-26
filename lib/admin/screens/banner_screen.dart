import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';

class BannerScreen extends StatefulWidget {
  const BannerScreen({super.key});

  @override
  State<BannerScreen> createState() => _BannerScreenState();
}

class _BannerScreenState extends State<BannerScreen> {
  List<Map<String, dynamic>> _banners = [];
  bool _loading = true;
  bool _uploading = false;
  double _uploadProgress = 0;
  String _uploadStatus = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .from('banners')
          .select()
          .order('created_at', ascending: false);
      setState(() {
        _banners = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // --- Загрузка локального файла ---
  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mov', 'webm', 'jpg', 'jpeg', 'png', 'gif', 'webp'],
      withData: true, // Получаем байты файла для веба
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    final fileName = file.name;
    final ext = fileName.split('.').last.toLowerCase();
    final isVideo = ['mp4', 'mov', 'webm'].contains(ext);
    final type = isVideo ? 'video' : 'image';

    // Уникальное имя файла
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'banners/$timestamp\_$fileName';

    setState(() {
      _uploading = true;
      _uploadProgress = 0;
      _uploadStatus = 'Загрузка файла...';
    });

    try {
      // Загружаем в Supabase Storage
      await Supabase.instance.client.storage.from('media').uploadBinary(
        storagePath,
        file.bytes!,
        fileOptions: FileOptions(
          contentType: isVideo ? 'video/$ext' : 'image/$ext',
          upsert: true,
        ),
      );

      setState(() => _uploadStatus = 'Получение ссылки...');

      // Получаем публичный URL (явно преобразуем в строку)
      final String publicUrl = Supabase.instance.client.storage
          .from('media')
          .getPublicUrl(storagePath);


      // Сохраняем в таблицу
      await Supabase.instance.client.from('banners').insert({
        'url': publicUrl,
        'type': type,
        'filename': fileName,
        'is_active': true,
      });

      setState(() {
        _uploading = false;
        _uploadStatus = '';
        _uploadProgress = 1.0;
      });

      _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${isVideo ? "Видео" : "Изображение"} загружено и активировано!',
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('UPLOAD ERROR: $e');
      setState(() {
        _uploading = false;
        _uploadStatus = '';
      });
      if (mounted) {
        String errorMsg = e.toString();
        if (errorMsg.contains('Failed to fetch')) {
          errorMsg = 'Ошибка сети/CORS: Проверьте настройки CORS в Supabase Storage';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg, style: GoogleFonts.outfit()),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // --- Добавление по URL ---
  void _showAddByUrl() {
    final urlCtrl = TextEditingController();
    String bannerType = 'video';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text('Добавить по URL',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlCtrl,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'https://example.com/video.mp4',
                  hintStyle: GoogleFonts.outfit(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFFD4A043)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _typeBtn('video', '🎬 Видео', bannerType, (v) => setD(() => bannerType = v))),
                const SizedBox(width: 8),
                Expanded(child: _typeBtn('image', '🖼 Фото', bannerType, (v) => setD(() => bannerType = v))),
              ]),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Отмена', style: GoogleFonts.outfit(color: Colors.white38))),
            ElevatedButton(
              onPressed: () async {
                if (urlCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                await Supabase.instance.client
                    .from('banners')
                    .update({'is_active': false})
                    .eq('is_active', true);
                await Supabase.instance.client.from('banners').insert({
                  'url': urlCtrl.text.trim(),
                  'type': bannerType,
                  'is_active': true,
                });
                _load();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4A043), foregroundColor: Colors.black),
              child: Text('Добавить', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeBtn(String type, String label, String current, ValueChanged<String> onSelect) {
    final isSelected = type == current;
    return GestureDetector(
      onTap: () => onSelect(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD4A043).withOpacity(0.15) : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(10),
          border: isSelected ? Border.all(color: const Color(0xFFD4A043)) : null,
        ),
        alignment: Alignment.center,
        child: Text(label, style: GoogleFonts.outfit(
          color: isSelected ? const Color(0xFFD4A043) : Colors.white54,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        )),
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> banner) async {
    final String id = banner['id'];
    final String url = banner['url'] ?? '';
    
    // Пытаемся удалить файл из хранилища, если это наш файл Supabase
    if (url.contains('/storage/v1/object/public/')) {
      try {
        final uri = Uri.parse(url);
        final segments = uri.pathSegments;
        // Формат: [..., 'public', 'media', 'banners', 'file.mp4']
        final publicIndex = segments.indexOf('public');
        if (publicIndex != -1 && segments.length > publicIndex + 2) {
          // Все сегменты после бакета (в нашем случае 'media') — это и есть путь
          final storagePath = segments.sublist(publicIndex + 2).join('/');
          final decodedPath = Uri.decodeComponent(storagePath);
          
          await Supabase.instance.client.storage.from('media').remove([decodedPath]);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Файл удален из Storage: $decodedPath'), backgroundColor: Colors.blue),
            );
          }
          debugPrint('SUCCESS: Deleted from storage: $decodedPath');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка Storage: $e'), backgroundColor: Colors.orange),
          );
        }
        debugPrint('ERROR: Failed to delete from storage: $e');
      }
    }

    await Supabase.instance.client.from('banners').delete().eq('id', id);
    _load();
  }

  Future<void> _toggleActive(String id, bool currentStatus) async {
    await Supabase.instance.client.from('banners').update({'is_active': !currentStatus}).eq('id', id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Шапка
        Container(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
          color: const Color(0xFF1A1A1A),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Видеобаннер', style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white38)),
                ],
              ),
              const SizedBox(height: 12),
              // Кнопки загрузки
              Row(
                children: [
                  // Загрузить файл с устройства
                  Expanded(
                    child: GestureDetector(
                      onTap: _uploading ? null : _pickAndUpload,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFD4A043), Color(0xFFE8B86D)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD4A043).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.upload_file_rounded,
                              color: Colors.black, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _uploading ? _uploadStatus : 'Загрузить с устройства',
                              style: GoogleFonts.outfit(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // Прогресс загрузки
              if (_uploading) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    color: const Color(0xFFD4A043),
                    backgroundColor: Colors.white12,
                    minHeight: 6,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              // Подсказка форматов
              Text(
                'Поддерживается: MP4, MOV, WebM, JPG, PNG, GIF',
                style: GoogleFonts.outfit(color: Colors.white24, fontSize: 11),
              ),
            ],
          ),
        ),
        // Список баннеров
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A043)))
              : _banners.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off_rounded, color: Colors.white12, size: 56),
                          const SizedBox(height: 12),
                          Text('Баннеров нет',
                            style: GoogleFonts.outfit(color: Colors.white38, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text('Загрузите видео или изображение',
                            style: GoogleFonts.outfit(color: Colors.white24, fontSize: 13)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _banners.length,
                      itemBuilder: (_, i) {
                        final b = _banners[i];
                        final isActive = b['is_active'] == true;
                        final isVideo = b['type'] == 'video';
                        final fileName = b['filename'] ?? '';
                        final url = b['url'] ?? '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(16),
                            border: isActive
                                ? Border.all(color: const Color(0xFFD4A043).withOpacity(0.5))
                                : null,
                          ),
                          child: Row(
                            children: [
                              // Превью / иконка
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: !isVideo && url.isNotEmpty
                                    ? Image.network(
                                        url,
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _iconBox(isVideo),
                                      )
                                    : _iconBox(isVideo),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isVideo ? 'Видеобаннер' : 'Изображение',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (fileName.isNotEmpty)
                                      Text(
                                        fileName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                                      ),
                                    if (isActive)
                                      Container(
                                        margin: const EdgeInsets.only(top: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD4A043).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text('● АКТИВЕН',
                                          style: GoogleFonts.outfit(
                                            color: const Color(0xFFD4A043),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1,
                                          )),
                                      ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                color: const Color(0xFF2A2A2A),
                                onSelected: (val) {
                                  if (val == 'toggle') _toggleActive(b['id'], isActive);
                                  if (val == 'delete') _delete(b);
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'toggle',
                                    child: Row(
                                      children: [
                                        Icon(isActive ? Icons.cancel_rounded : Icons.check_circle_rounded,
                                            color: const Color(0xFFD4A043), size: 18),
                                        const SizedBox(width: 8),
                                        Text(isActive ? 'Деактивировать' : 'Активировать',
                                            style: GoogleFonts.outfit(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.delete_rounded, color: Colors.red, size: 18),
                                        const SizedBox(width: 8),
                                        Text('Удалить', style: GoogleFonts.outfit(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                                icon: const Icon(Icons.more_vert_rounded, color: Colors.white38),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _iconBox(bool isVideo) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: (isVideo ? Colors.blue : Colors.green).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        isVideo ? Icons.play_circle_rounded : Icons.image_rounded,
        color: isVideo ? Colors.blue : Colors.green,
        size: 28,
      ),
    );
  }
}
