import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:running_historian/domain/fact.dart';
import 'package:running_historian/config/constants.dart';

class FactBankService {
  static final Box<Fact> _box = Hive.box<Fact>('facts');

  // Получить активные факты (неиспользованные)
  List<Fact> getActiveFacts() {
    return _box.values.where((fact) => !fact.isConsumed).toList();
  }

  // Получить объектные факты
  List<Fact> getObjectFacts(String landmarkId) {
    return _box.values
        .where((fact) => fact.type == 'object' && fact.landmarkId == landmarkId && !fact.isConsumed)
        .toList();
  }

  // Пометить факт как использованный
  Future<void> markAsConsumed(Fact fact) async {
    final updated = fact.copyWith(consumedAt: DateTime.now());
    await _box.put(fact.id, updated);
  }

  // Проверить размер банка
  int getBankSize() {
    return _box.length;
  }

  // Пополнить банк (при интернете)
  Future<void> replenishBank() async {
    int currentSize = getBankSize();
    
    if (currentSize < 40) {
      // Обязательно пополняем
      await _fetchAndSaveFacts(20);
    } else if (currentSize < 120) {
      // Допускается пополнение
      await _fetchAndSaveFacts(10);
    }
  }

  // Загрузить факты из Wikipedia
  Future<void> _fetchAndSaveFacts(int count) async {
    try {
      // Пример: получить случайные статьи
      final response = await http.get(
        Uri.parse('https://ru.wikipedia.org/api/rest_v1/page/random/summary'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final fact = Fact(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: data['extract'] ?? '',
          type: 'general',
          createdAt: DateTime.now(),
        );
        
        await _box.put(fact.id, fact);
      }
    } catch (e) {
      print('Ошибка загрузки факта: $e');
    }
  }

  // Получить общий факт (FIFO)
  Fact? getGeneralFact() {
    final facts = getActiveFacts().where((f) => f.type == 'general').toList();
    return facts.isNotEmpty ? facts.first : null;
  }
}