# EDAM fixtures — real FuseSoC captures from SERV

Two genuine `fusesoc`-generated EDAM (`.eda.yml`) files, captured from
[SERV](https://github.com/olofk/serv) 1.4.0 with FuseSoC 2.4.x /
Edalize 0.6.x on 2026-08-15, `core_file:` paths shortened to a neutral
relative form. They are reference captures for `EdamReader`
(guide §22), chosen because they exercise the two EDAM shapes in the
wild:

| File | API | What it exercises |
|---|---|---|
| `serv.eda.yml` | tool API (`lint-verilator` flow dir) | `tool_options.verilator` with `mode: lint-only` + `verilator_options: [-Wall]`, a `file_type: vlt` Verilator waiver, a parameter (`W`) with no default |
| `servant.eda.yml` | flow API (`flow_options: {tool: verilator}`) | the full `serv → servile → servant` dependency closure (three cores, 26 sources), resolved `toplevel: servant`, per-file `core:` provenance, `vlogdefine`/`vlogparam` declarations without defaults |

Regenerate:

```bash
pip install fusesoc
fusesoc library add serv /path/to/serv
fusesoc run --target=lint --setup award-winning:serv:serv
fusesoc run --target=lint --setup award-winning:serv:servant
# → build/<name>/{lint-verilator,lint}/<name>.eda.yml
```

Note the fixtures' `files[].name` entries point into the FuseSoC
`build/.../src/` staging area, which is not committed — these files
verify the *reader mapping* (they parse and import), not a full lint
run. For an end-to-end run, regenerate against a real SERV checkout
per guide §22.2.
