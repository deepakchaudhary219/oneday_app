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
- **Sharing a story:** the capture preview takes a caption and an activity and publishes through `StoryRepository`: `upload` (ticket → PUT to the signed URL with no bearer token → complete → wait for `READY`) and then `publish` (`POST /moments`). A Nearby share that needs the area shows "Share my area" and goes out after that tap; a share that needs the face check opens it and then continues. The camera is `DeviceCamera` (`core/device.dart`, the `camera` plugin): the screen opens it while visible and closes it in the background; tap for a photo, hold for a video. With no camera (simulators, tests, a refused permission) the drawn viewfinder stays and the story is shared as words. Lenses are a preview effect only: a photo is posted as taken, and its preview shows it that way.
- **Safety:** `showSafetySheet` (`features/safety`) is the one sheet for Report, Block and Leave quietly, opened from a chat's menu and from "Why you're seeing this" on Nearby. It sends exactly one target id (`SafetyTarget`), never a user id, and nothing in it notifies the other person.
- **Real time:** `RealtimeClient` (`core/realtime.dart`) is a receive-only STOMP client on `/ws`. It connects with a fresh access token, subscribes to `/user/queue/events`, and reconnects with backoff when the server closes the socket (token expiry, sign-out). `realtimeEventsProvider` runs it while signed in: an open chat appends pushed messages and the chat list refreshes. It uses `dart:io` sockets, so it does not connect in the web build.
- **Story Map:** the map reads `GET /map/stories` through `MapRepository`; each lens chip is one server query. Areas are placed on the drawn city by their relative positions. It is still the drawn city, not a map SDK.
- **Settings:** Me → menu opens the Preference Center (`features/settings`, route `/settings`): radius, Dating Lens, private account, Discretion Mode, stop sharing the area, per-purpose consent (withdrawing asks first and says what is deleted), signed-in devices, a copy of your data, account deletion (type DELETE) and the Grievance Officer.
- **Together** (Me → menu → Together, route `/together`): Today's Prompt (answer in words as a public story; nearby answers open once you have), friends' Pulse Status, and the ways in to Plans and Dates. Your own Pulse Status is the mood row on Me: tap a mood to share it with friends for a day, tap again to clear it.
- **Plans** (`features/plans`, route `/plans`): plans nearby and yours, asking to join, the Room (with the Empathy Mirror and live messages), approving requests as host, and hosting at a Safety-Verified Meeting Point.
- **Date Mode** (`features/dates`, route `/dates`): propose, accept or decline, the mutual location-sharing switch, a trusted contact, "I'm OK", SOS, "I'm home safe" and the Mutual Debrief. While both share and the date's time box is open, the Dates screen sends this phone's precise position about once a minute and shows the partner's last position (as coordinates; there is no map SDK).
- **Right Now, Threads and Time Capsules** (Together, routes `/right-now`, `/threads`, `/capsules`): start or stop a Right Now and say yes or not now to who's in, or say "I'm in" to someone nearby (a city where Right Now is off shows that, not an error); start a thread, invite Connections, join or decline an invitation, post words, delete your own posts, leave (new posts arrive over the socket); seal a capsule for yourself or a Connection, read opened ones, withdraw sealed ones. Thread posts and capsules are words only (photos there are a follow-up).
- **Plus and Your month** (Me → menu, routes `/plus`, `/ledger`): what Plus adds and what is never sold, subscribing and cancelling at period end; the private Real Value Ledger with last week's recap. Paying opens Razorpay's native checkout on Android and iOS (`razorpay_flutter`); elsewhere the checkout link is shown for a browser. Plus turns on when Razorpay's webhook reaches the server.
- **Story Relays** (`features/relays`, route `/relay/:momentId`, and "Answer with your own story" on Nearby's "Why you're seeing this"): the relay in order, adding your answer in words, and, on your own story, asking to spotlight an answer. Spotlight requests for your answers show at the top of Together.
- **Public figures and AMAs** (Together, routes `/figures`, `/amas`): find a verified account by handle, follow and unfollow, their stories today, apply for a public account; AMAs open to you, asking (optionally without your name), "Me too" votes, and for hosts: scheduling (with an optional Roots corridor), answering while live, hiding questions and cancelling before the start. Vote counts show to the host only.
- **Location:** `DeviceLocationSource` (`geolocator`), foreground only: coarse for Nearby and the map, precise for Date Mode. `ONEDAY_DEV_LOCATION` still pins a location for development.
- **Push:** `PushRegistration` registers this phone after sign-in (`POST /devices`) and unregisters it on sign-out, with a token from `PushTokenSource`. No token source is wired: Firebase Cloud Messaging needs the Firebase project files, so pushes are off and in-app notices carry everything.
- **Encrypted chat** (`core/e2ee.dart`, `libsignal_protocol_dart`): the lock button in a chat turns end-to-end encryption on (it never turns off). The install registers as a device with 100 one-time prekeys (topped up below 20), encrypts once per device of both people, commits to each message with HMAC-SHA256 (message franking), decrypts its inbox on the `e2ee` socket event and acknowledges it, and keeps decrypted messages only on the phone (secure storage, the last 300 per chat). Long-press someone's encrypted message to report it with proof. Signing out forgets the device keys. The on-device Empathy Mirror (`GET /empathy/lexicon`) isn't ported yet, so encrypted messages skip it.
- **Calls** (`features/calls`, `flutter_webrtc`): call from a chat; incoming calls open from the `call` socket event. Voice first; the layer chips ask for blurred or clear video, and the call runs at the lower of both choices. At Blurred the camera is sent at 1/16 resolution (blurred before it leaves the phone) and blurred again on screen; at Voice no video is sent.
- **Circle Live** (Together, route `/live`, `livekit_client`): go live to your connections, or watch a live; viewers renew access every 10 minutes; only the host sees the viewer count.
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
# leave out ONEDAY_DEV_LOCATION to use the device's location

# end-to-end smoke test with the app's real client (email + phone sign-up, face check, location, nearby, refresh)
ONEDAY_LIVE_API=http://localhost:8080 ONEDAY_LIVE_LOG=/path/to/backend.log flutter test test/live
```

Calls need a TURN server for strict networks (`ONEDAY_TURN_URLS` on the backend) and Circle Live needs a LiveKit server (`ONEDAY_LIVE_URL`); neither runs in demo mode. The new native packages (`camera`, `geolocator`, `flutter_webrtc`, `livekit_client`, `razorpay_flutter`, `libsignal_protocol_dart`) were added without running `flutter pub get`, so the first `pub get` may need a version bump.

With no `ONEDAY_API_URL` the app runs on fake data: phone code `123456`, any email with a 12+ character password. Add `--dart-define=ONEDAY_DEMO_SIGNED_IN=true` to skip sign-in for demos and design reviews. `ONEDAY_DEV_LOCATION` pins the area that "Share my area" sends, instead of asking the device. The web build can call a backend that lists its origin in `ONEDAY_CORS_ORIGINS` (the `dev` profile allows `http://localhost:*`).

### When the backend contract changes

Copy the backend's `docs/api/openapi.json` to `contract/openapi.json` and run `flutter test test/core/contract_test.dart`. It names every endpoint, request field and response field the app relies on that has gone missing.
