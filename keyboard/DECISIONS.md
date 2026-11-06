# NumberKeys decision log

- 31 Oct 2026: GitHub cloud builds + Sideloadly weekly reinstall (no Mac, no paid account).
- 6 Nov 2026: NumberKeys built as two keyboard extensions (EN/AR) in the same repo.
- 6 Nov 2026: v2 added Gboard features, learning predictions, swipe gestures, clipboard history; reduced height.
- 6 Nov 2026: v3 goal set — native-level speed and main-keyboard readiness.
- 6 Nov 2026: v3 audit done (11 causes of slowness, ranked). Plan approved: overlay first, then cheap keystrokes, then text cache, then the rest (background predictions, compact word list, startup, saving, delete/cursor, rendering, clipboard).
- 6 Nov 2026: Hidden speed overlay added (Perf.swift). It is toggled by holding the clipboard button for 1.2 s, not by a switch in the container app, because sharing a setting between app and keyboard needs an App Group, which a free Apple ID may not allow. Off by default.
- 6 Nov 2026: Keys are now redrawn only when something visible changes (mode, shift, theme, return key), not on every keystroke. Text before the cursor is kept in our own copy and re-checked once after typing pauses (0.4 s), so typing no longer reads the text field 3-4 times per key. Hold-delete and cursor-swipe no longer rebuild keys or recompute suggestions on every step.
