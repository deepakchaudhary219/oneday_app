import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_repositories.dart';
import 'models.dart';
import 'repositories.dart';

/// The single place the data source is chosen. Override in tests; replace with the API client later.
final dataProvider = Provider<FakeData>((ref) => FakeData());

final nearbyRepositoryProvider = Provider<NearbyRepository>(
  (ref) => ref.watch(dataProvider),
);
final signalsRepositoryProvider = Provider<SignalsRepository>(
  (ref) => ref.watch(dataProvider),
);
final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ref.watch(dataProvider),
);
final storyRepositoryProvider = Provider<StoryRepository>(
  (ref) => ref.watch(dataProvider),
);

final nearbyMomentsProvider = FutureProvider.autoDispose<List<NearbyMoment>>(
  (ref) => ref.watch(nearbyRepositoryProvider).nearby(),
);

final friendsStoriesProvider = FutureProvider<List<Story>>(
  (ref) => ref.watch(storyRepositoryProvider).friendsStories(),
);

final conversationsProvider = FutureProvider<List<Conversation>>(
  (ref) => ref.watch(chatRepositoryProvider).conversations(),
);
