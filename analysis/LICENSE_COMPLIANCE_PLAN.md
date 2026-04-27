# License Compliance Plan

## Refined Goal

The original ask was:

> produce a CycloneDX output from Gradle; run checks on this output vs an allowlist of licenses; decide which licenses to accept

That is directionally right, but too narrow if the real goal is a durable workspace-wide policy. A better target is:

> Build a cross-language dependency license compliance system with CycloneDX as the primary SBOM format, repo-local SBOM generation contracts, and a shared workspace policy evaluator that classifies licenses as allowed, denied, review-required, or unknown.

This refined version is better because it:

- avoids locking the design to Gradle even though Gradle is the first implementation
- separates SBOM generation from policy evaluation
- leaves room for npm, pnpm, Go, Rust, Python, and container inputs later
- keeps license policy in one place instead of scattering it across repos

## Recommendation

Use `CycloneDX` as the primary SBOM format.

Do not make Trivy the core license gate. Trivy can be a useful supplemental scanner, especially for images, but the main workflow should be:

1. each repo generates a CycloneDX SBOM
2. the workspace evaluates the SBOM against a shared policy
3. the evaluator emits concise violations and exits non-zero when policy is breached

## Current Workspace Implementation

The workspace now has a bootstrap implementation of this plan:

- root policy file: `policy/license-policy.yml`
- workspace command: `just license-audit-workspace`
- Gradle SBOM bootstrap: `scripts/cyclonedx-init.gradle`
- evaluator implementation: Kotlin CLI in `tools/modules/license-audit/app`

This is intentionally a bootstrap path, not the final architecture. The final shape should still move toward a real `sollecitom.sbom-conventions` plugin in `gradle-plugins`.

Current behavior:

- Gradle repos expose `just generate-sbom`
- Gradle repos also expose `just license-audit`
- the Kotlin auditor runs each repo command, merges per-project direct SBOMs, writes `build/reports/sbom/cyclonedx.json`, and evaluates the merged result
- denied licenses fail the run
- review and unknown licenses are reported but do not fail phase 1
- repo-local waivers live in `license-waivers.yml` and cannot silently override global denied licenses
- the audit is currently an explicit step via `just license-audit-workspace` or repo-local `just license-audit`
- once the audit runtime is consistently fast enough, it should be added to `refresh-workspace`, `refresh-local-workspace`, `build-workspace`, `rebuild-workspace`, and `refresh-rebuild-workspace`

Current known limitation:

- some third-party dependencies still surface as `UNKNOWN` because their child POM is not cached locally and their license metadata cannot yet be recovered without an additional fallback strategy
- inherited parent-POM licenses are handled when the necessary POMs are available in the local Gradle caches

Current performance behavior:

- repo audits cache by dependency-input fingerprint, so unchanged repos skip SBOM generation entirely
- `FORCE_LICENSE_AUDIT=1` or CLI `--force` bypasses the cache
- Gradle SBOM tasks now declare dependency-manifest inputs, so within a repo only affected projects need to regenerate direct SBOM files when dependency declarations change
- composed workspace flows should not call `license-audit` by default until these optimizations bring the end-to-end runtime low enough for routine `refresh-workspace` use

## Scope

Initial scope:

- JVM and Gradle-first implementation
- dependency license compliance only
- transitive dependencies included
- direct and transitive third-party artifacts only
- internal `sollecitom` artifacts excluded from enforcement by default

Out of scope for phase 1:

- notice file generation
- copyright attribution bundles
- source-file header scanning
- container base image licenses
- file-level license detection for vendored code

## Architecture

### Core Design

The system should have two layers:

1. **SBOM producer**
   Each repo exposes one standard command, for example `just generate-sbom`, and writes a CycloneDX JSON file to a predictable location.

2. **Policy evaluator**
   A shared workspace tool reads one or more SBOMs, normalizes license identifiers, applies policy, prints a summary, and fails if necessary.

This keeps ecosystem-specific logic at the edges and license policy in one place.

### Proposed Contract

For every repo that participates:

- command: `just generate-sbom`
- output path: `build/reports/sbom/cyclonedx.json`

For the workspace:

- command: `just license-audit-workspace`
- behavior:
  - run each repo's `generate-sbom`
  - collect all SBOM files
  - evaluate them with the shared policy
  - print a short, repo-grouped summary
  - exit non-zero on denied licenses

## Gradle: Producing CycloneDX

### Plugin Choice

Use the Gradle CycloneDX plugin:

- plugin id: `org.cyclonedx.bom`

