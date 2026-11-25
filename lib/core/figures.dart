import 'network/api_client.dart';
import 'network/api_error.dart';

/// What kind of public figure someone is. Exactly the backend's categories.
enum FigureCategory {
  creator('CREATOR', 'Creator'),
  artist('ARTIST', 'Artist'),
  musician('MUSICIAN', 'Musician'),
  athlete('ATHLETE', 'Athlete'),
  journalist('JOURNALIST', 'Journalist'),
  official('PUBLIC_OFFICIAL', 'Public official'),
  organisation('ORGANISATION', 'Organisation');

  const FigureCategory(this.api, this.label);

  final String api;
  final String label;

  static FigureCategory? fromApi(Object? value) {
    for (final c in values) {
      if (c.api == value) return c;
    }
    return null;
  }
}

/// A staff-verified public account, followed one way. Its follower count is shown to the figure only.
class Figure {
  const Figure({
    required this.handle,
    required this.publicName,
    this.category,
    this.bio,
    this.verified = false,
    this.following = false,
  });

  final String handle;
  final String publicName;
  final FigureCategory? category;
  final String? bio;
  final bool verified;
  final bool following;

  /// From FigureView.
  factory Figure.fromJson(Map<String, dynamic> j) => Figure(
    handle: j['handle'] as String,
    publicName: j['publicName'] as String? ?? '',
    category: FigureCategory.fromApi(j['category']),
    bio: j['bio'] as String?,
    verified: j['verified'] as bool? ?? false,
    following: j['following'] as bool? ?? false,
  );
}

/// Your own figure account or application.
class MyFigure {
  const MyFigure({
    required this.handle,
    required this.publicName,
    required this.status,
    this.followers,
  });

  final String handle;
  final String publicName;

  /// `PENDING`, `APPROVED`, `REJECTED` or `REVOKED`.
  final String status;

  /// Only you see this.
  final int? followers;

  bool get approved => status == 'APPROVED';

  factory MyFigure.fromJson(Map<String, dynamic> j) => MyFigure(
    handle: j['handle'] as String? ?? '',
    publicName: j['publicName'] as String? ?? '',
    status: j['status'] as String? ?? 'PENDING',
    followers: (j['followers'] as num?)?.toInt(),
  );
}

/// A story from a figure you follow. The feed carries no location.
class FigurePost {
  const FigurePost({
    required this.handle,
    required this.momentId,
    this.caption,
    this.activity,
    this.mediaUrl,
    this.postedAt,
  });

  final String handle;
  final String momentId;
  final String? caption;
  final String? activity;
  final String? mediaUrl;
  final DateTime? postedAt;

  /// From FeedItem.
  factory FigurePost.fromJson(Map<String, dynamic> j) {
    final m = (j['moment'] as Map?)?.cast<String, dynamic>() ?? const {};
    return FigurePost(
      handle: j['handle'] as String? ?? '',
      momentId: m['id'] as String? ?? '',
      caption: m['caption'] as String?,
      activity: m['activityTag'] as String?,
      mediaUrl: m['mediaUrl'] as String?,
      postedAt: m['postedAt'] == null
          ? null
          : DateTime.parse(m['postedAt'] as String).toLocal(),
    );
  }
}

/// No public figure has that handle (or it isn't approved).
class FigureNotFound implements Exception {
  const FigureNotFound();
}

abstract interface class FiguresRepository {
  Future<List<Figure>> following();

  Future<List<FigurePost>> feed();

  /// Throws [FigureNotFound].
  Future<Figure> figure(String handle);

  Future<Figure> follow(String handle);

  Future<void> unfollow(String handle);

  /// Null when you haven't applied.
  Future<MyFigure?> mine();

  Future<MyFigure> apply({
    required String handle,
    required String publicName,
    required FigureCategory category,
    required String evidence,
    String? bio,
  });
}

class ApiFigures implements FiguresRepository {
  ApiFigures(this.api);

  final ApiClient api;

  static final handlePattern = RegExp(r'^[a-z0-9_.]{3,30}$');

