import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
  final stt.SpeechToText speech = stt.SpeechToText();
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
  bool ready = false;
  bool listening = false;
  bool keepRecording = false;
  bool starting = false;
  bool restartScheduled = false;
  String lastHeard = '';

  String _normalize(String value) {
    return value
        .replaceAll(RegExp(r'[ًٌٍَُِّْـٰ]'), '')
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[،؛؟,.!؟:…()\[\]{}"“”]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int _countOccurrences(String recognized, String target) {
    final heardWords = _normalize(recognized).split(' ');
    final targetWords = _normalize(target).split(' ');
    if (targetWords.isEmpty || heardWords.length < targetWords.length) {
      return 0;
    }

    var matches = 0;
    for (var i = 0; i <= heardWords.length - targetWords.length; i++) {
      var match = true;
      for (var j = 0; j < targetWords.length; j++) {
        if (heardWords[i + j] != targetWords[j]) {
          match = false;
          break;
        }
      }
      if (match) matches++;
    }
    return matches;
  }

  Future<void> startRecording() async {
    if (starting || listening) return;
    starting = true;
    keepRecording = true;
    if (mounted) {
      setState(() => status = 'جارٍ تشغيل التسجيل…');
    }

    try {
      ready = await speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: (error) {
          keepRecording = false;
          starting = false;
          if (mounted) {
            setState(() {
              listening = false;
              status = 'تعذر التعرف على الصوت: ${error.errorMsg}';
            });
          }
        },
      );
    } catch (error) {
      keepRecording = false;
      starting = false;
      if (mounted) {
        setState(() {
          listening = false;
          status = 'تعذر تهيئة التعرف الصوتي: $error';
        });
      }
      return;
    }

    if (!ready) {
      keepRecording = false;
      starting = false;
      if (mounted) {
        setState(() {
          listening = false;
          status = 'التعرف على الكلام غير متاح على هذا الجهاز';
        });
      }
      return;
    }

    // تحرير قفل البدء قبل استدعاء _listenAgain حتى لا يبقى التسجيل معلقاً.
    starting = false;
    await _listenAgain();
  }

  void _handleSpeechStatus(String speechStatus) {
    if (!mounted) return;

    if (speechStatus == 'listening') {
      setState(() {
        listening = true;
        status = 'التسجيل يعمل… قل الذكر بوضوح';
      });
    } else if (speechStatus == 'done' || speechStatus == 'notListening') {
      setState(() => listening = false);
      if (keepRecording) _scheduleRestart();
    }
  }

  void _scheduleRestart() {
    if (restartScheduled || !keepRecording) return;
    restartScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 700), () async {
      restartScheduled = false;
      if (!mounted || !keepRecording || starting || listening) return;
      await _listenAgain();
    });
  }

  Future<void> _listenAgain() async {
    if (!keepRecording || starting) return;
    starting = true;
    try {
      await speech.listen(
        localeId: 'ar',
        listenFor: const Duration(minutes: 10),
        pauseFor: const Duration(seconds: 10),
        partialResults: true,
        onResult: (result) {
          if (!mounted) return;
          setState(() => lastHeard = result.recognizedWords);
          // نحتسب النتيجة النهائية فقط لتجنب تكرار النتائج الجزئية.
          if (!result.finalResult) return;
          final added = _countOccurrences(result.recognizedWords, dhikr);
          if (added > 0) {
            setState(() {
              count += added;
              status = 'تم احتساب $added من الذكر ✓';
            });
          } else {
            setState(() {
              status = result.recognizedWords.trim().isEmpty
                  ? 'لم يلتقط الهاتف كلاماً واضحاً، حاول مجدداً'
                  : 'سمع الهاتف كلاماً لكنه لم يطابق الذكر المحدد';
            });
          }
        },
      );
      if (mounted && keepRecording) {
        setState(() {
          listening = true;
          status = 'التسجيل يعمل… قل الذكر بوضوح';
        });
      }
    } catch (_) {
      keepRecording = false;
      if (mounted) {
        setState(() {
          listening = false;
          status = 'حدث خطأ أثناء التسجيل. حاول مرة أخرى.';
        });
      }
    } finally {
      starting = false;
    }
  }

  Future<void> stopRecording() async {
    keepRecording = false;
    restartScheduled = false;
    await speech.stop();
    if (mounted) {
      setState(() {
        listening = false;
        status = 'تم إيقاف التسجيل';
      });
    }
  }

  void _selectDhikr(String value) {
    setState(() {
      dhikr = value;
      status = 'تم اختيار الذكر';
    });
  }

  @override
  void dispose() {
    keepRecording = false;
    speech.stop();
    customController.dispose();
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
                      listening || keepRecording ? stopRecording : startRecording,
                  icon: Icon(
                    listening || keepRecording
                        ? Icons.stop_circle_outlined
                        : Icons.fiber_manual_record_rounded,
                  ),
                  label: Text(
                    listening || keepRecording ? 'إيقاف التسجيل' : 'ابدأ التسجيل',
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
