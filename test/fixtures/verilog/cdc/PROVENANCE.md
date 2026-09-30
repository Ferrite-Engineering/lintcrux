# CDC capstone fixture

Copied from the EDU pack `cdc-soc-capstone`
(`edacrux-edu-packs/packs/`), which is the design LintCrux uses as its CDC
gate.

Four files, one design:

| File | Role |
|---|---|
| `soc_top.v` | Top; instantiates the three below and carries `clk_a` / `clk_b` |
| `producer.v` | `clk_a` domain — drives `req` and an 8-bit `data` bus |
| `consumer.v` | `clk_b` domain — samples both |
| `sync2.v` | A correct two-flop synchronizer, used on `req` only |

## Why this design and not a smaller one

It contains **both** the hazard and the correct construct. `data` crosses
`clk_a → clk_b` with nothing in between; `req` crosses through `sync2`. A
fixture with only the hazard would be passed by a detector that flags every
crossing, which is the failure mode that makes CDC tools get uninstalled. The
"`req` is NOT flagged" assertion is the half of the gate that has teeth.

## Elaboration constraints

The tests run yosys with `flatten` and deliberately **without** `opt`.

- `flatten` is required, not cosmetic: unflattened, each module is its own scope
  and a crossing *between* two instances is invisible — which is most of the
  crossings that matter.
- `opt` is omitted because it folds and retimes the exact structure the analysis
  reads. An optimized two-flop chain can be merged, at which point a correct
  design starts reporting as unsafe.

Regenerating or replacing these files means re-checking both constraints.
