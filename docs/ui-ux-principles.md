# OneDay UI/UX Principles

This is how the app should look, feel and behave. It borrows proven interaction mechanics from Snapchat, Instagram, Tinder and TikTok. It deliberately leaves out the mechanics that drive compulsive use, which the backend docs (`05-engagement-psychology.md`) commit us to avoiding (and which India's CCPA 2023 dark-pattern guidelines and the EU DSA Art. 25 prohibit).

## 1. What we borrow, and why it works

| Source | Mechanic | Psychology | How OneDay uses it |
|---|---|---|---|
| Snapchat | **Camera-first launch**, horizontal swipe between surfaces | Zero-step creation lowers the cost of contribution; spatial memory ("chat is left") beats tab hunting | The app opens on the camera. Swipe left: Chats. Swipe right: Nearby. The bottom bar mirrors the pager. |
| Instagram | **Story rings** and the **story viewer** (tap left/right, hold to pause, swipe down to close) | Rings are a pre-attentive cue ("something new"). Hold-to-pause gives control. | The ring is shown only for *live* stories (24 h). No "seen" pressure is exposed. |
| Tinder | **Card stack with swipe physics** | Direct manipulation: the card follows the finger, so decisions feel light and reversible | Used for the **Signals digest** (people who reached out), *not* for judging strangers. Right reveals, left lets it pass quietly. |
| TikTok | **Full-screen vertical pager**, instant media | Immersion and zero-chrome focus | Nearby moments in a full-screen pager. **Bounded**: it ends with a closure card ("That's everyone nearby for now"). |

## 2. What we refuse (and the replacement)

| Pattern elsewhere | Why it's refused | OneDay's replacement |
|---|---|---|
| Infinite scroll | Removes stopping cues; drives compulsion | Pages end with a **closure state** and a suggestion to do something real |
| Streaks with loss | Loss aversion turned into a chore | **Connection Warmth**: a glow that grows with mutual exchange and never "breaks" |
| Public likes, followers, view counts | Social comparison, anxiety | No public metrics. Creators see their own counts privately. |
| Read receipts and "typing…" bait | Anxiety and over-checking | None |
| Bait notifications | Interrupts for the app's sake, not the user's | Pushes only for things the person is waiting for |
| Random rewards on pull-to-refresh | Slot-machine reinforcement | Refresh only refreshes. Nothing is held back to create suspense. |

## 3. Feel: motion and responsiveness

- **60/120 fps or nothing.**
  - Use `const` widgets, `RepaintBoundary` around animated layers, no layout work in animation ticks, and slivers for lists.
  - Images are decoded at display size (`cacheWidth`).
- **Physics, not timelines.**
  - Drags follow the finger 1:1 and release with spring physics (`SpringDescription`).
  - Durations come from tokens: `instant 90 ms`, `quick 160 ms`, `standard 240 ms`, `emphasized 360 ms`.
  - Curves are `emphasizedDecelerate` for entering and `emphasizedAccelerate` for leaving.
- **Every touch answers within 100 ms.** Pressables scale to 0.96 with a light haptic. Destructive actions use a medium haptic.
- **Optimistic UI.** Send, react and accept show immediately and reconcile with the server. Failures surface as a quiet inline retry, never a lost action.
- **Reduced motion.** When the OS asks (`MediaQuery.disableAnimations`), springs become fades and parallax switches off.

## 4. Visual language

- **Dark-first** (camera, stories and night use dominate), with a full light theme.
- The palette:
  - one vibrant **brand gradient** ("dusk": coral → magenta → violet) for primary actions and live states;
  - neutrals for everything else;
  - semantic colours for safety (calm teal), warning and error.
- **8-point grid** with 4-point half-steps. Radii are 8/14/22/32, and continuous corners on cards.
- **Type:** Plus Jakarta Sans (bundled, SIL OFL), one family with five roles (display, title, body, label, caption). Display sizes use tight negative tracking for a confident, editorial feel; timers use tabular figures.
- **Depth through blur and scrims,** not heavy shadows: frosted chrome over media, gradient scrims for legibility on any photo.

- **Content-first stand-ins:** the app never shows empty gradients. Until real photos load (and in demo mode), people are drawn as illustrated portraits and moments as painted places chosen from the activity ("sunrise trek" → mountains, "chai" → café). Both are deterministic per seed, so one person looks the same everywhere: avatar, story, Nearby card.

## 5. Surface by surface: the market standard, and where we go further

| Surface | The pattern people know | What OneDay adds |
| --- | --- | --- |
| Camera | Snapchat: tools on a right rail, lenses beside the shutter, Memories on the left, profile and search on top | A Friends / Nearby switch that says who sees it; Nearby captures are live and unfiltered, so lenses switch off |
| Nearby | Tinder: a card deck with drag, tilt and stamps, plus Pass, hero and secondary buttons | Cards are moments, not profiles; chips show what you share (language, roots, a friend who vouches); the hero action spends one of a few daily Signals; the deck ends |
| Chats | Instagram and Snapchat: stories row, search, rows with a quick-reply camera | Warmth glows instead of streaks, a quiet dot instead of badge counts, and Signals as a stacked-faces card |
| Me | Instagram: header, bio, Edit and Share, highlights, grid tabs | No follower or like counts; the grid is your private Memory Trail; settings sit behind the menu |
| Map | Snap Map: dark city, heat, story bubbles, a carousel | Areas, never pins: no person is ever placed on the map; lenses (Roots, language, activity) filter what lights up |
| Welcome | Hinge and Tinder: real people up front | Floating moment cards that show the product before any sign-up step |

## 6. Information architecture

```
                 ┌──────── bottom bar mirrors the pager ────────┐
   Chats  ◀──swipe──  Camera (home)  ──swipe──▶  Nearby  ──▶  Map
     │                    │                        │
  threads, calls      capture → share          vertical pager (bounded)
  signals digest      (Friends | Nearby)       story viewer
     │
   Me (profile, Pulse Status, privacy)
```

## 7. Safety in the UI

Safety is a first-class UI surface, never a buried menu:
- block and report sit one long-press away on every person-surface;
- the Empathy Mirror is a calm bottom sheet, not an error;
- Date Mode SOS is always reachable within one tap while a date is on.

## 8. Accessibility

- Tap targets ≥ 48 dp.
- Semantics labels on every icon button.
- Contrast ≥ 4.5:1 for text (checked in tests for the core tokens).
- Supports text scaling to 200% without clipping.
- Captions are always available on video.

## 9. Scalable code structure

- **Feature-first folders** (`lib/features/<feature>/{data,domain,presentation}`) with a shared **design system** (`lib/design_system`) and **core** (`lib/core`: routing, DI, networking).
- **State: Riverpod.** Repositories sit behind interfaces, with fake implementations until the generated API client is wired. Screens never call HTTP directly.
- **Navigation: `go_router`,** with a `StatefulShellRoute` for the main pager so each surface keeps its own state.
- **Components** live in the design system with a gallery screen (`/gallery`) and widget tests. Screens compose components and never restyle them.
