# OneDay app (Flutter)

The OneDay mobile app: a camera-first, location-aware social and dating app. The backend lives in `deepakchaudhary219/oneday`. Its `docs/api/openapi.json` is the API contract and `docs/08-flutter-integration.md` is the integration guide.

## Design

[`docs/ui-ux-principles.md`](docs/ui-ux-principles.md) covers what we borrow from Snapchat, Instagram, Tinder and TikTok, what we refuse (infinite feeds, streaks, public counts), and the motion, visual, accessibility and code rules.

## Structure

```
lib/
  design_system/   tokens (colour, spacing, radii, motion, type), theme, components (incl. the swipe deck) and
                   illustration/ (drawn portraits and places for demo data and loading states);
                   screens import design_system.dart only
  core/            domain models, repository interfaces, fake data, Riverpod providers
    network/       ApiClient (token refresh, idempotency, retries, problem details), token storage, config
    auth/          AuthRepository (API + fake), AuthController (session state the router follows)
    api_repositories.dart   the repositories backed by the API
  features/        auth (welcome, phone, code, about you, email, face check), shell (camera-first pager), camera,
                   nearby, stories, signals, chats, map, profile, gallery
contract/          a copy of the backend's openapi.json, checked by test/core/contract_test.dart
```

- **Repositories:** screens depend on the repository interfaces in `core/repositories.dart`. `core/providers.dart` picks the source: `FakeData` when no API URL is set (design and demo mode), `ApiData` otherwise.
- **Networking:** `ApiClient` adds the bearer token, refreshes it once on a 401 however many requests fail at the same time, signs out when the refresh is rejected, sends an `Idempotency-Key` with every POST and reuses it on retries, retries network failures with backoff, and turns problem details into `ApiError`. Repositories turn known codes into typed exceptions (`LocationRequired`, `EmpathyCheck`, `SignupDetailsRequired`).
- **Sign-in:** phone first (+91 default), email one tap away. A new number is asked for name, date of birth and consent, and the same code is re-submitted. The face check is asked for at the first contact action (sending a signal), not at sign-up. The router redirects on the session state, so a session that ends anywhere returns to Welcome.
- **Gallery:** every component is on the gallery screen (Me → Design system gallery).

## Run and test

```bash
flutter pub get
flutter run                 # a device or simulator
flutter test                # unit, contract and widget tests, including small-phone and 200%-text layout
flutter analyze
```

### Against the local backend

```bash
# backend (deepakchaudhary219/oneday): dev profile logs OTP codes instead of sending SMS
SPRING_PROFILES_ACTIVE=dev java -jar target/oneday-0.0.1-SNAPSHOT.jar

# app: Android emulator reaches the host as 10.0.2.2; iOS simulator uses localhost
flutter run --dart-define=ONEDAY_API_URL=http://10.0.2.2:8080 --dart-define=ONEDAY_DEV_LOCATION=12.9716,77.5946

# end-to-end smoke test with the app's real client (email + phone sign-up, face check, location, nearby, refresh)
ONEDAY_LIVE_API=http://localhost:8080 ONEDAY_LIVE_LOG=/path/to/backend.log flutter test test/live
```

With no `ONEDAY_API_URL` the app runs on fake data: phone code `123456`, any email with a 12+ character password. Add `--dart-define=ONEDAY_DEMO_SIGNED_IN=true` to skip sign-in for demos and design reviews. Until a location plugin is added, `ONEDAY_DEV_LOCATION` supplies the area that "Share my area" sends. The web build can't call the API yet because the backend has no CORS setup.

### When the backend contract changes

Copy the backend's `docs/api/openapi.json` to `contract/openapi.json` and run `flutter test test/core/contract_test.dart`. It names every endpoint, request field and response field the app relies on that has gone missing.
