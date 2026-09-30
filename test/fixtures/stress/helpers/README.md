# Large-scale stress corpus — regeneration

Backs the stress + perf tests (50K parse/ingest, 100K streaming, index
integrity, perf budgets).

## What is committed vs generated

The 50K / 100K corpora are **not** committed as multi-MB binaries. They are
regenerated deterministically in memory from a fixed seed by
`test/support/stress_corpus.dart` (byte-stable, reproducible, and free of
the git-size and gzip-nondeterminism cost of committing them, which is why
no `.zst` corpus is committed). Only the small artifacts
that *pin* that generation are committed:

```
test/fixtures/stress/
├── violations_50k.expected.meta.json   # distribution counts of the 50K set
└── sarif_malformed/
    ├── truncated.sarif.json            # rejection cases (typed
    ├── bad_token.sarif.json            #  SarifReadException, store intact)
    └── wrong_schema.sarif.json
```

Mirrored under `verification/fixtures/stress/`.

## Regenerate the committed artifacts

```bash
dart run tool/generate_stress_fixtures.dart
```

`index_integrity_test.dart` cross-checks the live generation against
`violations_50k.expected.meta.json`, so an accidental change to the
generator (which would shift the corpus) fails loudly.

## Run the perf harness

```bash
flutter test --dart-define=RUN_BENCHMARKS=true test/perf/lint_perf_bench.dart
```

Median-of-three per metric; one JSON row per metric appended to
`build/perf/results.jsonl` (gitignored). Record hardware + build-mode when
comparing results across machines.
