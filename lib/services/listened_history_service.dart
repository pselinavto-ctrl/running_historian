import 'dart:convert';
import 'package:crypto/crypto.dart'; // 👈 ДОБАВИМ ДЛЯ ХЭШЕЙ
import 'package:hive/hive.dart';
import '../domain/listened_fact.dart';

class ListenedHistoryService {
  static const String _boxName = 'listened_facts';
  static const int _maxFacts = 1000;
  
  // 👈 ПРАВИЛЬНО: используем уже открытый бокс
  Box<ListenedFact> get _box => Hive.box<ListenedFact>(_boxName);
  
  // 👈 Безопасный хэш текста
  static String _hashText(String text) {
    return sha1.convert(utf8.encode(text)).toString();
  }
  
  Future<void> addFact(ListenedFact fact) async {
    final box = _box; // 👈 НЕ открываем заново!
    
    // 👈 ПРАВИЛЬНАЯ очистка старых фактов
    if (box.length >= _maxFacts) {
      final sorted = box.values.toList()
        ..sort((a, b) => a.listenedAt.compareTo(b.listenedAt));
      
      final toRemove = sorted.take(box.length - _maxFacts + 1);
      
      for (final factToRemove in toRemove) {
        await box.delete(factToRemove.id);
      }
    }
    
    await box.put(fact.id, fact);
    print('📝 Факт добавлен в историю (${box.length}/$_maxFacts): ${fact.text.substring(0, 30)}...');
  }
  
  // Антидубликаты в сессии
  final Set<String> _sessionFactHashes = {};
  
  bool isNewFactForSession(String text) {
    final hash = _hashText(text); // 👈 Безопасный хэш
    if (_sessionFactHashes.contains(hash)) return false;
    _sessionFactHashes.add(hash);
    return true;
  }
  
  void clearSessionCache() {
    _sessionFactHashes.clear();
  }
  
  // 👈 Остальные методы остаются, но используют _box вместо _openBox()
  Future<List<ListenedFact>> getAllFacts() async {
    final facts = _box.values.toList();
    facts.sort((a, b) => b.listenedAt.compareTo(a.listenedAt));
    return facts;
  }
  
  Future<List<ListenedFact>> getFactsByType(FactType type) async {
    final allFacts = await getAllFacts();
    return allFacts.where((fact) => fact.factType == type).toList();
  }
  
  Future<List<ListenedFact>> getFactsByPoi(String poiId) async {
    final allFacts = await getAllFacts();
    return allFacts.where((fact) => fact.poiId == poiId).toList();
  }
  
  Future<Map<String, dynamic>> getStats() async {
    final allFacts = await getAllFacts();
    
    return {
      'totalFacts': allFacts.length,
      'poiFacts': allFacts.where((f) => f.factType == FactType.poi).length,
      'generalFacts': allFacts.where((f) => f.factType == FactType.general).length,
      'contextFacts': allFacts.where((f) => f.factType == FactType.context).length,
      'firstFactDate': allFacts.isNotEmpty ? allFacts.last.listenedAt : null,
      'lastFactDate': allFacts.isNotEmpty ? allFacts.first.listenedAt : null,
    };
  }
  
  Future<void> deleteFact(String id) async {
    await _box.delete(id);
  }
  
  Future<void> clearHistory() async {
    await _box.clear();
  }
  
  Future<String> exportToJson() async {
    final facts = await getAllFacts();
    final jsonList = facts.map((fact) => fact.toJson()).toList();
    return jsonEncode(jsonList);
  }
  
  Future<List<ListenedFact>> search(String query) async {
    final allFacts = await getAllFacts();
    final lowercaseQuery = query.toLowerCase();
    
    return allFacts.where((fact) {
      return fact.text.toLowerCase().contains(lowercaseQuery) ||
             fact.poiName?.toLowerCase().contains(lowercaseQuery) == true;
    }).toList();
  }
}