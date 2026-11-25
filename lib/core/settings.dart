import 'network/api_client.dart';

/// The Preference Center's switches and dials, read from and written to the profile.
class Preferences {
  const Preferences({
    required this.discoveryRadiusKm,
    required this.datingLens,
    required this.discretionMode,
    required this.privateAccount,
    this.safeZoneSet = false,
    this.emergencyNumber,
  });

  /// How far Nearby reaches.
  final int discoveryRadiusKm;

  /// Whether dating intent is on (it records consent for dating preferences the first time).
  final bool datingLens;

  /// Notifications that give nothing away on the lock screen.
  final bool discretionMode;
  final bool privateAccount;
  final bool safeZoneSet;

  /// The local emergency number shown on safety surfaces (112 in India).
  final String? emergencyNumber;

  static const minRadiusKm = 1;
  static const maxRadiusKm = 25;

  /// From ProfileView.
  factory Preferences.fromJson(Map<String, dynamic> j) => Preferences(
    discoveryRadiusKm: (j['discoveryRadiusKm'] as num?)?.toInt() ?? 5,
    datingLens: j['datingLens'] as bool? ?? false,
    discretionMode: j['discretionMode'] as bool? ?? false,
    privateAccount: j['accountPrivacy'] == 'PRIVATE',
    safeZoneSet: j['safeZoneSet'] as bool? ?? false,
    emergencyNumber: j['emergencyNumber'] as String?,
  );

  Preferences copyWith({
    int? discoveryRadiusKm,
    bool? datingLens,
    bool? discretionMode,
    bool? privateAccount,
  }) => Preferences(
    discoveryRadiusKm: discoveryRadiusKm ?? this.discoveryRadiusKm,
    datingLens: datingLens ?? this.datingLens,
    discretionMode: discretionMode ?? this.discretionMode,
    privateAccount: privateAccount ?? this.privateAccount,
    safeZoneSet: safeZoneSet,
    emergencyNumber: emergencyNumber,
  );
}

/// One purpose the person can consent to (DPDP): what it uses, and what withdrawing does.
class ConsentPurpose {
  const ConsentPurpose({
    required this.purpose,
    required this.processes,
    required this.onWithdrawal,
    required this.granted,
  });

  /// The backend's key, e.g. `LOCATION_DISCOVERY`.
  final String purpose;
  final String processes;
  final String onWithdrawal;
  final bool granted;

  String get title => switch (purpose) {
    'LOCATION_DISCOVERY' => 'Location for Nearby',
    'DATING_PREFERENCES' => 'Dating preferences',
    'ROOTS_AND_LANGUAGES' => 'Roots and languages',
    'WELLBEING_SURVEY' => 'Wellbeing check-ins',
    _ => purpose,
  };

  /// From PurposeView.
  factory ConsentPurpose.fromJson(Map<String, dynamic> j) => ConsentPurpose(
    purpose: j['purpose'] as String,
    processes: j['processes'] as String? ?? '',
    onWithdrawal: j['onWithdrawal'] as String? ?? '',
    granted: j['state'] == 'GRANTED',
  );
}

/// A signed-in device.
class DeviceSession {
  const DeviceSession({
    required this.id,
    required this.device,
    required this.current,
    this.lastUsedAt,
  });

  final String id;
  final String device;
  final bool current;
  final DateTime? lastUsedAt;

  /// From SessionView.
  factory DeviceSession.fromJson(Map<String, dynamic> j) => DeviceSession(
    id: j['id'] as String,
    device: j['device'] as String? ?? 'Unknown device',
    current: j['current'] as bool? ?? false,
    lastUsedAt: j['lastUsedAt'] == null
        ? null
        : DateTime.parse(j['lastUsedAt'] as String),
  );
}

/// The Grievance Officer's published contact (IT Rules 3(2), DPDP).
class OfficerContact {
  const OfficerContact({required this.name, required this.email, this.address});

  final String name;
  final String email;
  final String? address;

  factory OfficerContact.fromJson(Map<String, dynamic> j) => OfficerContact(
    name: j['name'] as String? ?? '',
    email: j['email'] as String? ?? '',
    address: j['address'] as String?,
  );
}

/// Preferences, privacy and account controls.
abstract interface class SettingsRepository {
  Future<Preferences> preferences();

  /// Sends only what changed; returns the profile's new state.
  Future<Preferences> update({
    int? discoveryRadiusKm,
    bool? datingLens,
    bool? discretionMode,
    bool? privateAccount,
  });

  /// Stops sharing the area now; Nearby and the map forget it until it's shared again.
  Future<void> pauseLocation();

  Future<List<ConsentPurpose>> consents();

  Future<List<ConsentPurpose>> grant(String purpose);

  /// Deletes that purpose's data at once and blocks its use until it is granted again.
  Future<List<ConsentPurpose>> withdraw(String purpose);

  Future<List<DeviceSession>> sessions();

  Future<void> endSession(String sessionId);

  /// Everything OneDay holds about the person, as the server returns it.
  Future<Map<String, dynamic>> exportData();

  /// Permanent. The caller signs out afterwards.
  Future<void> deleteAccount();

  Future<OfficerContact> officer();
}

class ApiSettings implements SettingsRepository {
  ApiSettings(this.api);

  final ApiClient api;

  @override
  Future<Preferences> preferences() async => Preferences.fromJson(
    await api.get('/profile/me') as Map<String, dynamic>,
  );

