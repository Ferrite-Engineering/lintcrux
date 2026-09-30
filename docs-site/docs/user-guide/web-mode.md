# The web viewer

The browser viewer at [app.lintcrux.app](https://app.lintcrux.app)
renders any SARIF 2.1.0 document with the same filter chips, virtualized
violation table, inspector, and source-preview layout as the desktop
dashboard — but without the ability to spawn lint-engine subprocesses,
watch project files, or persist settings to disk.

## When to use it

* **Sharing a CI report in a PR.** Publish your SARIF export to a
  pre-signed S3 URL (or any HTTPS host that allows CORS to the
  LintCrux origin) and link `https://app.lintcrux.app/?sarif=<url>`.
  Reviewers open the URL and get the triage table with no install.
* **Quick one-off triage.** Open a `.sarif` / `.sarif.json` file from a
  local download. The viewer parses it in the browser; nothing leaves
  your machine.
* **Demoing LintCrux.** Show the dashboard to a colleague without
  walking them through engine setup.

The desktop app can open a SARIF report too: `File → Import SARIF
report…` loads it into the same read-only viewer — see
[Import a SARIF report on the desktop](../exports-and-ci.md#import-sarif).

## Two input mechanisms

### File upload

Click **Open SARIF File…** on the landing screen and pick a `.sarif` or
`.json` file from your local disk. The browser reads the bytes through
its file picker and parses them entirely client-side — the file is never
uploaded to any server.

### URL parameter

Two equivalent paths:

* **Paste a URL** into the **SARIF URL** field and click **Open**.
* **Encode the URL in the query string**:
  `https://app.lintcrux.app/?sarif=https%3A%2F%2Fexample.com%2Freport.sarif`.
  The viewer auto-fetches on landing.

The URL must use the `http` or `https` scheme and must serve the
SARIF document with permissive CORS headers
(`Access-Control-Allow-Origin: *` or matching the LintCrux origin).
Pre-signed S3 URLs and most artifact stores that allow CORS satisfy
this; documents behind authenticated APIs do not.

## Limitations vs. the desktop app

The web viewer is intentionally read-only. The following features
are **desktop-only**:

| Feature | Desktop | Web |
|---|---|---|
| Run lint engines (Verilator, Verible, Slang, …) | ✓ | ✗ — browsers cannot spawn subprocesses |
| Open project (`.lintcrux`) files | ✓ | ✗ |
| Import Vivado-style `.f` filelists / FuseSoC EDAM | ✓ | ✗ |
| Sessions, workspaces, tabs and split panes | ✓ | ✗ |
| Persist settings to disk | ✓ | ✗ |
| Render violation table | ✓ | ✓ |
| Severity / engine chips, text filters, sort | ✓ | ✓ |
| Search dialog (`Cmd/Ctrl+F`) | ✓ | ✓ — searches the loaded report |
| Inspector pane (message, location, severity) | ✓ | ✓ |
| Rule metadata (tags, **Learn more**) and the Rules panel | ✓ | ✓ |
| Source preview | ✓ — reads the file from disk | ✗ — the pane shows "Could not read source"; SARIF snippets are not rendered |
| Render error / warning / note / fatal levels | ✓ | ✓ |
| CJK localization | ✓ | ✓ |

If a workflow requires any of the desktop-only capabilities, install
the desktop app from [lintcrux.app](https://lintcrux.app/download).

## Performance

The viewer ingests reports through the same streaming SARIF reader as
the desktop app, which is tested to load a 100,000-violation document
in bounded memory; the table is virtualized, so scrolling cost does not
grow with the report. A URL-fetched report is downloaded in full before
parsing starts, and a very large report can take a few seconds to parse.

## Privacy

* The file-upload path keeps the SARIF document entirely on your
  machine. Nothing is sent to a server.
* The URL-fetch path issues a single GET from your browser directly
  to the host you specify. LintCrux's deployment never sees the
  document body — the request does not pass through our
  infrastructure.

## Deployment

The viewer is a static site (no backend), so anyone can host their own
instance. It is built from a checkout of the LintCrux open-core
repository, with the Flutter SDK:

```bash
git submodule update --init --recursive
flutter pub get
flutter build web --release
# build/web/ is a complete, statically servable bundle.
```

Serve `build/web/` with single-page-application fallback to
`index.html`, so `?sarif=` deep links resolve client-side.