  /// "@Riya.Sings " becomes "riya.sings".
  static String normalise(String handle) =>
      handle.trim().replaceFirst(RegExp('^@'), '').toLowerCase();

  @override
  Future<List<Figure>> following() async => [
    for (final f
        in (await api.get('/figures/following') as List)
            .cast<Map<String, dynamic>>())
      Figure.fromJson(f),
  ];

  @override
  Future<List<FigurePost>> feed() async => [
    for (final f
        in (await api.get('/figures/feed', query: {'limit': 50}) as List)
            .cast<Map<String, dynamic>>())
      FigurePost.fromJson(f),
  ];

  @override
  Future<Figure> figure(String handle) async {
    try {
      return Figure.fromJson(
        await api.get('/figures/${normalise(handle)}') as Map<String, dynamic>,
      );
    } on ApiError catch (e) {
      if (e.status == 404) throw const FigureNotFound();
      rethrow;
    }
  }

  @override
  Future<Figure> follow(String handle) async => Figure.fromJson(
    await api.post('/figures/${normalise(handle)}/follow')
        as Map<String, dynamic>,
  );

  @override
  Future<void> unfollow(String handle) =>
      api.delete('/figures/${normalise(handle)}/follow');

  @override
  Future<MyFigure?> mine() async {
    final json = await api.get('/figures/me'); // 204 when none
    return json is Map ? MyFigure.fromJson(json.cast<String, dynamic>()) : null;
  }

  @override
  Future<MyFigure> apply({
    required String handle,
    required String publicName,
    required FigureCategory category,
    required String evidence,
    String? bio,
  }) async {
    final about = bio?.trim() ?? '';
    return MyFigure.fromJson(
      await api.post(
            '/figures/apply',
            body: {
              'handle': normalise(handle),
              'publicName': publicName.trim(),
              'category': category.api,
              'evidence': evidence.trim(),
              if (about.isNotEmpty) 'bio': about,
            },
          )
          as Map<String, dynamic>,
    );
  }
}

class FakeFigures implements FiguresRepository {
  final _following = <String>{'chef.ranveer'};
  MyFigure? applied;

  static const _all = [
    Figure(
      handle: 'chef.ranveer',
      publicName: 'Ranveer',
      category: FigureCategory.creator,
      bio: 'Cooking the food of every Indian state, one week each.',
      verified: true,
    ),
    Figure(
      handle: 'kerala.blasters',
      publicName: 'Kerala Blasters',
      category: FigureCategory.organisation,
      bio: 'Manjappada, this way.',
      verified: true,
    ),
  ];

  Figure _view(Figure f) => Figure(
    handle: f.handle,
    publicName: f.publicName,
    category: f.category,
    bio: f.bio,
    verified: f.verified,
    following: _following.contains(f.handle),
  );

  @override
  Future<List<Figure>> following() async => [
    for (final f in _all)
      if (_following.contains(f.handle)) _view(f),
  ];

  @override
  Future<List<FigurePost>> feed() async => [
    if (_following.contains('chef.ranveer'))
      const FigurePost(
        handle: 'chef.ranveer',
        momentId: 'fm1',
        caption: 'Week 12: Meghalaya. Jadoh tonight.',
        activity: 'cooking',
      ),
  ];

  @override
  Future<Figure> figure(String handle) async {
    final h = ApiFigures.normalise(handle);
    for (final f in _all) {
      if (f.handle == h) return _view(f);
    }
    throw const FigureNotFound();
  }

  @override
  Future<Figure> follow(String handle) async {
    _following.add(ApiFigures.normalise(handle));
    return figure(handle);
  }

  @override
  Future<void> unfollow(String handle) async =>
      _following.remove(ApiFigures.normalise(handle));

  @override
  Future<MyFigure?> mine() async => applied;

  @override
  Future<MyFigure> apply({
    required String handle,
    required String publicName,
    required FigureCategory category,
    required String evidence,
    String? bio,
  }) async => applied = MyFigure(
    handle: ApiFigures.normalise(handle),
    publicName: publicName.trim(),
    status: 'PENDING',
  );
}
