/// Where the phone is, only while the app is open (the backend snaps it to a ~0.7 km² cell and discards the
/// coordinates). The device implementation (geolocator, foreground only) slots in here; until then a dev build can
/// pin a location:
///
///     flutter run --dart-define=ONEDAY_DEV_LOCATION=12.9352,77.6245
abstract interface class LocationSource {
  /// Null when there's no permission or no fix.
  Future<({double lat, double lon})?> current();
}

class DevLocationSource implements LocationSource {
  const DevLocationSource();

  static const _pinned = String.fromEnvironment('ONEDAY_DEV_LOCATION');

  @override
  Future<({double lat, double lon})?> current() async {
    final parts = _pinned.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lon = double.tryParse(parts[1].trim());
    return lat == null || lon == null ? null : (lat: lat, lon: lon);
  }
}
