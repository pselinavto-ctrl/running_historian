import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Сервис для кэширования тайлов карты
/// Кэширует тайлы локально для офлайн-работы
class MapTileCacheService {
  static const String _tileCacheDir = 'map_tiles';
  static const int _maxCacheSizeMB = 100; // Максимальный размер кэша
  static const Duration _tileMaxAge = Duration(days: 30); // Срок жизни тайла

  Directory? _cacheDir;

  /// Инициализация кэша
  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory(path.join(appDir.path, _tileCacheDir));
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    print('🗺️ Кэш карты инициализирован: ${_cacheDir!.path}');
  }

  /// Получить тайл из кэша или загрузить
  Future<Uint8List?> getTile(int z, int x, int y, String urlTemplate) async {
    if (_cacheDir == null) await init();

    final tileFile = _getTileFile(z, x, y);
    
    // Проверяем кэш
    if (await tileFile.exists()) {
      final stat = await tileFile.stat();
      final age = DateTime.now().difference(stat.modified);
      
      // Если тайл свежий, возвращаем из кэша
      if (age < _tileMaxAge) {
        try {
          return await tileFile.readAsBytes();
        } catch (e) {
          print('⚠️ Ошибка чтения тайла из кэша: $e');
        }
      } else {
        // Удаляем устаревший тайл
        await tileFile.delete();
      }
    }

    // Загружаем тайл из сети
    try {
      final url = urlTemplate
          .replaceAll('{z}', z.toString())
          .replaceAll('{x}', x.toString())
          .replaceAll('{y}', y.toString());
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'RunningHistorian/1.0',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        
        // Сохраняем в кэш
        await tileFile.writeAsBytes(bytes);
        
        return bytes;
      }
    } catch (e) {
      print('⚠️ Ошибка загрузки тайла: $e');
      // Пытаемся вернуть из кэша даже если устарел
      if (await tileFile.exists()) {
        return await tileFile.readAsBytes();
      }
    }

    return null;
  }

  /// Предзагрузить тайлы для области вокруг точки
  /// [center] - центр области
  /// [radiusKm] - радиус в километрах (по умолчанию 15 км = квадрат 30x30)
  /// [zoomLevels] - уровни зума для загрузки
  Future<void> preloadArea(
    LatLng center, {
    double radiusKm = 15.0,
    List<int> zoomLevels = const [13, 14, 15, 16],
  }) async {
    if (_cacheDir == null) await init();

    print('🗺️ Начинаю предзагрузку тайлов для области ${radiusKm}км вокруг ${center.latitude}, ${center.longitude}');

    final distance = Distance();
    int totalTiles = 0;
    int loadedTiles = 0;

    for (final z in zoomLevels) {
      // Вычисляем границы тайлов
      final northEast = distance.offset(center, radiusKm * 1000, 45);
      final southWest = distance.offset(center, radiusKm * 1000, 225);

      final minTileX = _lonToTileX(southWest.longitude, z);
      final maxTileX = _lonToTileX(northEast.longitude, z);
      final minTileY = _latToTileY(northEast.latitude, z);
      final maxTileY = _latToTileY(southWest.latitude, z);

      for (int x = minTileX; x <= maxTileX; x++) {
        for (int y = minTileY; y <= maxTileY; y++) {
          totalTiles++;
          
          final tileFile = _getTileFile(z, x, y);
          
          // Пропускаем если уже есть свежий тайл
          if (await tileFile.exists()) {
            final stat = await tileFile.stat();
            if (DateTime.now().difference(stat.modified) < _tileMaxAge) {
              continue;
            }
          }

          // Загружаем тайл
          final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
          try {
            final response = await http.get(
              Uri.parse(url),
              headers: {'User-Agent': 'RunningHistorian/1.0'},
            ).timeout(const Duration(seconds: 5));

            if (response.statusCode == 200) {
              await tileFile.writeAsBytes(response.bodyBytes);
              loadedTiles++;
              
              // Небольшая задержка чтобы не перегружать сервер
              if (loadedTiles % 10 == 0) {
                await Future.delayed(const Duration(milliseconds: 100));
              }
            }
          } catch (e) {
            // Игнорируем ошибки при предзагрузке
          }
        }
      }
    }

    print('🗺️ Предзагрузка завершена: $loadedTiles/$totalTiles тайлов');
    
    // Очищаем старые тайлы если кэш слишком большой
    await _cleanupOldTiles();
  }

  /// Очистка старых тайлов
  Future<void> _cleanupOldTiles() async {
    if (_cacheDir == null) return;

    try {
      final files = _cacheDir!.listSync(recursive: true)
          .whereType<File>()
          .toList();

      // Сортируем по дате изменения
      files.sort((a, b) {
        try {
          return a.statSync().modified.compareTo(b.statSync().modified);
        } catch (_) {
          return 0;
        }
      });

      // Вычисляем размер кэша
      int totalSize = 0;
      for (final file in files) {
        try {
          totalSize += file.statSync().size;
        } catch (_) {}
      }

      final maxSize = _maxCacheSizeMB * 1024 * 1024;

      // Удаляем старые файлы если превышен лимит
      if (totalSize > maxSize) {
        int deletedSize = 0;
        for (final file in files) {
          try {
            final size = file.statSync().size;
            await file.delete();
            deletedSize += size;
            if (totalSize - deletedSize <= maxSize * 0.8) break;
          } catch (_) {}
        }
        print('🗑️ Очищено ${(deletedSize / 1024 / 1024).toStringAsFixed(2)} MB кэша');
      }
    } catch (e) {
      print('⚠️ Ошибка очистки кэша: $e');
    }
  }

  /// Получить файл тайла
  File _getTileFile(int z, int x, int y) {
    final tilePath = path.join(_cacheDir!.path, '$z', '$x', '$y.png');
    return File(tilePath);
  }

  /// Конвертация долготы в номер тайла X
  int _lonToTileX(double lon, int z) {
    return ((lon + 180.0) / 360.0 * (1 << z)).floor();
  }

  /// Конвертация широты в номер тайла Y
  int _latToTileY(double lat, int z) {
    final latRad = lat * math.pi / 180.0;
    return ((1.0 - (0.5 * (math.log((1 + math.sin(latRad)) / (1 - math.sin(latRad))) / math.pi))) * (1 << z)).floor();
  }
}
