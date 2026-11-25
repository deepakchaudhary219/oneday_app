import 'network/api_client.dart';
import 'network/api_error.dart';
import 'repositories.dart';

/// What lights up on the Story Map. Each lens is one server query, so the phone never filters people itself.
enum MapLens {
  everything('Everything'),
  roots('Roots'),
  language('My languages'),
  city('Whole city'),
  prompt('Today\'s prompt');

  const MapLens(this.label);

  final String label;

  /// The `scope` query parameter.
  String get scope => switch (this) {
    MapLens.roots => 'ROOTS',
    MapLens.language => 'LANGUAGE',
    MapLens.city => 'CITY',
    _ => 'RADIUS',
  };
}

/// One story inside an area: a first name and an activity, never more (Layer 0).
class MapStory {
  const MapStory({
    required this.momentId,
    required this.firstName,
    this.activity,
    this.previewUrl,
    this.why,
  });

  final String momentId;
  final String firstName;
  final String? activity;
  final String? previewUrl;
  final String? why;

  /// From StoryCard.
  factory MapStory.fromJson(Map<String, dynamic> j) => MapStory(
    momentId: j['momentId'] as String? ?? '',
    firstName: j['firstName'] as String? ?? '',
    activity: j['activity'] as String?,
    previewUrl: j['previewUrl'] as String?,
    why: j['whyYouSeeThis'] as String?,
  );
}

/// A k-anonymous area with stories in it. The centre is the area's, not a person's.
class MapArea {
  const MapArea({
    required this.id,
    required this.name,
    required this.count,
    required this.seed,
    this.lat,
    this.lon,
    this.activity,
    this.busy = false,
    this.stories = const [],
  });

  final String id;

  /// A short label for the area: its vibe ("Street food evening"), season or top activity.
  final String name;

  /// Stories in the area (shown plus the "more" the server didn't list).
  final int count;
  final int seed;
  final double? lat;
  final double? lon;
  final String? activity;

  /// Someone is sharing live right now.
  final bool busy;
  final List<MapStory> stories;

  /// From Cluster.
  factory MapArea.fromJson(Map<String, dynamic> j) {
    final stories = [
      for (final s in (j['stories'] as List? ?? const []))
        MapStory.fromJson((s as Map).cast<String, dynamic>()),
    ];
    final activities = (j['activities'] as List? ?? const []).cast<String>();
    final id = j['id'] as String? ?? '';
    String? text(String key) {
      final value = j[key] as String?;
      return value == null || value.trim().isEmpty ? null : value;
    }

    return MapArea(
      id: id,
      name:
          text('vibe') ??
          text('season') ??
          (activities.isEmpty ? (text('people') ?? 'Stories') : activities.first),
      count: stories.length + ((j['more'] as num?)?.toInt() ?? 0),
      seed: id.hashCode,
      lat: (j['centerLat'] as num?)?.toDouble(),
      lon: (j['centerLon'] as num?)?.toDouble(),
      activity: activities.isEmpty ? null : activities.first,
      busy: j['liveNow'] as bool? ?? false,
      stories: stories,
    );
  }
}

class StoryMapData {
  const StoryMapData({required this.areas, this.message});

  final List<MapArea> areas;

  /// The server's line for an empty or thin map ("Quiet around you right now").
  final String? message;

  /// From StoryMap.
  factory StoryMapData.fromJson(Map<String, dynamic> j) => StoryMapData(
    areas: [
      for (final c in (j['clusters'] as List? ?? const []))
        MapArea.fromJson((c as Map).cast<String, dynamic>()),
    ],
    message: j['message'] as String?,
  );
}

abstract interface class MapRepository {
  /// Throws [LocationRequired] until the area has been shared.
  Future<StoryMapData> stories(MapLens lens);
}

class ApiMap implements MapRepository {
  ApiMap(this.api);

  final ApiClient api;

  @override
  Future<StoryMapData> stories(MapLens lens) async {
    try {
      final json = await api.get(
        '/map/stories',
        query: {
          'scope': lens.scope,
          if (lens == MapLens.prompt) 'todaysPrompt': true,
        },
      );
      return StoryMapData.fromJson(json as Map<String, dynamic>);
    } on ApiError catch (e) {
      if (e.code == 'LOCATION_REQUIRED') throw const LocationRequired();
      rethrow;
    }
  }
}

/// Demo mode: Bengaluru on a busy evening.
class FakeMap implements MapRepository {
  static const _all = [
    (MapArea(id: 'a1', name: 'Indiranagar', count: 14, seed: 1, lat: 12.9719, lon: 77.6412, activity: 'gig', busy: true), {MapLens.language, MapLens.prompt}),
    (MapArea(id: 'a2', name: 'Cubbon Park', count: 6, seed: 2, lat: 12.9763, lon: 77.5929, activity: 'park run'), <MapLens>{}),
    (MapArea(id: 'a3', name: 'Koramangala', count: 23, seed: 3, lat: 12.9352, lon: 77.6245, activity: 'street food', busy: true), {MapLens.roots, MapLens.language, MapLens.prompt}),
    (MapArea(id: 'a4', name: 'HSR Layout', count: 5, seed: 4, lat: 12.9116, lon: 77.6474, activity: 'cycling'), <MapLens>{}),
    (MapArea(id: 'a5', name: 'Jayanagar', count: 9, seed: 5, lat: 12.9308, lon: 77.5838, activity: 'chai at a café'), {MapLens.roots}),
    (MapArea(id: 'a6', name: 'MG Road', count: 11, seed: 6, lat: 12.9756, lon: 77.6068, activity: 'rooftop'), {MapLens.prompt}),
  ];

  @override
  Future<StoryMapData> stories(MapLens lens) async => StoryMapData(
    areas: [
      for (final (area, lenses) in _all)
        if (lens == MapLens.everything ||
            lens == MapLens.city ||
            lenses.contains(lens))
          area,
    ],
  );
}
