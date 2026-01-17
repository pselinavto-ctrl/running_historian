import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:running_historian/services/map_tile_cache_service.dart';

/// Создает виджет тайла с кэшированием
Widget buildCachedTile(
  TileCoordinates coordinates,
  TileLayer options,
  MapTileCacheService cacheService,
) {
  return FutureBuilder<Uint8List?>(
    future: cacheService.getTile(
      coordinates.z.round(),
      coordinates.x.round(),
      coordinates.y.round(),
      options.urlTemplate,
    ),
    builder: (context, snapshot) {
      if (snapshot.hasData && snapshot.data != null) {
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[200],
              child: const Center(
                child: Icon(Icons.error_outline, color: Colors.grey, size: 20),
              ),
            );
          },
        );
      } else if (snapshot.hasError) {
        return Container(
          color: Colors.grey[200],
          child: const Center(
            child: Icon(Icons.error_outline, color: Colors.grey, size: 20),
          ),
        );
      } else {
        return Container(
          color: Colors.grey[100],
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
    },
  );
}
