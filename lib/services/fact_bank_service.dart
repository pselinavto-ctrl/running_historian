import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:running_historian/domain/fact.dart';

class FactBankService {
  static const String _boxName = 'facts';
  late Box<Fact> _box;

  /// Обязательная инициализация перед использованием
  Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      _box = await Hive.openBox<Fact>(_boxName);
    } else {
      _box = Hive.box<Fact>(_boxName);
    }
  }

  /// Получить все неиспользованные факты
  List<Fact> getActiveFacts() {
    return _box.values.where((fact) => !fact.isConsumed).toList();
  }

  /// Получить объектные факты по landmarkId
  List<Fact> getObjectFacts(String landmarkId) {
    return _box.values
        .where((fact) =>
            fact.type == 'object' &&
            fact.landmarkId == landmarkId &&
            !fact.isConsumed)
        .toList();
  }

  /// Пометить факт как использованный
  Future<void> markAsConsumed(Fact fact) async {
    final updated = fact.copyWith(consumedAt: DateTime.now());
    await _box.put(fact.id, updated);
  }

  /// Текущий размер банка
  int getBankSize() {
    return _box.length;
  }

  /// Пополнить банк фактами при необходимости
  Future<void> replenishBank() async {
    final currentSize = getBankSize();
    if (currentSize < 40) {
      await _fetchAndSaveFacts(20);
    } else if (currentSize < 120) {
      await _fetchAndSaveFacts(10);
    }
  }

  /// 🔥 Загрузить N валидных фактов из Википедии
  Future<void> _fetchAndSaveFacts(int count) async {
    int saved = 0;
    int attempts = 0;
    const maxAttempts = 60; // защита от бесконечного цикла

    while (saved < count && attempts < maxAttempts) {
      attempts++;
      try {
        // ⚠️ УБРАН ЛИШНИЙ ПРОБЕЛ В URL!
        final response = await http.get(
          Uri.parse('https://ru.wikipedia.org/api/rest_v1/page/random/summary'),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final extract = data['extract'] as String?;

          // Фильтрация мусора: пусто, редиректы, короткие тексты
          if (extract != null &&
              extract.isNotEmpty &&
              !extract.startsWith('Перенаправление') &&
              extract.length >= 80) {

            final fact = Fact(
              id: '${DateTime.now().microsecondsSinceEpoch}_$saved',
              text: extract,
              type: 'general',
              createdAt: DateTime.now(),
            );

            await _box.put(fact.id, fact);
            saved++;
          }
        }
      } catch (e) {
        print('Ошибка загрузки факта #$attempts: $e');
      }
    }
    print('✅ FactBank: загружено $saved новых фактов (попыток: $attempts)');
  }

  /// Получить общий факт по FIFO (первый неиспользованный)
  Fact? getGeneralFact() {
    final facts = getActiveFacts().where((f) => f.type == 'general').toList();
    return facts.isNotEmpty ? facts.first : null;
  }
}