# Python Runner re_editor Patch Notes

Updated: 2026-06-28

## Current Decision

Python Runner keeps `third_party/re_editor` as a local editor dependency. App
syntax highlighting uses `re_highlight`; the app-level `highlight` dependency is
not needed and should not be re-added unless a direct call site is introduced.

## Why This Copy Is Vendored

- The upstream `re_editor` release used by the app needs a small Flutter input
  compatibility patch.
- The local copy guards asynchronous syntax highlighting so stale highlight
  results cannot overwrite newer text.

## Local Changes

- `lib/src/_code_input.dart`
  - `onFocusReceived()` returns `false` to match the current Flutter input
    callback contract.
- `lib/src/_code_highlight.dart`
  - `_highlightRevision` drops stale asynchronous highlight results.
  - Repeated highlight work is skipped when code lines have not changed.

## Dependency Rule

The app should depend on:

- `re_editor`
- `re_highlight`

The app should not depend directly on:

- `highlight`

If direct `highlight` usage becomes necessary, document the call site and why
`re_highlight` cannot cover it before adding the dependency back.

## Upgrade Checklist

- `flutter analyze`
- `flutter test`
- Script editor syntax highlighting renders correctly.
- Project file editor syntax highlighting renders correctly.
- Rapid typing does not show stale highlight results.
- Editor focus, typing, selection, copy, and paste still work.