  @override
  Future<Preferences> update({
    int? discoveryRadiusKm,
    bool? datingLens,
    bool? discretionMode,
    bool? privateAccount,
  }) async => Preferences.fromJson(
    await api.patch(
          '/profile/me',
          body: {
            'discoveryRadiusKm': ?discoveryRadiusKm,
            'datingLens': ?datingLens,
            'discretionMode': ?discretionMode,
            if (privateAccount != null)
              'accountPrivacy': privateAccount ? 'PRIVATE' : 'PUBLIC',
          },
        )
        as Map<String, dynamic>,
  );

  @override
  Future<void> pauseLocation() => api.post('/location/pause');

  List<ConsentPurpose> _purposes(dynamic json) => [
    for (final p in (json as List).cast<Map<String, dynamic>>())
      ConsentPurpose.fromJson(p),
  ];

  @override
  Future<List<ConsentPurpose>> consents() async =>
      _purposes(await api.get('/consents'));

  @override
  Future<List<ConsentPurpose>> grant(String purpose) async =>
      _purposes(await api.post('/consents/$purpose'));

  @override
  Future<List<ConsentPurpose>> withdraw(String purpose) async =>
      _purposes(await api.delete('/consents/$purpose'));

  @override
  Future<List<DeviceSession>> sessions() async => [
    for (final s
        in (await api.get('/auth/sessions') as List)
            .cast<Map<String, dynamic>>())
      DeviceSession.fromJson(s),
  ];

  @override
  Future<void> endSession(String sessionId) =>
      api.delete('/auth/sessions/$sessionId');

  @override
  Future<Map<String, dynamic>> exportData() async =>
      await api.get('/privacy/export') as Map<String, dynamic>;

  @override
  Future<void> deleteAccount() =>
      api.delete('/privacy/account', query: {'confirm': 'DELETE'});

  @override
  Future<OfficerContact> officer() async => OfficerContact.fromJson(
    await api.get('/grievances/officer') as Map<String, dynamic>,
  );
}

/// Demo mode: an in-memory copy that behaves like the server's.
class FakeSettings implements SettingsRepository {
  Preferences _prefs = const Preferences(
    discoveryRadiusKm: 5,
    datingLens: false,
    discretionMode: false,
    privateAccount: false,
    emergencyNumber: '112',
  );

  final _granted = <String>{'LOCATION_DISCOVERY', 'ROOTS_AND_LANGUAGES'};
  final _sessions = <DeviceSession>[
    const DeviceSession(id: 'this', device: 'This phone', current: true),
    const DeviceSession(id: 'old', device: 'Pixel 8 · Chrome', current: false),
  ];

  bool locationPaused = false;
  bool deleted = false;

  @override
  Future<Preferences> preferences() async => _prefs;

  @override
  Future<Preferences> update({
    int? discoveryRadiusKm,
    bool? datingLens,
    bool? discretionMode,
    bool? privateAccount,
  }) async {
    if (datingLens == true) _granted.add('DATING_PREFERENCES');
    return _prefs = _prefs.copyWith(
      discoveryRadiusKm: discoveryRadiusKm,
      datingLens: datingLens,
      discretionMode: discretionMode,
      privateAccount: privateAccount,
    );
  }

  @override
  Future<void> pauseLocation() async => locationPaused = true;

  List<ConsentPurpose> get _purposes => [
    for (final (key, processes, onWithdrawal) in const [
      (
        'LOCATION_DISCOVERY',
        'Your area, snapped to a neighbourhood, while the app is open.',
        'Your area is deleted and you leave Nearby and the map.',
      ),
      (
        'DATING_PREFERENCES',
        'Your gender and who you\'re interested in, for the Dating Lens.',
        'The Dating Lens turns off and those answers are deleted.',
      ),
      (
        'ROOTS_AND_LANGUAGES',
        'Your home region and languages, to find people from home.',
        'Your home region and languages are deleted.',
      ),
      (
        'WELLBEING_SURVEY',
        'Your answer to an occasional "was your time well spent?"',
        'Past answers are deleted and we stop asking.',
      ),
    ])
      ConsentPurpose(
        purpose: key,
        processes: processes,
        onWithdrawal: onWithdrawal,
        granted: _granted.contains(key),
      ),
  ];

  @override
  Future<List<ConsentPurpose>> consents() async => _purposes;

  @override
  Future<List<ConsentPurpose>> grant(String purpose) async {
    _granted.add(purpose);
    return _purposes;
  }

  @override
  Future<List<ConsentPurpose>> withdraw(String purpose) async {
    _granted.remove(purpose);
    if (purpose == 'DATING_PREFERENCES') {
      _prefs = _prefs.copyWith(datingLens: false);
    }
    return _purposes;
  }

  @override
  Future<List<DeviceSession>> sessions() async => List.of(_sessions);

  @override
  Future<void> endSession(String sessionId) async =>
      _sessions.removeWhere((s) => s.id == sessionId && !s.current);

  @override
  Future<Map<String, dynamic>> exportData() async => {
    'profile': {'displayName': 'Asha'},
    'moments': <Object>[],
    'consents': [for (final p in _granted) p],
  };

  @override
  Future<void> deleteAccount() async => deleted = true;

  @override
  Future<OfficerContact> officer() async => const OfficerContact(
    name: 'Grievance Officer',
    email: 'grievance@oneday.example',
    address: 'Bengaluru, Karnataka',
  );
}
