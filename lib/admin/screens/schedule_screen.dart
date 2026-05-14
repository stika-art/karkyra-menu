import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import '../../services/settings_service.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  Map<String, String> _schedule = {};
  bool _saving = false;

  final Map<String, String> _daysMap = {
    'Mon': 'Понедельник',
    'Tue': 'Вторник',
    'Wed': 'Среда',
    'Thu': 'Четверг',
    'Fri': 'Пятница',
    'Sat': 'Суббота',
    'Sun': 'Воскресенье',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      final jsonStr = SettingsService.weeklySchedule;
      final decoded = json.decode(jsonStr) as Map<String, dynamic>;
      setState(() {
        _schedule = decoded.map((key, value) => MapEntry(key, value.toString()));
      });
    } catch (e) {
      debugPrint('Error loading schedule: $e');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final jsonStr = json.encode(_schedule);
      await SettingsService.update('weekly_schedule', jsonStr);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('График сохранен ✅'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _editDay(String key) {
    final current = _schedule[key] ?? '08:00-21:30';
    final parts = current.split('-');
    final startCtrl = TextEditingController(text: parts[0]);
    final endCtrl = TextEditingController(text: parts.length > 1 ? parts[1] : '21:30');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(_daysMap[key]!, style: GoogleFonts.outfit(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _timeField(startCtrl, 'Открытие'),
            const SizedBox(height: 16),
            _timeField(endCtrl, 'Закрытие'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _schedule[key] = '${startCtrl.text}-${endCtrl.text}';
              });
              Navigator.pop(ctx);
            },
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  Widget _timeField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
          color: const Color(0xFF1A1A1A),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('График работы', style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving 
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_rounded, size: 18),
                label: Text('Сохранить', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4A043),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: _daysMap.keys.map((key) {
              final time = _schedule[key] ?? '08:00-21:30';
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  title: Text(_daysMap[key]!, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                  trailing: Text(time, style: GoogleFonts.outfit(color: const Color(0xFFD4A043), fontWeight: FontWeight.bold, fontSize: 16)),
                  onTap: () => _editDay(key),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
