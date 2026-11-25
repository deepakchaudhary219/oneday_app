import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'amas.dart';
import 'api_repositories.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_repository.dart';
import 'capsules.dart';
import 'capture.dart';
import 'dates.dart';
import 'device.dart';
import 'e2ee.dart';
import 'fake_repositories.dart';
import 'figures.dart';
import 'live.dart';
import 'location.dart';
import 'models.dart';
import 'network/api_client.dart';
import 'network/api_config.dart';
import 'network/token_store.dart';
import 'plans.dart';
import 'plus_ledger.dart';
import 'prompts.dart';
import 'pulse_status.dart';
import 'realtime.dart';
import 'relays.dart';
import 'repositories.dart';
import 'right_now.dart';
import 'safety.dart';
import 'settings.dart';
import 'story_map.dart';
import 'threads.dart';

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
  if (api != null) return ApiAuthRepository(api);
  // Demo mode can start signed in (screenshots, design reviews): --dart-define=ONEDAY_DEMO_SIGNED_IN=true
  const signedIn = bool.fromEnvironment('ONEDAY_DEMO_SIGNED_IN');
  return FakeAuthRepository(
    initial: signedIn
        ? const AuthState(AuthStage.signedIn)
        : AuthState.signedOut,
  );
});

final locationShareProvider = Provider<LocationShare>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null
      ? FakeLocationShare()
      : ApiLocationShare(api, ref.watch(locationSourceProvider));
});

/// The in-app camera. With no camera (simulators, tests, a refused permission) stories are shared as words.
final captureSourceProvider = Provider<CaptureSource>((ref) {
  final camera = DeviceCamera();
  ref.onDispose(camera.dispose);
  return camera;
});

/// Where the phone is, for Nearby and the map: a pinned dev location when ONEDAY_DEV_LOCATION is set,
/// otherwise the device (foreground only).
final locationSourceProvider = Provider<LocationSource>(
  (ref) => DevLocationSource.pinned
      ? const DevLocationSource()
      : const DeviceLocationSource(),
);

/// Date Mode needs a precise position (only while both people share, inside the time box).
final preciseLocationSourceProvider = Provider<LocationSource>(
  (ref) => DevLocationSource.pinned
      ? const DevLocationSource()
      : const DeviceLocationSource(precise: true),
);

final pushTokenSourceProvider = Provider<PushTokenSource>(
  (ref) => const NoPushTokens(),
);

/// Registers this phone for pushes while signed in, and unregisters it on sign-out.
final pushRegistrationProvider = Provider<PushRegistration?>((ref) {
  final api = ref.watch(apiClientProvider);
  if (api == null) return null;
  final push = PushRegistration(api, ref.watch(pushTokenSourceProvider));
  ref.listen(
    authControllerProvider.select((s) => s.stage),
    (_, stage) => stage == AuthStage.signedIn
        ? push.register()
        : push.unregister(),
    fireImmediately: true,
  );
  return push;
});

final checkoutLauncherProvider = Provider<CheckoutLauncher>(
  (ref) => RazorpayCheckout(),
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

final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakeSafety() : ApiSafety(api);
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakeSettings() : ApiSettings(api);
});

final mapRepositoryProvider = Provider<MapRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakeMap() : ApiMap(api);
});

/// The Story Map through one lens; each lens is its own server query.
final storyMapProvider = FutureProvider.autoDispose
    .family<StoryMapData, MapLens>(
      (ref, lens) => ref.watch(mapRepositoryProvider).stories(lens),
    );

/// What the server pushes while signed in (chat messages, notices, friends' status). Empty in demo mode and
/// while signed out; the socket closes when the session ends and reopens with the next one.
final realtimeEventsProvider = StreamProvider<RealtimeEvent>((ref) {
  final api = ref.watch(apiClientProvider);
  final signedIn = ref.watch(
    authControllerProvider.select((s) => s.stage == AuthStage.signedIn),
  );
  if (api == null || !signedIn) return const Stream.empty();
  final client = RealtimeClient(
    url: RealtimeClient.socketUrl(ApiConfig.baseUrl),
    accessToken: api.freshAccessToken,
  );
  ref.onDispose(client.dispose);
  client.start();
  return client.events;
});

final promptRepositoryProvider = Provider<PromptRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakePrompts() : ApiPrompts(api);
});

final todaysPromptProvider = FutureProvider.autoDispose<TodaysPrompt>(
  (ref) => ref.watch(promptRepositoryProvider).today(),
);

final pulseRepositoryProvider = Provider<PulseRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakePulse() : ApiPulse(api);
});

final friendStatusesProvider = FutureProvider.autoDispose<List<FriendStatus>>(
  (ref) => ref.watch(pulseRepositoryProvider).friends(),
);

final plansRepositoryProvider = Provider<PlansRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakePlans() : ApiPlans(api);
});

final nearbyPlansProvider = FutureProvider.autoDispose<List<PlanCard>>(
  (ref) => ref.watch(plansRepositoryProvider).nearby(),
);

final myPlansProvider = FutureProvider.autoDispose<List<PlanDetail>>(
  (ref) => ref.watch(plansRepositoryProvider).mine(),
);

final datesRepositoryProvider = Provider<DatesRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakeDates() : ApiDates(api);
});

final datesProvider = FutureProvider.autoDispose<List<DatePlan>>(
  (ref) => ref.watch(datesRepositoryProvider).list(),
);

final rightNowRepositoryProvider = Provider<RightNowRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakeRightNow() : ApiRightNow(api);
});

final capsuleRepositoryProvider = Provider<CapsuleRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakeCapsules() : ApiCapsules(api);
});

final threadsRepositoryProvider = Provider<ThreadsRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakeThreads() : ApiThreads(api);
});

final threadsProvider = FutureProvider.autoDispose<List<StoryThread>>(
  (ref) => ref.watch(threadsRepositoryProvider).list(),
);

final plusLedgerRepositoryProvider = Provider<PlusLedgerRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakePlusLedger() : ApiPlusLedger(api);
});

final relayRepositoryProvider = Provider<RelayRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakeRelays() : ApiRelays(api);
});

final figuresRepositoryProvider = Provider<FiguresRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakeFigures() : ApiFigures(api);
});

final amasRepositoryProvider = Provider<AmasRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakeAmas() : ApiAmas(api);
});

final amasProvider = FutureProvider.autoDispose<List<Ama>>(
  (ref) => ref.watch(amasRepositoryProvider).list(),
);

/// End-to-end encrypted chat for this install (null in demo mode). Signing out forgets this device's keys: the
/// server unlinks the device with the session.
final encryptedChatProvider = Provider<EncryptedChat?>((ref) {
  final api = ref.watch(apiClientProvider);
  if (api == null) return null;
  final chat = EncryptedChat(api, SecureKeyValueStore());
  ref.listen(
    authControllerProvider.select((s) => s.stage),
    (previous, stage) {
      if (previous == AuthStage.signedIn && stage == AuthStage.signedOut) {
        chat.forgetDevice();
      }
    },
  );
  return chat;
});

final liveRepositoryProvider = Provider<LiveRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? FakeLive() : ApiLive(api);
});
