# 0005 — One mobile shell; phone layouts never change the desktop

**Status:** accepted, in force.

## Context

The desktop shell is a fixed sidebar beside the content, built for windows
of 1024 px and wider. A phone needs a different frame, but the app is one
Flutter code base and the desktop layouts must not regress when a phone
layout is added.

## Decision

- On Android and iOS the app always uses `MobileShell`
  (`apps/gui/lib/app/shell.dart`) — on phones, tablets and in landscape
  alike: a thin header (wallet name opens the picker, the sync pill syncs)
  and a bottom carousel (`apps/gui/lib/shared/widgets/carousel_nav.dart`).
  No sidebar or rail on mobile. The carousel items are listed by
  `mobileNavItems` in `shell.dart`.
- The system back button goes through one handler
  (`apps/gui/lib/app/back_handler.dart` and the shell's `PopScope`): a wizard
  step goes back, a sub-page returns to its parent, any section returns to
  the Dashboard, the Dashboard exits.
- Every phone-specific layout is gated on `AppLayout.isPhone(context)`
  (`apps/gui/lib/theme/app_layout.dart`), which is false on every desktop
  window by construction. Desktop widget trees stay as they are.
- A phone changes geometry and feel (filled controls, sheets instead of
  dialogs, stacked cards), never the icon set or the palette: those are the
  desktop's, and [`design.md`](../../design.md) holds both.

## Consequences

- A new screen needs a phone layout check, and its phone branch belongs
  behind `isPhone`.
- Tablets get the phone shell with wider content, not the desktop sidebar.
