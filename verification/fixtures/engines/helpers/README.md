# Engine-output fixture corpus — regeneration & provenance

This corpus pins *LintCrux's parsing of engine output*. Each case turns a canned engine invocation + output into the
golden unified SARIF the parser must emit.

## Layout

```
test/fixtures/engines/<engine>/
├── generated/<case>/
│   ├── cmdline.txt          # the exact engine invocation (documentation)
│   ├── output.txt           # captured raw engine output (parser input)
│   └── expected.sarif.json  # golden unified SARIF (parser output)
└── captured/<case>/         # real output rebuilt from public OSS RTL
    ├── output.txt
    ├── expected.sarif.json
    └── PROVENANCE.md         # source project, SHA, license, anchor
```

The same tree is mirrored under `verification/fixtures/engines/` for
release sign-off; the generator writes both in one pass so they cannot
drift.

## Regenerate

```bash
dart run tool/generate_engine_corpus.dart
```

This declares the case table in Dart, runs the **real** parser on every
case's `output.txt`, and rewrites `cmdline.txt`, `output.txt`, and
`expected.sarif.json` into both the `test/` and `verification/` trees. The
golden test (`test/services/engines/engine_golden_test.dart`) re-derives the
SARIF and compares; `REGENERATE=1 flutter test …/engine_golden_test.dart`
refreshes just the goldens after an intentional parser change.

## Static guardrails (test/static/)

- `engine_fixture_layout_test.dart` — no loose files outside
  `generated/<case>/` or `captured/<case>/`.
- `all_engines_have_fixtures_test.dart` — every registered engine has ≥1
  generated case.
- `engine_fixture_companion_test.dart` — every `output.txt` has its golden
  + `cmdline.txt` (generated) or `PROVENANCE.md` (captured).
- `captured_fixture_licenses_test.dart` — captured `PROVENANCE.md` licenses
  are on the permissive allow-list (MIT/BSD/Apache-2.0/ISC/CC0/public-domain).

## Captured-fixture provenance

A captured case rebuilds real output from a public OSS RTL project. Its
`PROVENANCE.md` must record the source project + commit SHA, the engine
version + capture command, a hand-verified anchor violation, and the SPDX
license (which must be on the allow-list — GPL/AGPL/proprietary are blocked).
