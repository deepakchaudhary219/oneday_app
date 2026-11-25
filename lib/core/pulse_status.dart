import 'network/api_client.dart';

/// How you're doing, for friends only, for 24 hours. Exactly the backend's moods.
enum Mood {
  happy('HAPPY', 'Happy', '😊'),
  chill('CHILL', 'Chill', '😌'),
  focused('FOCUSED', 'Heads down', '🎧'),
  adventurous('ADVENTUROUS', 'Up for adventure', '🧗'),
  social('SOCIAL', 'Feeling social', '🫂'),
  celebrating('CELEBRATING', 'Celebrating', '🥳'),
  onTheMove('ON_THE_MOVE', 'On the move', '🚆'),
  tired('TIRED', 'Tired', '😴'),
  homesick('HOMESICK', 'Missing home', '🏡'),
  low('LOW', 'Feeling low', '🌧️');

  const Mood(this.api, this.label, this.emoji);

  final String api;
  final String label;
  final String emoji;

  static Mood? fromApi(Object? value) {
    for (final m in values) {
      if (m.api == value) return m;
    }
    return null;
  }
}

/// A friend's status. There is no seen-by list and no like: a low mood asks for a check-in instead.
class FriendStatus {
  const FriendStatus({
    required this.connectionId,
    required this.statusId,
    required this.firstName,
    required this.moodLabel,
    required this.emoji,
    this.note,
    this.checkIn = false,
  });

  final String connectionId;
  final String statusId;
  final String firstName;
  final String moodLabel;
  final String emoji;
  final String? note;

  /// The server suggests reaching out (their mood is low).
  final bool checkIn;

  /// From FriendStatusView.
  factory FriendStatus.fromJson(Map<String, dynamic> j) => FriendStatus(
    connectionId: j['connectionId'] as String? ?? '',
    statusId: j['statusId'] as String? ?? '',
    firstName: j['firstName'] as String? ?? '',
    moodLabel:
        j['moodLabel'] as String? ?? Mood.fromApi(j['mood'])?.label ?? '',
    emoji: j['emoji'] as String? ?? '',
    note: j['note'] as String?,
    checkIn: j['checkIn'] as bool? ?? false,
  );
}

abstract interface class PulseRepository {
  /// Null when no status is set (or it expired).
  Future<Mood?> mine();

  Future<void> set(Mood mood, {String? note});

  Future<void> clear();

  Future<List<FriendStatus>> friends();
}

class ApiPulse implements PulseRepository {
  ApiPulse(this.api);

  final ApiClient api;

  @override
  Future<Mood?> mine() async {
    final json = await api.get('/pulse-status/mine'); // 204 when none
    return json is Map ? Mood.fromApi(json['mood']) : null;
  }

  @override
  Future<void> set(Mood mood, {String? note}) {
    final text = note?.trim() ?? '';
    return api.put(
      '/pulse-status',
      body: {
        'mood': mood.api,
        'emoji': mood.emoji,
        if (text.isNotEmpty) 'note': text,
      },
    );
  }

  @override
  Future<void> clear() => api.delete('/pulse-status');

  @override
  Future<List<FriendStatus>> friends() async => [
    for (final s
        in (await api.get('/pulse-status/friends') as List)
            .cast<Map<String, dynamic>>())
      FriendStatus.fromJson(s),
  ];
}

class FakePulse implements PulseRepository {
  Mood? current;

  @override
  Future<Mood?> mine() async => current;

  @override
  Future<void> set(Mood mood, {String? note}) async => current = mood;

  @override
  Future<void> clear() async => current = null;

  @override
  Future<List<FriendStatus>> friends() async => const [
    FriendStatus(
      connectionId: 'c1',
      statusId: 'ps1',
      firstName: 'Riya',
      moodLabel: 'Up for adventure',
      emoji: '🧗',
      note: 'Nandi Hills on Sunday?',
    ),
    FriendStatus(
      connectionId: 'c2',
      statusId: 'ps2',
      firstName: 'Arjun',
      moodLabel: 'Feeling low',
      emoji: '🌧️',
      checkIn: true,
    ),
  ];
}
