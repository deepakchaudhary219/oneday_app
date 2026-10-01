import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_repositories.dart';
import 'auth/auth_repository.dart';
import 'fake_repositories.dart';
import 'location.dart';
import 'models.dart';
import 'network/api_client.dart';
import 'network/api_config.dart';
import 'network/token_store.dart';
import 'repositories.dart';

/// The single place the data source is chosen: fake data when no ONEDAY_API_URL is set (design and demo mode),
/// the API otherwise. Tests override [dataProvider], [authRepositoryProvider] or [apiClientProvider].
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient?>((ref) {
  if (ApiConfig.useFakeData) return null;
  final client = ApiClient(
    baseUrl: ApiConfig.baseUrl,
    tokens: ref.watch(tokenStoreProvider),
  );
  ref.onDispose(client.dispose);
  return client;
});

final dataProvider = Provider<FakeData>((ref) => FakeData());

final _apiDataProvider = Provider<ApiData?>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? null : ApiData(api);
});

final nearbyRepositoryProvider = Provider<NearbyRepository>(
  (ref) => ref.watch(_apiDataProvider) ?? ref.watch(dataProvider),
);
final signalsRepositoryProvider = Provider<SignalsRepository>(
  (ref) => ref.watch(_apiDataProvider) ?? ref.watch(dataProvider),
);
final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ref.watch(_apiDataProvider) ?? ref.watch(dataProvider),
);
final storyRepositoryProvider = Provider<StoryRepository>(
  (ref) => ref.watch(_apiDataProvider) ?? ref.watch(dataProvider),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ref.watch(_apiDataProvider) ?? ref.watch(dataProvider),
);

final myProfileProvider = FutureProvider<MyProfile>(
  (ref) => ref.watch(profileRepositoryProvider).me(),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakeAuthRepository() : ApiAuthRepository(api);
});

final locationShareProvider = Provider<LocationShare>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null
      ? FakeLocationShare()
      : ApiLocationShare(api, const DevLocationSource());
});

final nearbyMomentsProvider = FutureProvider.autoDispose<List<NearbyMoment>>(
  (ref) => ref.watch(nearbyRepositoryProvider).nearby(),
);

final friendsStoriesProvider = FutureProvider<List<Story>>(
  (ref) => ref.watch(storyRepositoryProvider).friendsStories(),
);

final conversationsProvider = FutureProvider<List<Conversation>>(
  (ref) => ref.watch(chatRepositoryProvider).conversations(),
);
