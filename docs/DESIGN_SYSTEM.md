# Design system

Dark-first Material 3 with a custom palette. Every token lives in `lib/core/theme/`.

## Colour

| Token | Hex | Use |
| --- | --- | --- |
| `ink` | #050914 | Deepest background, text on bright buttons |
| `background` | #0A1022 | Scaffold |
| `surface` | #111A35 | Cards, sheets, dialogs |
| `surfaceHigh` | #18234A | Tracks, inputs, snackbars |
| `primary` | #4C8DFF | Primary actions, focus, links |
| `violet` | #8B5CF6 | Gradient partner, LED accents |
| `cyan` | #22D3EE | Secondary metric colour |
| `success` / `warning` / `danger` / `info` | #34D399 / #FBBF24 / #F87171 / #60A5FA | Status |
| `textPrimary` / `textSecondary` / `textMuted` | #EEF3FF / #A7B3D6 / #6E7BA3 | Text hierarchy |

Status is never colour-only: every state pairs a colour with a label and a pulsing dot.

## Typography

- Latin: **Inter** (variable font, `wght` axis set through `FontVariation`).
- Arabic: **Cairo** (variable), declared as `fontFamilyFallback`, so both languages share one scale.
- Scale: display 36, headline 30/26/22, title 20/17/15, body 16/15/13, label 15/13/11.
- Console uses the platform monospace at 12.5 sp.
- Text scale is clamped to 0.9 through 1.5 so layouts stay intact at large accessibility sizes.

## Spacing, radius, elevation

- Spacing: 4, 8, 12, 16, 24, 32.
- Radius: 12 (small controls), 16 (buttons, inputs), 22 (cards), 28 (sheets), 999 (pills).
- Elevation is expressed with soft coloured shadows and a hairline outline (`AppColors.outline`), not Material elevation.

## Motion

| Token | Value | Use |
| --- | --- | --- |
| `fast` | 160 ms | Press feedback |
| `base` | 260 ms | Selection, chips, switches |
| `slow` | 480 ms | Progress bars, hero entrances |
| `page` | 340 ms | Route transitions (fade and rise 3.5%) |
| `enter` / `exit` | easeOutCubic / easeInCubic | Standard direction |
| `emphasized` | easeOutBack | Dialogs, empty-state icons |

Reusable motion: `PressScale` (0.97 on press), `FadeSlideIn` (staggered entrance), `Shimmer` (loading), `PulseDot` (live state), animated progress, and tab cross-fades (`fadeThroughPage`).

## Components

`GlassCard`, `PressScale`, `PrimaryButton` (gradient), `SecondaryButton`, `SectionTitle`, `ServerStateChip`, `PulseDot`, `EmptyState`, `ErrorState`, `AsyncBody`, `SkeletonList`, `Shimmer`, `FadeSlideIn`, `MetricCard`, `InfoLine`, `OptionChips`, `ValueStepper`, `SettingSwitch`, `AppSearchField`, `AvatarImage`, `VoxelLogo`, `FloatingNav`, `AppPage` (large collapsing app bar, responsive inset, shell clearance), `confirmAction` (dialog with scale and fade), `showAppSnack`.

## Layout and responsiveness

- Breakpoints: compact below 600 dp, medium from 840 dp, expanded from 1200 dp.
- Content is centred at 760 dp maximum width. Horizontal inset grows on wide screens.
- Metric grids switch from 2 to 4 columns at 840 dp.
- Bottom navigation has 112 dp of clearance on scrolling pages. Safe areas are respected on every screen.
- Portrait and landscape are both supported; no screen assumes a fixed orientation.

## Right-to-left

- Layout uses `Start`/`End` semantics (`AlignmentDirectional`, `EdgeInsetsDirectional`) and Material's built-in `Directionality`.
- Arabic is the default when the device language is Arabic, and is selectable at any time.
- Numbers and technical identifiers (IP addresses, file names, commands) stay left-to-right inside `SelectableText`.

## Accessibility

- Touch targets are at least 48 dp.
- Icon-only buttons have tooltips.
- Navigation items expose `Semantics(button, selected)`.
- Status changes are announced through text, not only colour or animation.
