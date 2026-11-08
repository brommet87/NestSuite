# Design Principles

1. **Feels like the Mac.** Native controls, native behaviors, Human Interface Guidelines first. When
   in doubt, do what Finder or System Settings do. No custom chrome where a system component exists.
2. **Calm confidence.** Virtualization is technical; the app isn’t. Show what matters (is it running,
   what does it use), hide the rest behind “Advanced”. Defaults are chosen for the user’s Mac, so
   most people never need to change them.
3. **Never a dead end.** Every empty, error or blocked state explains *why* and offers *what next*.
   Damaged VMs are shown, not hidden. Disabled controls explain themselves in a tooltip.
4. **Safe and reversible.** Destructive actions go to the Trash or ask for confirmation. Anything
   crossing the guest–host boundary (folders, clipboard) is visible and can be switched off.
5. **Everyone can use it.** Full keyboard access, VoiceOver, Dynamic Type where macOS supports it,
   Increase Contrast, Reduce Motion. Color is never the only signal.
