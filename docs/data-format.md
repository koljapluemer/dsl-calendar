# Calendar data format

Items are written in the item language from the sibling `dsl` repo. Its
`spec/language.md` defines the syntax, and its `spec/keywords.yaml` lists the
keywords. This file only covers what is specific to the calendar.

## Files

Every `*.txt` file directly inside the data folder is one item. Subdirectories
and other extensions are ignored. The app only reads the files; it never
writes them.

```
HCI lecture 4pm-7pm
(bring laptop)
recurring mo until 27-03
```

## Schema

The calendar bundles a copy of `keywords.yaml` at `assets/dsl/keywords.yaml`
and parses files using that copy, so keyword names, roles and argument types
are not hardcoded. To pick up spec changes, run `just sync-spec`. A test fails
when the copy differs from `../dsl/spec/keywords.yaml`, and the parser runs the
dsl repo's conformance cases (`spec/examples`).

## What the calendar does with keywords

- `appointment <date>`: shown on that day.
- `recurring <weekday> [until <date|month>]`: shown on every matching
  weekday up to and including `until`. A month means its last day.
- No primary keyword the calendar knows (a plain note, e.g. from graphirst
  sharing the folder, or a primary added to the schema later): the item is
  valid, but appears on no day and isn't kept in memory.
- The first body line is the item's heading; the other body lines are shown
  muted under it. Relationships, `media` and the extra block are ignored.

## Problems

Settings lists two kinds of problem files, each with the spec's code, line
and offending token:
- **Invalid files**: files with errors. They are not shown in the calendar.
- **Warnings**: valid items with warnings, for example unknown keywords.
