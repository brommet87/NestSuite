# Design Tokens

Defined in [`Tokens.swift`](../../Packages/NestKit/Sources/NestDesign/Tokens.swift). Views use tokens,
never literal values.

## Color

### Brand (sampled from the logo)

| Token | Hex | Use |
|---|---|---|
| `Tokens.Brand.cyan` | `#22C6F5` | Gradient start, highlights |
| `Tokens.Brand.azure` | `#3D8BEF` | Gradient, macOS guest tile |
| `Tokens.Brand.indigo` | `#4338CA` | Gradient, Linux guest tile |
| `Tokens.Brand.violet` | `#8B3FE0` | Gradient end |
| `Tokens.Brand.ink` | `#0A0E1A` | Wordmark on light backgrounds |
| `Tokens.Brand.gradient` | cyan → azure → indigo → violet | Brand mark, illustrations |

Brand colors are for accents and illustrations. **Text and surfaces use semantic system colors**
(`.primary`, `.secondary`, `Color(nsColor: .windowBackgroundColor)` …) so Dark Mode and Increase
Contrast work automatically.

Accent color (asset catalog): `#2F6FE0` light / `#4D9BF5` dark — both meet WCAG AA (≥ 4.5:1) for
text on the standard window backgrounds.

### Status

| State | Token | Symbol |
|---|---|---|
| Running | `Status.running` (green) | `play.circle.fill` |
| Paused | `Status.paused` (orange) | `pause.circle.fill` |
| Suspended | `Status.suspended` (indigo) | `moon.circle.fill` |
| Stopped | `Status.stopped` (secondary) | `stop.circle` |
| Failed | `Status.failed` (red) | `exclamationmark.triangle.fill` |
| Transitioning | `Status.transitioning` (accent, pulsing) | per state |

## Spacing — 4-pt grid

`xxSmall 2 · xSmall 4 · small 8 · medium 12 · large 16 · xLarge 24 · xxLarge 32 · xxxLarge 48`

## Radius

`small 6` (tiles, badges) · `medium 10` (cards) · `large 14` (sheets content) · `xLarge 20` (hero surfaces)

## Size

| Token | Value | Use |
|---|---|---|
| `minimumHitTarget` | 28 pt | Smallest custom control |
| `sidebarIcon` | 28 pt | Guest tiles in the sidebar |
| `heroIllustration` | 96 pt | Empty-state illustration |
| `readableWidth` | 420 pt | Max width of explanatory text |

## Motion

`Tokens.Motion.standard(reduceMotion:)` — a 0.25 s snappy spring, or no animation when Reduce
Motion is on. Status symbols pulse only while a transition is in progress, and not with Reduce Motion.
