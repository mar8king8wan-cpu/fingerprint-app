import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

const String kMasterDevCode = "marwan1988";
const String kSalt = "FP_MARWAN_2026_LOCK_SALT";

class SlotItem {
  final String id;
  final String title;
  final String window;
  final String? note;
  final int defaultHour;
  final int defaultMinute;

  const SlotItem({
    required this.id,
    required this.title,
    required this.window,
    this.note,
    required this.defaultHour,
    required this.defaultMinute,
  });
}

const List<SlotItem> kDay1Slots = [
  SlotItem(
    id: "d1_1",
    title: "البصمة الأولى (الحضور)",
    window: "قبل الساعة 10:00 صباحاً",
    defaultHour: 9,
    defaultMinute: 30,
  ),
  SlotItem(
    id: "d1_2",
    title: "البصمة الثانية (المسائية)",
    window: "من 04:00 م إلى 07:00 م",
    defaultHour: 16,
    defaultMinute: 30,
  ),
  SlotItem(
    id: "d1_3",
    title: "البصمة الثالثة (الليلية)",
    window: "من 09:00 م إلى 12:00 ص",
    defaultHour: 21,
    defaultMinute: 30,
  ),
];

const List<SlotItem> kDay2Slots = [
  SlotItem(
    id: "d2_1",
    title: "البصمة الأولى (الصباحية)",
    window: "من 06:00 ص إلى 09:00 ص",
    note: "تنبيه الانصراف: بعد الساعة 09:30 صباحاً",
    defaultHour: 8,
    defaultMinute: 15,
  ),
  SlotItem(
    id: "d2_2",
    title: "البصمة الثانية (المسائية)",
    window: "من 04:00 م إلى 07:00 م",
    defaultHour: 16,
    defaultMinute: 30,
  ),
  SlotItem(
    id: "d2_3",
    title: "البصمة الثالثة (الليلية)",
    window: "من 09:00 م إلى 12:00 ص",
    defaultHour: 21,
    defaultMinute: 30,
  ),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation("Asia/Baghdad"));
  } catch (_) {}

  const androidInit = AndroidInitializationSettings("@mipmap/ic_launcher");
  const initSettings = InitializationSettings(android: androidInit);
  await notificationsPlugin.initialize(initSettings);

  final androidPlugin = notificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();
  await androidPlugin?.requestExactAlarmsPermission();

  runApp(const FingerprintApp());
}

class FingerprintApp extends StatelessWidget {
  const FingerprintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: "أوقات أداء البصمة",
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late String deviceId;
  bool isLoggedIn = false;
  bool isDev = false;
  final TextEditingController codeCtrl = TextEditingController();
  String? loginError;

  DateTime selectedDate = DateTime.now();
  DateTime cycleStart = DateTime.now();
  Set<String> completed = {};
  Map<String, dynamic> alarmConfigs = {};

  @override
  void initState() {
    super.initState();
    selectedDate = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    cycleStart = selectedDate;
    _loadState();
  }

  String _simpleHash(String input) {
    int h1 = 0xdeadbeef;
    int h2 = 0x41c6ce57;
    for (int i = 0; i < input.length; i++) {
      final ch = input.codeUnitAt(i);
      h1 = ((h1 ^ ch) * 2654435761) & 0xffffffff;
      h2 = ((h2 ^ ch) * 1597334677) & 0xffffffff;
    }
    h1 = (((h1 ^ (h1 >> 16)) * 2246822507) ^ ((h2 ^ (h2 >> 13)) * 3266489909)) & 0xffffffff;
    h2 = (((h2 ^ (h2 >> 16)) * 2246822507) ^ ((h1 ^ (h1 >> 13)) * 3266489909)) & 0xffffffff;
    final val = ((h2 & 0x1fffff) * 4294967296.0 + h1.toUnsigned(32)).toInt();
    return val.abs().toRadixString(16).toUpperCase().padLeft(8, "0").substring(0, 8);
  }

