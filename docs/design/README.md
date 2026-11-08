# NestSuite Design System

How NestSuite looks, sounds and behaves. Everyone changing UI reads this first.

| Document | What it covers |
|---|---|
| [PRINCIPLES.md](PRINCIPLES.md) | The five principles every design decision is checked against |
| [TOKENS.md](TOKENS.md) | Color, spacing, radius, size, motion — the only allowed raw values |
| [COMPONENTS.md](COMPONENTS.md) | Reusable components and when to use them |
| [VOICE-AND-TONE.md](VOICE-AND-TONE.md) | How we write UI text in English and German |
| [ACCESSIBILITY.md](ACCESSIBILITY.md) | Our accessibility commitments and the review checklist |
| [Brand assets](../../Design/Brand) | Logo, app icon |

## Process

1. **Problem first.** Every UI change starts from a user problem in an issue, not from a solution.
2. **Sketch → review → build.** Non-trivial UI gets a sketch or screenshot mock in the issue for
   feedback before implementation.
3. **Build with tokens and components.** New patterns are added to `NestDesign` and documented here.
4. **Review checklist** (in every UI pull request): light + dark screenshots, VoiceOver pass,
   keyboard-only pass, German strings checked for length, empty/error/loading states covered.
