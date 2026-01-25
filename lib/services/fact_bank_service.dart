// lib/services/fact_bank_service.dart
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:running_historian/domain/fact.dart';

class FactBankService {
  static const String _boxName = 'facts';
  static const String _usedPageIdsBoxName = 'used_pageids';
  late Box<Fact> _box;
  late Box<List<String>> _usedPageIdsBox;

  // 🔒 Защита от частого пополнения
  DateTime? _lastReplenishTime;

  Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      _box = await Hive.openBox<Fact>(_boxName);
    } else {
      _box = Hive.box<Fact>(_boxName);
    }

    if (!Hive.isBoxOpen(_usedPageIdsBoxName)) {
      _usedPageIdsBox = await Hive.openBox<List<String>>(_usedPageIdsBoxName);
    } else {
      _usedPageIdsBox = Hive.box<List<String>>(_usedPageIdsBoxName);
    }
  }

  List<Fact> getActiveFacts() {
    return _box.values.where((fact) => !fact.isConsumed).toList();
  }

  int getBankSize() {
    // Считает ВСЕ активные факты (для отладки)
    return _box.values.where((f) => !f.isConsumed).length;
  }

  /// ✅ НОВОЕ: размер банка ТОЛЬКО для конкретного города
  int getCityBankSize(String city) {
    return _box.values
        .where((f) => !f.isConsumed && f.type == 'city' && f.city == city)
        .length;
  }

  List<Fact> getObjectFacts(String landmarkId) {
    return _box.values
        .where((fact) =>
            fact.type == 'object' &&
            fact.landmarkId == landmarkId &&
            !fact.isConsumed)
        .toList();
  }

  Future<void> markAsConsumed(Fact fact) async {
    final updated = fact.copyWith(consumedAt: DateTime.now());
    await _box.put(fact.id, updated);
  }

  /// Пополняет банк фактами ТОЛЬКО для указанного города.
  Future<void> replenishBank({required String city}) async {
    if (_lastReplenishTime != null &&
        DateTime.now().difference(_lastReplenishTime!) < const Duration(minutes: 10)) {
      print('🔄 FactBank: пополнение пропущено (менее 10 мин с последнего)');
      return;
    }

    _lastReplenishTime = DateTime.now();

    // ✅ ИСПРАВЛЕНО: проверяем размер ТОЛЬКО для этого города
    final citySize = getCityBankSize(city);
    if (citySize >= 40) {
      print('ℹ️ FactBank: достаточно фактов для города $city ($citySize/40)');
      return;
    }

    await _fetchCityFacts(city, count: 15);
  }

  Future<void> _fetchCityFacts(String city, {int count = 10}) async {
    final userAgent = 'running_historian/1.0 (running.historian.app@gmail.com)';
    try {
      final searchUri = Uri.https(
        'ru.wikipedia.org',
        '/w/api.php',
        {
          'action': 'query',
          'list': 'search',
          'srsearch': city,
          'srlimit': '50',
          'format': 'json',
        },
      );

      final searchResponse = await http.get(searchUri, headers: {'User-Agent': userAgent});
      if (searchResponse.statusCode != 200) {
        throw Exception('HTTP ${searchResponse.statusCode}');
      }

      final data = json.decode(searchResponse.body);
      final query = data['query'];
      if (query == null) {
        throw Exception('No "query" in response');
      }

      final results = query['search'] as List?;
      if (results == null || results.isEmpty) {
        print('ℹ️ Нет результатов поиска для города "$city"');
        _addFallbackFact(city, 'Интересные факты о городе $city скоро появятся!');
        return;
      }

      // used_pageids хранятся ПО ГОРОДУ
      final usedPageIds = Set<String>.from(
        _usedPageIdsBox.get(city, defaultValue: <String>[]) ?? [],
      );

      int saved = 0;
      for (var item in results) {
        if (saved >= count) break;

        if (item is! Map<String, dynamic>) continue;

        final pageidObj = item['pageid'];
        final title = item['title'] as String?;
        final snippet = item['snippet'] as String?;

        if (pageidObj == null || title == null) continue;

        final pageid = pageidObj.toString();
        if (usedPageIds.contains(pageid)) continue;

        // Фильтрация: только если город есть в title или snippet
        final lowerCity = city.toLowerCase();
        final lowerTitle = title.toLowerCase();
        final lowerSnippet = snippet?.toLowerCase() ?? '';

        if (!lowerTitle.contains(lowerCity) && !lowerSnippet.contains(lowerCity)) {
          continue;
        }

        final encodedTitle = Uri.encodeComponent(title);
        final summaryUri = Uri.parse('https://ru.wikipedia.org/api/rest_v1/page/summary/$encodedTitle');

        final summaryResponse = await http.get(summaryUri, headers: {'User-Agent': userAgent});
        if (summaryResponse.statusCode != 200) continue;

        final summaryData = json.decode(summaryResponse.body);
        final extract = summaryData['extract'] as String?;

        if (extract != null && extract.length > 80) {
          final fact = Fact(
            id: '${DateTime.now().microsecondsSinceEpoch}_city_$pageid',
            text: extract,
            type: 'city',
            city: city,
            region: _getRegionFromCity(city),
            createdAt: DateTime.now(),
          );
          await _box.put(fact.id, fact);
          usedPageIds.add(pageid);
          saved++;
        }

        await Future.delayed(const Duration(milliseconds: 200));
      }

      await _usedPageIdsBox.put(city, usedPageIds.toList());
      print('✅ Загружено $saved фактов для города "$city"');

      if (saved == 0) {
        _addFallbackFact(city, 'Не удалось найти интересные факты о городе $city.');
      }
    } catch (e) {
      print('❌ Ошибка при загрузке фактов для "$city": $e');
      _addFallbackFact(city, 'Временно не удаётся загрузить факты о городе $city.');
    }
  }

  Future<void> _addFallbackFact(String city, String text) async {
    final fact = Fact(
      id: 'fallback_${city.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      type: 'city',
      city: city,
      region: _getRegionFromCity(city),
      createdAt: DateTime.now(),
    );
    await _box.put(fact.id, fact);
  }

  String? _getRegionFromCity(String city) {
    const regions = {
      'Ростов-на-Дону': 'Ростовская область',
      'Новочеркасск': 'Ростовская область',
      'Таганрог': 'Ростовская область',
      'Азов': 'Ростовская область',
    };
    return regions[city];
  }

  Fact? getGeneralFact() {
    final facts = getActiveFacts().where((f) => f.type == 'general').toList();
    if (facts.isEmpty) return null;
    facts.shuffle();
    return facts.first;
  }

  Fact? getCityFact(String city) {
    final facts = getActiveFacts()
        .where((f) => f.type == 'city' && f.city == city)
        .toList();

    if (facts.isEmpty) return null;
    facts.shuffle();
    return facts.first;
  }

  // 🔜 Будущая оптимизация (раскомментировать через 3–6 месяцев)
  /*
  Future<void> cleanupConsumed({Duration olderThan = const Duration(days: 7)}) async {
    final cutoff = DateTime.now().subtract(olderThan);
    final keysToDelete = <String>[];
    _box.values.forEach((fact) {
      if (fact.isConsumed && fact.consumedAt != null && fact.consumedAt!.isBefore(cutoff)) {
        keysToDelete.add(fact.id);
      }
    });

    if (keysToDelete.isNotEmpty) {
      await _box.deleteAll(keysToDelete);
      print('🧹 Очищено ${keysToDelete.length} старых consumed-фактов');
    }
  }
  */
}