  String _computeCodeForDevice(String devId) {
    final clean = devId.trim().toUpperCase();
    final h = _simpleHash("$kSalt:$clean");
    return "FP-${h.substring(0, 4)}-${h.substring(4, 8)}";
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedDev = prefs.getString("fp_device_id");
    if (savedDev == null) {
      final rnd = Random.secure().nextInt(99999999);
      savedDev = _simpleHash("DEV_${DateTime.now().microsecondsSinceEpoch}_$rnd");
      await prefs.setString("fp_device_id", savedDev);
    }

    final startStr = prefs.getString("fp_cycle_start");
    DateTime loadedStart = selectedDate;
    if (startStr != null) {
      final parsed = DateTime.tryParse(startStr);
      if (parsed != null) {
        loadedStart = DateTime(parsed.year, parsed.month, parsed.day);
      }
    }

    final compList = prefs.getStringList("fp_completed") ?? [];
    final cfgRaw = prefs.getString("fp_alarm_configs");
    Map<String, dynamic> loadedCfg = {};
    if (cfgRaw != null) {
      try {
        loadedCfg = Map<String, dynamic>.from(jsonDecode(cfgRaw));
      } catch (_) {}
    }

    setState(() {
      deviceId = savedDev!;
      isLoggedIn = prefs.getBool("fp_logged_in") ?? false;
      isDev = prefs.getBool("fp_is_dev") ?? false;
      cycleStart = loadedStart;
      completed = compList.toSet();
      alarmConfigs = loadedCfg;
    });

    if (isLoggedIn) {
      await _rescheduleAllAlarms();
    }
  }

  Future<void> _login() async {
    final entered = codeCtrl.text.trim();
    if (entered.isEmpty) {
      setState(() => loginError = "يرجى إدخال كود التفعيل");
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (entered == kMasterDevCode) {
      await prefs.setBool("fp_logged_in", true);
      await prefs.setBool("fp_is_dev", true);
      setState(() {
        isLoggedIn = true;
        isDev = true;
        loginError = null;
      });
      await _rescheduleAllAlarms();
      return;
    }
    if (entered.toUpperCase() == _computeCodeForDevice(deviceId)) {
      await prefs.setBool("fp_logged_in", true);
      await prefs.setBool("fp_is_dev", false);
      setState(() {
        isLoggedIn = true;
        isDev = false;
        loginError = null;
      });
      await _rescheduleAllAlarms();
      return;
    }
    setState(() => loginError = "الكود غير صحيح أو غير مخصص لهذا الجهاز");
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("fp_logged_in", false);
    await prefs.setBool("fp_is_dev", false);
    setState(() {
      isLoggedIn = false;
      isDev = false;
      codeCtrl.clear();
    });
  }

  int _cycleIndex(DateTime date) {
    final diff = date.difference(cycleStart).inDays;
    final mod = diff % 6;
    return mod < 0 ? mod + 6 : mod;
  }

  Map<String, int> _slotTime(SlotItem slot) {
    final item = alarmConfigs[slot.id];
    if (item is Map) {
      return {
        "hour": (item["hour"] as int?) ?? slot.defaultHour,
        "minute": (item["minute"] as int?) ?? slot.defaultMinute,
        "enabled": (item["enabled"] == false) ? 0 : 1,
      };
    }
    return {
      "hour": slot.defaultHour,
      "minute": slot.defaultMinute,
      "enabled": 1,
    };
  }

  Future<void> _pickSlotTime(SlotItem slot) async {
    final current = _slotTime(slot);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current["hour"]!, minute: current["minute"]!),
    );
    if (picked == null) return;

    alarmConfigs[slot.id] = {
      "hour": picked.hour,
      "minute": picked.minute,
      "enabled": true,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("fp_alarm_configs", jsonEncode(alarmConfigs));
    setState(() {});
    await _rescheduleAllAlarms();
  }

