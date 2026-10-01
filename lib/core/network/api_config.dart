/// Where the API lives. Set at build time:
///
///     flutter run --dart-define=ONEDAY_API_URL=http://10.0.2.2:8080     # Android emulator → local backend
///     flutter run --dart-define=ONEDAY_API_URL=http://localhost:8080    # iOS simulator
///
/// Left empty, the app runs entirely on fake data (design and demo mode).
abstract final class ApiConfig {
  static const baseUrl = String.fromEnvironment('ONEDAY_API_URL');

  static bool get useFakeData => baseUrl.isEmpty;

  /// The privacy notice version the app shows at sign-up (must match the backend's current version).
  static const consentVersion = String.fromEnvironment(
    'ONEDAY_CONSENT_VERSION',
    defaultValue: '2026-09',
  );
}
