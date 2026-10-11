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
when the copy differs from `../dsl/spec/keywords.yaml`.

## What the calendar does with keywords

- `appointment <date>`: shown on that day.
- `recurring <weekday> [until <date|month>]`: shown on every matching
  weekday up to and including `until`. A month means its last day.
- Any other valid primary keyword: the item is valid, but appears on no day.
- Description lines are shown muted under the title.

## Problems

Settings lists two kinds of problem files, each with the spec's code, line
and offending token:
- **Invalid files**: files with errors. They are not shown in the calendar.
- **Warnings**: valid items with warnings, for example unknown keywords.
