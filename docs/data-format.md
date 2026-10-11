# Calendar data format

The selected data directory is a flat collection of plain-text files. Every
`*.txt` file directly inside it is one item. Subdirectories and other
extensions are ignored. The app only reads these files; it never writes them.

```
HCI lecture 4pm-7pm
(bring laptop)
recurring mo until 27-03
iterable d 4 0.4
```

## Lines

Lines are trimmed. Blank lines are ignored.

1. **Title**: the first line. It is shown verbatim, and any times written in
   it are just text.
2. **Notes**: optional free-text lines after the title. They are shown muted
   under the title.
3. **Keyword lines**: a line whose first word is a reserved keyword. Once the
   first keyword line appears, every later line must also be a keyword line.

Reserved keywords: `appointment recurring goal weekly prio reconsider raincheck
finishable next iterable` (see `docs/new_data_format/ideas/language_spec.md`).

## Supported keywords

Each item needs exactly one of these:

- `appointment <yy-mm-dd>`: the item shows on that single day.
- `recurring <weekday> [until <date>]`: the item shows on every matching
  weekday, with no start bound, up to and including `until`.
  - Weekdays: `mo tu we th fr sa su`.

The other reserved keywords are accepted and kept, but have no effect yet.

## Dates

- `yy-mm-dd` means 20yy-mm-dd, and must be a real calendar date.
- In `until` only, `yy-mm` is also accepted. It means the last day of that
  month, so `until 27-03` runs through 31 Mar 2027.

## Invalid files

A file is invalid when any of these is true:
- it is empty;
- it has no `appointment`/`recurring` line, or more than one;
- it has a malformed date or weekday;
- it has a text line after its keyword lines.

An invalid file never stops the rest of the folder from loading. Invalid files
are listed, with the reason, under "Problems" in Settings.
