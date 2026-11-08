# Components

All components live in [`NestDesign`](../../Packages/NestKit/Sources/NestDesign) and have SwiftUI previews.

## Empty state
`EmptyStateView(title:message:illustration:actions:)`

Use for every screen that has nothing to show yet, cannot load, or is blocked.
- **Title:** what the situation is (“This Virtual Machine Can’t Be Opened”). Title Case in English.
- **Message:** why, and what the user can do. One or two sentences.
- **Actions:** at most one prominent button, plus secondary actions. Destructive actions use `role: .destructive`.

## Status badge
`StatusBadge(state:)`

Shows a VM lifecycle state with symbol + color + text. Use it everywhere a VM state is shown, so the
same state always looks the same. VoiceOver reads the text.

## Brand mark
`BrandMark(accessibilityLabel:)`

The logo mark drawn in code. Decorative (hidden from VoiceOver) unless a label is passed. Use in the
welcome screen and About; not as a generic icon.

## Guest icon (app target)
`GuestIcon(guest:)` — a rounded tile with an SF Symbol per guest OS. Sidebar and headers.

## Patterns
- **Forms** use `Form { … }.formStyle(.grouped)` with `LabeledContent`, like System Settings.
- **Destructive actions** move items to the Trash; permanent deletion always asks for confirmation.
- **Disabled controls** carry a `.help(…)` tooltip that explains why and when they become available.
