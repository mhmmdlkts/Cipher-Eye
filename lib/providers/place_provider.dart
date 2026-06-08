import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';

/// Reverse-geocodes a "lat,long" string to "City, Country". Falls back to the
/// raw coordinates if geocoding is unavailable. Cached per coordinate (family).
final placeProvider =
    FutureProvider.family<String, String>((ref, coords) async {
  try {
    final parts = coords.split(',');
    final lat = double.parse(parts[0].trim());
    final lng = double.parse(parts[1].trim());
    final placemarks = await placemarkFromCoordinates(lat, lng);
    if (placemarks.isEmpty) return coords;
    final p = placemarks.first;
    final city = (p.locality?.isNotEmpty ?? false)
        ? p.locality
        : p.administrativeArea;
    final pieces = [city, p.country]
        .where((s) => s != null && s.isNotEmpty)
        .toList();
    return pieces.isEmpty ? coords : pieces.join(', ');
  } catch (_) {
    return coords;
  }
});
