# Engineering principles

Apply to everything developed in any project: code, configuration, CLI output, help, docs and comments.

- **Name things for what they represent, not their current value or value set.** "3P", not a vendor; "the
  calibration model", not today's model; "the retry interval", not its default; no enumerating today's members
  of a set, no hard-coded counts of things that grow. Exempt: identifiers, text about one specific tool's
  behaviour, dated measurements (they record what was true then).
- **Sets, not singletons.** Unless the domain makes something one forever (a default), model it as a set of one
  today and many tomorrow: lists in configuration, plural names, code that iterates.
- **No magic values in configuration.** On/off is a union: `name = false`, or `[name] enabled = true` with its
  settings. Durations carry units (`"30m"`, `"6h"`, `"1d"`). No 0, -1 or "" carrying meaning.
- **Standing concerns on every change:** user experience, reliability, performance, maintainability, security,
  compliance. Name the trade-off when one costs another.
- **CLIs:** a human view on a terminal, machine-readable (tab-separated) when piped, `--json` for programs;
  errors say what to do next.
