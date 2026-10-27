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

# Writing proposals and docs

A doc is only as good as the opinions it changes, and it has to be read first. Readability is a requirement.

- **Lead with what and why.** The first page stands alone: the problem, the idea, why it matters now, and what
  you ask of the reader, explicitly. Keep the how short; mechanics and fine print go in an appendix.
- **Make it scannable.** A short summary callout at the top, headings that say something, tables for
  comparisons, bullets with a one-line point, short paragraphs with space around tables and callouts.
- **Cut hard.** Keep every load-bearing fact, number and link; drop restatement and process narration.
- **Concrete over abstract.** A worked example or a number beats a paragraph of explanation.
- **Refer back, never forward.** Point to what the reader has already seen. If a point needs something that comes
  later, state it in place instead of saying "below".
