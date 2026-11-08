# Accessibility

NestSuite targets **WCAG 2.2 AA** where applicable to native macOS apps and follows Apple’s
accessibility guidelines.

## Commitments
- **VoiceOver:** every control has a meaningful label; decorative images are hidden; headings are marked.
- **Keyboard:** every action is reachable from the menu bar, most with a shortcut; focus order is logical.
- **Color:** never the only signal (status = symbol + color + text); text contrast ≥ 4.5:1.
- **Motion:** animations respect Reduce Motion.
- **Text:** no truncation of essential information in English or German; Increase Contrast supported
  through semantic colors.

## Review checklist (every UI pull request)
- [ ] VoiceOver: navigate the changed screen; every element is announced sensibly
- [ ] Keyboard only: reach and trigger every new action
- [ ] Light, dark and Increase Contrast screenshots attached
- [ ] Reduce Motion: no essential information conveyed only by animation
- [ ] German UI: no truncation or overlap