  Future<void> _rescheduleAllAlarms() async {
    await notificationsPlugin.cancelAll();
    final now = DateTime.now();
    int notifId = 100;

    for (int offset = 0; offset < 30; offset++) {
      final day = DateTime(now.year, now.month, now.day).add(Duration(days: offset));
      final idx = _cycleIndex(day);
      if (idx != 0 && idx != 1) continue;

      final slots = idx == 0 ? kDay1Slots : kDay2Slots;
      for (final slot in slots) {
        final cfg = _slotTime(slot);
        if (cfg["enabled"] == 0) continue;

        final scheduled = tz.TZDateTime(
          tz.local,
          day.year,
          day.month,
          day.day,
          cfg["hour"]!,
          cfg["minute"]!,
        );
        if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) continue;

        const androidDetails = AndroidNotificationDetails(
          "fp_alarm_channel",
          "منبهات أوقات البصمة",
          channelDescription: "تنبيهات مواعيد البصمة في جدول المناوبات",
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          fullScreenIntent: true,
        );

        await notificationsPlugin.zonedSchedule(
          notifId++,
          "🔔 حان وقت البصمة",
          "${slot.title} — ${slot.window}",
          scheduled,
          const NotificationDetails(android: androidDetails),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }

  Future<void> _toggleCompleted(String slotId) async {
    final key = "${DateFormat('yyyy-MM-dd').format(selectedDate)}_$slotId";
    if (completed.contains(key)) {
      completed.remove(key);
    } else {
      completed.add(key);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList("fp_completed", completed.toList());
    setState(() {});
  }

  void _openKeygenDialog() {
    final targetCtrl = TextEditingController();
    String generated = "";
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text("🔑 توليد كود تفعيل"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: targetCtrl,
                decoration: const InputDecoration(hintText: "أدخل معرّف الجهاز"),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  if (targetCtrl.text.trim().isNotEmpty) {
                    setLocal(() {
                      generated = _computeCodeForDevice(targetCtrl.text.trim());
                    });
                  }
                },
                child: const Text("توليد الكود"),
              ),
              if (generated.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(
                  generated,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إغلاق")),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isLoggedIn) {
      return Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.fingerprint, size: 68, color: Color(0xFF0F766E)),
                    const SizedBox(height: 10),
                    const Text("أوقات أداء البصمة", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("معرّف الجهاز: $deviceId", style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 14),
                    TextField(
                      controller: codeCtrl,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: "أدخل كود الدخول / التفعيل",
                      ),
                    ),
                    if (loginError != null) ...[
                      const SizedBox(height: 8),
                      Text(loginError!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _login,
                        child: const Text("دخول"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final idx = _cycleIndex(selectedDate);
    final isWork = idx == 0 || idx == 1;
    final slots = idx == 0 ? kDay1Slots : kDay2Slots;

    return Scaffold(
      appBar: AppBar(
        title: const Text("أوقات أداء البصمة"),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        actions: [
          if (isDev)
            IconButton(
              onPressed: _openKeygenDialog,
              icon: const Icon(Icons.vpn_key),
              tooltip: "توليد كود",
            ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: "خروج",
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => setState(() {
                          selectedDate = selectedDate.subtract(const Duration(days: 1));
                        }),
                        icon: const Icon(Icons.chevron_right),
                      ),
                      Text(
                        DateFormat("EEEE — yyyy/MM/dd", "ar").format(selectedDate),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          selectedDate = selectedDate.add(const Duration(days: 1));
                        }),
                        icon: const Icon(Icons.chevron_left),
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("تاريخ أول يوم دوام:"),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: cycleStart,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            final norm = DateTime(picked.year, picked.month, picked.day);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString("fp_cycle_start", norm.toIso8601String());
                            setState(() => cycleStart = norm);
                            await _rescheduleAllAlarms();
                          }
                        },
                        child: Text(DateFormat("yyyy-MM-dd").format(cycleStart)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isWork ? const Color(0xFF0F766E) : const Color(0xFF475569),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              isWork
                  ? (idx == 0
                      ? "اليوم الأول للعمل (3 بصمات)"
                      : "اليوم الثاني للعمل (3 بصمات + انصراف 09:30 ص)")
                  : "يوم راحة (${idx - 1} من 4)",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          if (!isWork)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text("لا توجد بصمات مطلوبة في هذا اليوم")),
              ),
            )
          else
            ...slots.map((slot) {
              final key = "${DateFormat('yyyy-MM-dd').format(selectedDate)}_${slot.id}";
              final isDone = completed.contains(key);
              final cfg = _slotTime(slot);
              final hh = cfg["hour"]!.toString().padLeft(2, "0");
              final mm = cfg["minute"]!.toString().padLeft(2, "0");

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  slot.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    decoration: isDone ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                Text(slot.window, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                if (slot.note != null)
                                  Text(slot.note!, style: const TextStyle(color: Colors.deepOrange, fontSize: 12)),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => _toggleCompleted(slot.id),
                            child: Text(isDone ? "تمت ✓" : "بصمت"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("⏰ وقت التنبيه: $hh:$mm"),
                          TextButton(
                            onPressed: () => _pickSlotTime(slot),
                            child: const Text("تعديل وقت التنبيه"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
