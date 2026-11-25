import 'network/api_client.dart';

/// A Time Capsule: a message sealed until a chosen day, for yourself or a Connection. Its content stays hidden
/// until then, even from you.
class Capsule {
  const Capsule({
    required this.id,
    required this.direction,
    required this.open,
    required this.opensAt,
    this.withFirstName,
    this.message,
    this.mediaUrl,
  });

  final String id;

  /// `SELF`, `SENT` or `RECEIVED`.
  final String direction;
  final bool open;
  final DateTime opensAt;

  /// The other person (null for a capsule to yourself).
  final String? withFirstName;

  /// Only once open.
  final String? message;
  final String? mediaUrl;

  bool get toSelf => direction == 'SELF';

  bool get sent => direction == 'SENT';

  /// From CapsuleView.
  factory Capsule.fromJson(Map<String, dynamic> j) => Capsule(
    id: j['id'] as String,
    direction: j['direction'] as String? ?? 'SELF',
    open: j['state'] == 'OPEN',
    opensAt: DateTime.parse(j['opensAt'] as String).toLocal(),
    withFirstName: j['withFirstName'] as String?,
    message: j['message'] as String?,
    mediaUrl: j['mediaUrl'] as String?,
  );
}

abstract interface class CapsuleRepository {
  /// Capsules from Connections, sealed or already open.
  Future<List<Capsule>> incoming();

  /// Capsules you sealed: for yourself and for Connections.
  Future<List<Capsule>> sent();

  Future<Capsule> open(String capsuleId);

  /// [opensAt] is a day between tomorrow and five years from now; [connectionId] null seals it for yourself.
  Future<Capsule> seal({
    required String message,
    required DateTime opensAt,
    String? connectionId,
  });

  /// Withdraws a capsule you sealed, before it opens (an opened one can't be withdrawn).
  Future<void> delete(String capsuleId);
}

class ApiCapsules implements CapsuleRepository {
  ApiCapsules(this.api);

  final ApiClient api;

  static const maxMessage = 1000;
  static const maxWaiting = 20;

  List<Capsule> _list(dynamic json) => [
    for (final c in (json as List).cast<Map<String, dynamic>>())
      Capsule.fromJson(c),
  ];

  @override
  Future<List<Capsule>> incoming() async =>
      _list(await api.get('/capsules/incoming'));

  @override
  Future<List<Capsule>> sent() async => _list(await api.get('/capsules/sent'));

  @override
  Future<Capsule> open(String capsuleId) async => Capsule.fromJson(
    await api.get('/capsules/$capsuleId') as Map<String, dynamic>,
  );

  @override
  Future<Capsule> seal({
    required String message,
    required DateTime opensAt,
    String? connectionId,
  }) async => Capsule.fromJson(
    await api.post(
          '/capsules',
          body: {
            'message': message.trim(),
            'opensAt': opensAt.toUtc().toIso8601String(),
            'connectionId': ?connectionId,
          },
        )
        as Map<String, dynamic>,
  );

  @override
  Future<void> delete(String capsuleId) => api.delete('/capsules/$capsuleId');
}

class FakeCapsules implements CapsuleRepository {
  FakeCapsules({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    final now = _clock();
    _all.addAll([
      Capsule(
        id: 'cp1',
        direction: 'RECEIVED',
        open: true,
        opensAt: now.subtract(const Duration(days: 1)),
        withFirstName: 'Riya',
        message: 'One year since Nandi Hills. Same time next year?',
      ),
      Capsule(
        id: 'cp2',
        direction: 'SELF',
        open: false,
        opensAt: now.add(const Duration(days: 180)),
      ),
    ]);
  }

  final DateTime Function() _clock;
  final _all = <Capsule>[];

  @override
  Future<List<Capsule>> incoming() async => [
    for (final c in _all)
      if (c.direction == 'RECEIVED') c,
  ];

  @override
  Future<List<Capsule>> sent() async => [
    for (final c in _all)
      if (c.direction != 'RECEIVED') c,
  ];

  @override
  Future<Capsule> open(String capsuleId) async =>
      _all.firstWhere((c) => c.id == capsuleId);

  @override
  Future<Capsule> seal({
    required String message,
    required DateTime opensAt,
    String? connectionId,
  }) async {
    final capsule = Capsule(
      id: 'cp${_all.length + 1}',
      direction: connectionId == null ? 'SELF' : 'SENT',
      open: false,
      opensAt: opensAt,
      withFirstName: connectionId == null ? null : 'Your connection',
    );
    _all.add(capsule);
    return capsule;
  }

  @override
  Future<void> delete(String capsuleId) async =>
      _all.removeWhere((c) => c.id == capsuleId);
}
