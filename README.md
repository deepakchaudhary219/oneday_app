# OneDay app (Flutter)

The OneDay mobile app: a camera-first, location-aware social and dating app. The backend lives in `deepakchaudhary219/oneday`. Its `docs/api/openapi.json` is the API contract and `docs/08-flutter-integration.md` is the integration guide.

## Design

[`docs/ui-ux-principles.md`](docs/ui-ux-principles.md) covers what we borrow from Snapchat, Instagram, Tinder and TikTok, what we refuse (infinite feeds, streaks, public counts), and the motion, visual, accessibility and code rules.

## Structure

```
lib/
  design_system/   tokens (colour, spacing, radii, motion, type), theme, components; screens import design_system.dart only
  core/            domain models, repository interfaces, fake data, Riverpod providers
  features/        shell (camera-first pager), camera, nearby, stories, signals, chats, map, profile, gallery
```

- **Repositories:** screens depend on the repository interfaces in `core/repositories.dart`. `FakeData` backs them until the generated API client is wired, and only `core/providers.dart` changes when it is.
- **Gallery:** every component is on the gallery screen (Me → Design system gallery).

## Run and test

```bash
flutter pub get
flutter run                 # a device or simulator
flutter test                # widget tests, including small-phone and 200%-text layout
flutter analyze
```
