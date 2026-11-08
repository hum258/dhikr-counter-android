import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() => runApp(const DhikrCounterApp());

class DhikrCounterApp extends StatelessWidget {
  const DhikrCounterApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'عدّاد الأذكار',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF147D64)), useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFF5F8F6), fontFamily: 'Roboto'),
    home: const CounterPage(),
  );
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});
  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  final speech = stt.SpeechToText();
  final customController = TextEditingController();
  final presets = ['لا إله إلا الله', 'سبحان الله', 'الحمد لله', 'الله أكبر', 'أستغفر الله', 'اللهم صلِّ على محمد'];
  String dhikr = 'لا إله إلا الله';
  int count = 0;
  bool ready = false, listening = false;
  String status = 'اضغط بدء الاستماع وابدأ بذكرك';
  String lastCounted = '';
  DateTime? lastCountAt;

  Future<void> startListening() async {
    ready = await speech.initialize(
      onStatus: (s) { if (mounted) setState(() { listening = s == 'listening'; if (s == 'done' || s == 'notListening') status = 'توقف الاستماع'; }); },
      onError: (e) { if (mounted) setState(() => status = 'تعذر التعرف على الصوت: ${e.errorMsg}'); },
    );
    if (!ready) { setState(() => status = 'التعرف على الكلام غير متاح على هذا الجهاز'); return; }
    setState(() { listening = true; status = 'أستمع إليك…'; });
    await speech.listen(
      localeId: 'ar',
      listenFor: const Duration(minutes: 1),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      onResult: (result) {
        final words = result.recognizedWords.replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '').trim();
        final target = dhikr.replaceAll(RegExp(r'[ًٌٍَُِّْـ]'), '').trim();
        if (words.isEmpty || target.isEmpty) return;
        final normalized = words.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا');
        final wanted = target.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا');
        final now = DateTime.now();
        if (normalized.contains(wanted) && (lastCounted != result.recognizedWords || lastCountAt == null || now.difference(lastCountAt!) > const Duration(seconds: 2))) {
          setState(() { count++; lastCounted = result.recognizedWords; lastCountAt = now; status = 'تم احتساب ذكر جديد ✓'; });
        } else if (mounted) { setState(() => status = 'أستمع إليك…'); }
      },
    );
  }

  Future<void> stopListening() async { await speech.stop(); if (mounted) setState(() { listening = false; status = 'تم إيقاف الاستماع'; }); }

  @override
  void dispose() { speech.stop(); customController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Directionality(textDirection: TextDirection.rtl, child: Scaffold(
      appBar: AppBar(title: const Text('عدّاد الأذكار', style: TextStyle(fontWeight: FontWeight.bold)), centerTitle: true, backgroundColor: Colors.transparent),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: const Color(0xFFE5F2EC), borderRadius: BorderRadius.circular(24)), child: const Column(children: [
          Icon(Icons.spa_rounded, size: 42, color: Color(0xFF147D64)),
          SizedBox(height: 10),
          Text('اذكر الله بقلبك… واترك العدّ علينا', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF155B49))),
        ])),
        const SizedBox(height: 24),
        const Text('اختر الذكر', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: presets.map((p) => ChoiceChip(label: Text(p), selected: dhikr == p, onSelected: (_) => setState(() => dhikr = p))).toList()),
        const SizedBox(height: 14),
        TextField(controller: customController, textDirection: TextDirection.rtl, decoration: InputDecoration(labelText: 'أو اكتب ذكراً خاصاً', hintText: 'اكتب الذكر هنا', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)), onSubmitted: (v) { if (v.trim().isNotEmpty) setState(() => dhikr = v.trim()); }),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () { if (customController.text.trim().isNotEmpty) setState(() => dhikr = customController.text.trim()); }, icon: const Icon(Icons.check), label: const Text('اعتماد الذكر المكتوب'))),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.symmetric(vertical: 28), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 16)]), child: Column(children: [
          const Text('الذكر الحالي', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(dhikr, textAlign: TextAlign.center, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: Color(0xFF147D64)))),
          const SizedBox(height: 16),
          Text('$count', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: Color(0xFF173D32))),
          Text(status, style: TextStyle(color: listening ? const Color(0xFF147D64) : Colors.black54)),
        ])),
        const SizedBox(height: 20),
        SizedBox(height: 56, child: FilledButton.icon(onPressed: listening ? stopListening : startListening, icon: Icon(listening ? Icons.stop_circle_outlined : Icons.mic), label: Text(listening ? 'إيقاف الاستماع' : 'ابدأ الاستماع'), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF147D64), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))))),
        Center(child: TextButton.icon(onPressed: () => setState(() { count = 0; lastCounted = ''; status = 'تم تصفير العدّاد'; }), icon: const Icon(Icons.refresh), label: const Text('تصفير العدّاد'))),
        const SizedBox(height: 8),
        const Text('ملاحظة: هذه نسخة أولية؛ قد يختلف التعرف على النطق حسب الجهاز. الاستماع في الخلفية عند إغلاق الشاشة لم يُفعّل بعد.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
      ])),
    ));
  }
}