This should be wrapped in a workspace-owned convention plugin rather than copy-pasted in each repo.

### Proposed Convention Plugin

Add a new plugin in `gradle-plugins`, for example:

- `sollecitom.sbom-conventions`

Responsibilities:

- apply `org.cyclonedx.bom`
- configure consistent output location and format
- expose a predictable task name
- prefer JSON output
- include resolved runtime and compile classpaths
- support multi-module projects in a consistent way

### Expected Gradle Task Shape

At the repo level, the wrapper command should effectively run something equivalent to:

```bash
./gradlew cyclonedxBom
```

The convention should standardize:

- output format: JSON
- output file: `build/reports/sbom/cyclonedx.json`
- schema version: pin explicitly rather than floating
- project type: library or application as appropriate

### Example Gradle Shape

Illustrative Kotlin DSL shape only:

```kotlin
plugins {
    id("org.cyclonedx.bom")
}

cyclonedxBom {
    outputName.set("cyclonedx")
    outputFormat.set("json")
    includeConfigs.set(listOf("runtimeClasspath", "compileClasspath"))
    skipConfigs.set(listOf("testRuntimeClasspath", "testCompileClasspath"))
    projectType.set("library")
}
```

The final exact DSL should be taken from the plugin version chosen at implementation time.

### Multi-Module Gradle Repos

For multi-module repos, prefer one aggregate SBOM per repo in phase 1.

Why:

- policy should be repo-facing, not subproject-facing
- workspace reporting stays shorter
- avoids duplicate transitive dependencies across many submodules

Keep per-subproject SBOM generation as a later option if needed for diagnostics.

## Policy Evaluation

### Why a Custom Evaluator

Do not encode policy directly in Gradle plugin configuration.

Build a shared evaluator because it needs to handle:

- license normalization
- dual-licensed packages
- missing or malformed license metadata
- waivers and temporary exceptions
- repo-level and dependency-level overrides
- future non-Gradle repos

### Proposed Inputs

The evaluator should consume:

- one or more CycloneDX JSON files
- one workspace policy file
- optional per-repo waiver file

### Proposed Files

- workspace policy: `policy/license-policy.yml` at the workspace root, not in `gradle-plugins`
- optional repo waiver file: `<repo>/license-waivers.yml`

The workspace root is the right home for policy because:

- the policy applies across build tools, not just Gradle
- non-Gradle repos should use the same rules
- `gradle-plugins` should own Gradle mechanics, not the compliance policy itself

### Proposed Evaluator Output

Each finding should be concise and machine-stable:

```text
DENY   swissknife   org.example:bad-lib:1.2.3   GPL-3.0-only
REVIEW tools        com.example:unclear:4.5.6   LicenseRef-Unknown
UNKNOWN examples    org.foo:bar:2.0.0           (missing)
```

Workspace summary:

```text
License policy failed:
- 2 denied licenses
- 3 review-required licenses
- 1 unknown license
```

### Evaluation Rules

For each component in the SBOM:

1. ignore internal components that match configured internal groups such as `sollecitom`
2. extract declared licenses
3. normalize SPDX identifiers and common aliases
4. if no license is present, classify as `unknown`
5. if any declared license is in `deny`, fail
6. if all declared licenses are in `allow`, pass
7. if a declared license is in `review`, mark review-required
8. if the license string is not recognized, classify as `unknown`
9. if the component has a matching waiver, apply the waiver decision instead

### Dual Licensing

Use this rule:

- if a dependency declares multiple licenses and at least one is allowed, treat it as `pass`
- if all declared licenses are denied, treat it as `deny`
- if licenses are mixed between `allow` and `review`, treat it as `review`

This is pragmatic for build gating, while still surfacing ambiguous cases.

## License Policy

This is an engineering default, not legal advice. The exact final allowlist should be confirmed with your own legal/compliance bar if this workspace becomes externally distributed.

### Allow

Accept by default:

- `Apache-2.0`
- `MIT`
- `BSD-2-Clause`
- `BSD-3-Clause`
- `ISC`
- `0BSD`
- `Python-2.0`
- `Zlib`
- `Unlicense`
- `CC0-1.0`
- `BSL-1.0`

Reasoning:

- these are broadly accepted permissive licenses
- they are common in JVM and general software dependency graphs
- they do not usually create reciprocal distribution obligations that surprise application/library consumers

### Review

Require explicit review rather than hard-fail:

