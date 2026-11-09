import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const DhikrCounterApp());

class DhikrCounterApp extends StatelessWidget {
  const DhikrCounterApp({super.key});

  static const silver = Color(0xFFE9ECF0);
  static const ink = Color(0xFF3F4A59);
  static const accent = Color(0xFF718096);

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'عدّاد الأذكار',
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto',
          scaffoldBackgroundColor: silver,
          colorScheme: ColorScheme.fromSeed(
            seedColor: accent,
            surface: const Color(0xFFF7F8FA),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: silver,
            foregroundColor: ink,
            elevation: 0,
          ),
        ),
        home: const CounterPage(),
      );
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  static const MethodChannel _recorder = MethodChannel('dhikr/recorder');
  static const EventChannel _events = EventChannel('dhikr/events');
  StreamSubscription<dynamic>? recorderEvents;
  final TextEditingController customController = TextEditingController();

  final List<String> presets = const [
    'لا إله إلا الله',
    'سبحان الله',
    'الحمد لله',
    'الله أكبر',
    'أستغفر الله',
    'اللهم صلِّ على محمد',
  ];

  String dhikr = 'لا إله إلا الله';
  String status = 'جاهز للتسجيل';
  int count = 0;
  final List<String> recognizedDhikr = [];
  bool ready = false;
  bool listening = false;
  bool keepRecording = false;
  bool starting = false;
  bool restartScheduled = false;
  String lastHeard = '';
  final Stopwatch recordingClock = Stopwatch();
  Timer? elapsedTicker;
  int elapsedSeconds = 0;
  int countedInCurrentUtterance = 0;
  String speechLocaleId = 'ar-SA';

  @override
  void initState() {
    super.initState();
    recorderEvents = _events.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (_) {
        if (mounted) setState(() => status = 'انقطع الاتصال بخدمة التسجيل');
      },
    );
    _restoreNativeState();
  }

  Future<void> _restoreNativeState() async {
    try {
      final state = await _recorder.invokeMapMethod<String, dynamic>('getState');
      if (!mounted || state == null) return;
      final savedHistory = (state['history'] as List?)?.cast<String>() ?? <String>[];
      setState(() {
        count = (state['count'] as num?)?.toInt() ?? count;
        recognizedDhikr
          ..clear()
          ..addAll(savedHistory);
        if (state['running'] == true) {
          keepRecording = true;
          listening = state['listening'] == true;
          status = 'التسجيل مستمر في الخلفية';
        }
      });
    } catch (_) {}
  }

  void _handleNativeEvent(dynamic event) {
    if (!mounted || event is! Map) return;
    final type = event['type'];
    if (type == 'transcript') {
      final heard = (event['text'] ?? '').toString();
      final savedHistory = (event['history'] as List?)?.cast<String>();
      setState(() {
        if (heard.isNotEmpty) lastHeard = heard;
        count = (event['count'] as num?)?.toInt() ?? count;
        if (savedHistory != null) {
          recognizedDhikr
            ..clear()
            ..addAll(savedHistory);
        }
      });
    } else if (type == 'state') {
      final active = event['listening'] == true;
      setState(() {
        listening = active;
        starting = false;
        if (active) {
          if (!recordingClock.isRunning) recordingClock.start();
          elapsedTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted && keepRecording) {
              setState(() => elapsedSeconds = recordingClock.elapsed.inSeconds);
            }
          });
          status = 'التسجيل يعمل… قل الذكر بوضوح';
        } else if (keepRecording) {
          status = 'لا يوجد كلام حالياً، سيعود الاستماع تلقائياً…';
        }
      });
    } else if (type == 'error') {
      setState(() {
        listening = false;
        status = 'تعذر التقاط الصوت مؤقتاً، أحاول مجدداً…';
      });
    }
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remaining = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remaining';
  }

  String _normalize(String value) {
    return value
        .replaceAll(RegExp(r'[ًٌٍَُِّْـٰ]'), '')
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll(RegExp(r'[،؛؟,.!؟:…()\[\]{}"“”]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // يقبل تكرار الذكر المحدد متتالياً فقط، ويرفض أي كلام زائد أو مختلف.
  int _countExactRepetitions(String recognized, String target) {
    final heardWords = _normalize(recognized).split(' ');
    final targetWords = _normalize(target).split(' ');
    if (targetWords.isEmpty ||
        heardWords.isEmpty ||
        heardWords.length % targetWords.length != 0) {
      return 0;
    }

    for (var start = 0; start < heardWords.length; start += targetWords.length) {
      for (var i = 0; i < targetWords.length; i++) {
        if (heardWords[start + i] != targetWords[i]) return 0;
      }
    }
    return heardWords.length ~/ targetWords.length;
  }

  Future<void> startRecording() async {
    if (starting || keepRecording) return;
    starting = true;
    keepRecording = true;
    elapsedTicker?.cancel();
    recordingClock.reset();
    elapsedSeconds = 0;
    if (mounted) {
      setState(() => status = 'جارٍ تشغيل خدمة التسجيل…');
    }
    try {
      await _recorder.invokeMethod('start', {
        'dhikr': dhikr,
        'locale': speechLocaleId,
      });
      if (mounted) {
        setState(() {
          starting = false;
          status = 'تم تشغيل خدمة التسجيل، بانتظار التقاط الصوت…';
        });
      }
    } catch (error) {
      keepRecording = false;
      starting = false;
      if (mounted) {
        setState(() => status = 'تعذر تشغيل خدمة التسجيل: $error');
      }
    }
  }

  Future<void> stopRecording() async {
    keepRecording = false;
    elapsedTicker?.cancel();
    elapsedTicker = null;
    recordingClock.stop();
    elapsedSeconds = recordingClock.elapsed.inSeconds;
    try {
      await _recorder.invokeMethod('stop');
    } catch (_) {}
    if (mounted) {
      setState(() {
        listening = false;
        starting = false;
        status = 'تم إيقاف التسجيل';
      });
    }
  }

  void _selectDhikr(String value) {
    countedInCurrentUtterance = 0;
    lastHeard = '';
    setState(() {
      dhikr = value;
      count = 0;
      recognizedDhikr.clear();
      status = 'تم اختيار الذكر، وتم بدء سجل جديد';
    });

    // عند تغيير الذكر نعيد فتح جلسة التعرف حتى لا تختلط كلمات الذكر السابق
    // بنتائج الذكر الجديد.
    if (keepRecording) {
      _recorder.invokeMethod('setDhikr', {'dhikr': value});
    }
  }

  @override
  void dispose() {
    elapsedTicker?.cancel();
    recordingClock.stop();
    recorderEvents?.cancel();
    // لا نوقف خدمة الميكروفون هنا؛ قد تكون الواجهة أُغلقت بينما المستخدم
    // يريد استمرار التسجيل في الخلفية.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF3F4A59);
    const muted = Color(0xFF7C8795);
    const accent = Color(0xFF718096);
    const card = Color(0xFFF8F9FB);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: const Text(
            'عدّاد الأذكار',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2),
          ),
          actions: [
            IconButton(
              tooltip: 'تصفير العدّاد',
              onPressed: () => setState(() {
                count = 0;
                recognizedDhikr.clear();
                status = 'تم تصفير العدّاد';
              }),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 25),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [Color(0xFFF9FAFC), Color(0xFFDDE2E8)],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white.withValues(alpha: .9)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF657184).withValues(alpha: .10),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Column(
                  children: [
                    Icon(Icons.spa_rounded, size: 42, color: accent),
                    SizedBox(height: 12),
                    Text(
                      'اذكر الله واطمئن',
                      style: TextStyle(
                        color: ink,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'اترك العدّ علينا، واضغط إيقاف التسجيل عندما تنتهي',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'اختر الذكر',
                style: TextStyle(
                    color: ink, fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 9,
                children: presets
                    .map(
                      (item) => ChoiceChip(
                        label: Text(item),
                        selected: dhikr == item,
                        onSelected: (_) => _selectDhikr(item),
                        selectedColor: const Color(0xFFD5DCE5),
                        backgroundColor: card,
                        side: BorderSide(
                          color: dhikr == item
                              ? accent
                              : const Color(0xFFDCE1E7),
                        ),
                        labelStyle: TextStyle(
                          color: ink,
                          fontWeight: dhikr == item
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: customController,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  labelText: 'ذكر مخصص',
                  hintText: 'اكتب الذكر الذي تريده',
                  filled: true,
                  fillColor: card,
                  prefixIcon: const Icon(Icons.edit_note_rounded, color: muted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: const BorderSide(color: Color(0xFFDCE1E7)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: const BorderSide(color: Color(0xFFDCE1E7)),
                  ),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) _selectDhikr(value.trim());
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    if (customController.text.trim().isNotEmpty) {
                      _selectDhikr(customController.text.trim());
                    }
                  },
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('اعتماد الذكر'),
                  style: TextButton.styleFrom(foregroundColor: accent),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 25),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF657184).withValues(alpha: .08),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      'الذكر الحالي',
                      style: TextStyle(
                          color: muted, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      dhikr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      '$count',
                      style: const TextStyle(
                        color: Color(0xFF536174),
                        fontSize: 68,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'مدة التسجيل: ${_formatDuration(elapsedSeconds)}',
                      style: const TextStyle(color: muted, fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          listening
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                          size: 17,
                          color: listening ? accent : muted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            status,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: listening ? accent : muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (recognizedDhikr.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFDCE1E7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'سجلّ الأذكار المقروءة',
                        style: TextStyle(
                          color: ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(recognizedDhikr.length, (index) {
                        final id = index + 1;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE3E8EE),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$id-',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  recognizedDhikr[index],
                                  style: const TextStyle(color: ink, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              if (lastHeard.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9EDF2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'آخر كلام التقطه الهاتف: $lastHeard',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                height: 58,
                child: FilledButton.icon(
                  onPressed:
                      starting || listening || keepRecording ? stopRecording : startRecording,
                  icon: Icon(
                    starting || listening || keepRecording
                        ? Icons.stop_circle_outlined
                        : Icons.fiber_manual_record_rounded,
                  ),
                  label: Text(
                    starting || listening || keepRecording ? 'إيقاف التسجيل' : 'ابدأ التسجيل',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    count = 0;
                    recognizedDhikr.clear();
                    status = 'تم تصفير العدّاد';
                  }),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('تصفير العدّاد'),
                  style: TextButton.styleFrom(foregroundColor: muted),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'ملاحظة: يعتمد دقّة العدّ على وضوح النطق ودقّة خدمة التعرّف الصوتي في الهاتف.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
