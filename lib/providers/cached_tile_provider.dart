// lib/providers/cached_tile_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/map_tile_cache_service.dart';

class CachedTileProvider extends TileProvider {
  final MapTileCacheService cache;
  final String urlTemplate;
  final String provider;

  CachedTileProvider({
    required this.cache,
    required this.urlTemplate,
    required this.provider,
  });

  @override
  ImageProvider<Object> getImage(TileCoordinates coordinates, TileLayer options) {
    return MemoryImageProvider(
      cache,
      coordinates.z,
      coordinates.x,
      coordinates.y,
      urlTemplate,
      provider,
    );
  }
}

class MemoryImageProvider extends ImageProvider<MemoryImageProvider> {
  final MapTileCacheService cache;
  final int z, x, y;
  final String urlTemplate;
  final String provider;

  const MemoryImageProvider(
    this.cache,
    this.z,
    this.x,
    this.y,
    this.urlTemplate,
    this.provider,
  );

  @override
  Future<MemoryImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<MemoryImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(MemoryImageProvider key, ImageDecoderCallback decode) {
    // Возвращаем completer, который загружает данные из кэша
    return OneFrameImageStreamCompleter(
      _loadAsync(key, decode),
    );
  }

  Future<ImageInfo> _loadAsync(MemoryImageProvider key, ImageDecoderCallback decode) async {
    final Uint8List? bytes = await cache.getTile(key.z, key.x, key.y, key.urlTemplate, key.provider);
    if (bytes == null) {
      throw Exception('Could not load image for $key');
    }
    final ImageDescriptor descriptor = await ImmutableBuffer.fromUint8List(bytes).then(
      (buffer) => ImageDescriptor.encoded(buffer),
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }
}