- `MPL-2.0`
- `LGPL-2.1-only`
- `LGPL-2.1-or-later`
- `LGPL-3.0-only`
- `LGPL-3.0-or-later`
- `CDDL-1.0`
- `CDDL-1.1`
- `EPL-1.0`
- `EPL-2.0`
- `Unicode-DFS-2016`
- custom `LicenseRef-*`

Reasoning:

- these can be acceptable, but they are not as low-friction as the permissive set
- some have reciprocal or distribution-specific obligations
- some appear due to metadata quirks and need human review

### Deny

Deny by default:

- `GPL-2.0-only`
- `GPL-2.0-or-later`
- `GPL-3.0-only`
- `GPL-3.0-or-later`
- `AGPL-3.0-only`
- `AGPL-3.0-or-later`
- `LGPLLR`
- `SSPL-1.0`
- `Commons-Clause`
- any explicitly proprietary commercial license unless waived

Reasoning:

- strong copyleft and network copyleft licenses are the most likely to be incompatible with normal dependency consumption goals
- SSPL and Commons Clause are intentionally restricted and should not silently enter the tree
- proprietary licenses should require an explicit human decision

### Unknown

Treat missing or unparsable licenses as `review-required` in reporting, but keep them as a separate `unknown` class internally.

Policy for phase 1:

- do not fail the build on `unknown`
- do fail on `deny`
- do surface `review` and `unknown` prominently

Policy for phase 2:

- optionally fail on `unknown` unless covered by a waiver

## Normalization Rules

The evaluator should normalize common variants, for example:

- `Apache 2.0` -> `Apache-2.0`
- `Apache License, Version 2.0` -> `Apache-2.0`
- `BSD License` -> `BSD-3-Clause` only if there is a safe explicit mapping, otherwise `unknown`
- `The MIT License` -> `MIT`

Prefer a small explicit alias map over clever heuristics. Wrong normalization is worse than `unknown`.

## Waivers

Waivers are necessary. Without them, the first few odd packages will push people to disable the system.

Each waiver should require:

- repo
- package coordinate or purl
- license
- reason
- owner
- created date
- expiry date

Example shape:

```yaml
waivers:
  - package: "pkg:maven/org.example/weird-lib@1.2.3"
    license: "LicenseRef-Vendor-Eula"
    decision: "allow"
    reason: "Used only in local tooling"
    owner: "msollecito"
    expires: "2026-12-31"
```

## Proposed Implementation Plan

### Phase 1: Gradle-Only Foundation

1. add `sollecitom.sbom-conventions` to `gradle-plugins`
2. configure CycloneDX JSON generation consistently
3. add `just generate-sbom` to Gradle repos
4. create `policy/license-policy.yml`
5. build a workspace evaluator script, likely Kotlin or shell-plus-`jq`
6. add `just license-audit-workspace`
7. report `allow`, `deny`, `review`, `unknown`
8. fail only on `deny`

Bootstrap note:

- the very first working slice can use a shared Gradle init script to apply and configure CycloneDX without waiting for every repo to adopt a published `gradle-plugins` release
- once the convention plugin is published and the repos are updated, the init script can be retired

### Phase 2: Hardening

1. add alias normalization table
2. add waiver support
3. add repo-specific policy overrides only if truly needed
4. improve summaries and machine-readable output
5. add CI-style exit codes even if used locally first

### Phase 3: Cross-Language Expansion

For each non-Gradle ecosystem, keep the same contract:

- produce `build/reports/sbom/cyclonedx.json`
- reuse the same workspace evaluator

Candidate adapters:

- npm / pnpm / yarn: CycloneDX Node tooling
- Python: CycloneDX Python tooling
- Go: CycloneDX Go tooling
- Rust: `cargo-cyclonedx`
- containers: optional Trivy or image SBOM ingestion as supplemental input

## Why Not ORT First

ORT is stronger as a full compliance platform, but heavier than needed for the current workspace.

Heavier means:

- more configuration
- more moving parts
- longer runtime
- more maintenance cost
- more process overhead than a simple build gate

Stronger means:

- more mature policy evaluation
- richer compliance workflows
- better reporting for legal/audit use cases
- better long-term governance support

If the requirement evolves from "block bad licenses in dependencies" to "run a real multi-repo compliance program", ORT becomes a more compelling next step.

## Recommended Final Position

For this workspace, the best plan is:

1. standardize on `CycloneDX`
2. generate SBOMs in each Gradle repo via a convention plugin
3. evaluate them in one shared workspace policy step
4. allow common permissive licenses
5. deny strong copyleft and restricted licenses
6. review weak copyleft and ambiguous licenses
7. add waivers early

This gets you a practical and extensible system without overbuilding it.
