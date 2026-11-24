# LintCrux for coding agents

LintCrux lints Verilog, SystemVerilog and VHDL with the engines a project
configures (Verilator, Verible, Slang, Yosys, GHDL, svlint, and LintCrux's own
structural CDC and pin-constraint checks) and answers over the Model Context
Protocol (MCP), so a coding agent can lint a design instead of guessing whether
it is clean. Every answer is also a command, with the same output.

## What the server offers

The server is started with `lintcrux mcp --root <project directory>`. It speaks
MCP over standard input and output, runs on your machine, writes nothing into
the project and makes no network call of its own. Every path a tool receives
must be inside `--root` (the working directory when omitted), and so must every
source, include directory and Verilator configuration file a `.lintcrux`
project names. A path outside it, a symbolic link that leads outside it, or a
network path is refused and nothing is run. A project that hands an engine raw
flags is refused too: run it from the command line.

The engines are the ones on `PATH`. The server offers no way to name another
engine binary, to write an export or a baseline, or to tolerate a missing
engine: a person does those from the command line.

| Tool | What it returns |
|---|---|
| `lint` | Every engine's run, the counts by severity, and the findings: rule, severity, message, `file:line`, whether a waiver suppressed it, its baseline state |
| `rule` | A rule's default severity and the engine's help link, by the `engineId/ruleId` a finding gives |
| `waivers` | The waivers in force: inline `lint_off` pragmas, Verilator configuration `lint_off` lines, and the baseline's frozen findings |

`lint` takes a `.lintcrux` project, or source files with an optional top module.
LintCrux Pro, started as `lintcrux_pro mcp`, serves the same three tools and
includes in the answer what needs a Pro licence, such as CDC findings and a
project's managed waivers. Below Pro, that part is left out and a
`licence.withheld` warning in the document says so; the rest of the answer
stands.

Each tool is also a command, with the same inputs as flags and the same output
with `--json`:

```
lintcrux design.lintcrux --json
lintcrux top.sv fifo.sv --top top --json
lintcrux rule verilator/WIDTH --json
lintcrux waivers design.lintcrux --json
```

A tool's text is byte for byte what the command writes, so a script and an
agent read the same document.

## Register it with your agent

The `lintcrux` command must be on the `PATH` of the program that starts the
server. The instructions below were checked against each host's own
documentation on 2026-11-24; hosts change, so check theirs if a step differs.
To use Pro, replace `lintcrux` with `lintcrux_pro`.

=== "Claude Code"

    Add the server for the current project:

    ```
    claude mcp add --transport stdio lintcrux -- lintcrux mcp --root /path/to/project
    ```

    Everything after `--` is the command that starts the server. By default the
    entry is private to you and the project. To share it with your team, add
    `--scope project`, which writes `.mcp.json` in the project root:

    ```json
    {
      "mcpServers": {
        "lintcrux": {
          "command": "lintcrux",
          "args": ["mcp", "--root", "${CLAUDE_PROJECT_DIR:-.}"]
        }
      }
    }
    ```

    Claude Code asks each person to approve a project server the first time.
    Run `claude mcp list`, or `/mcp` inside Claude Code, to see that it
    connected.

=== "VS Code"

    With the EDACrux LintCrux extension installed, there is nothing to
    configure. The extension registers the server with the editor for each
    workspace folder you open, with that folder as `--root`, and the editor asks
    you before it first runs. It needs a folder open in a trusted workspace.
    It finds `lintcrux_pro` or `lintcrux` through the `edacrux.lint.executable`
    setting, then your `PATH`. Turn registration off with the
    `edacrux.lint.mcp.enabled` setting.

    Without the extension, add the server to `.vscode/mcp.json` in the
    workspace (VS Code's own file uses `servers`, not `mcpServers`):

    ```json
    {
      "servers": {
        "lintcrux": {
          "type": "stdio",
          "command": "lintcrux",
          "args": ["mcp", "--root", "${workspaceFolder}"]
        }
      }
    }
    ```

    Or run **MCP: Add Server** from the Command Palette and choose a command
    (stdio) server.

=== "Cursor"

    Create `.cursor/mcp.json` in the project (or `mcp.json` in `.cursor` in your
    home folder for every project):

    ```json
    {
      "mcpServers": {
        "lintcrux": {
          "type": "stdio",
          "command": "lintcrux",
          "args": ["mcp", "--root", "${workspaceFolder}"]
        }
      }
    }
    ```

    Then open **Customize** in the sidebar and confirm the server is enabled.
    If it does not connect, open the Output panel and choose "MCP Logs".

An editor that does not offer the registration API gets the same snippet from
the **Copy LintCrux MCP Server Configuration** command in the Command Palette.

## When an agent should call it

- Before it says that lint is clean: lint the project, and report the outcome
  and the counts the document gives.
- After it changes RTL: lint again and compare. A finding whose `baseline` is
  `new` is one the project's baseline does not already accept.
- When a finding names a rule it does not know: `rule` gives its default
  severity and the engine's page for it.
- Before it argues that a finding does not matter: `waivers` lists the waivers
  already in force and where each is written.

## Read the outcome first

Every answer is one JSON document. Its `outcome` is the authority. An
`engine_error` is never a clean result: the document still lists what the other
engines found and says which engine did not finish, so the agent should say the
run is incomplete and name the engine, not that the design is lint clean. A
`failed_gate` means a gate the project or organisation set fired. The findings
are one page; when `truncated` is true the agent asks again with `offset` to
read the next page.

Two things an agent should never do: edit a waiver, a `lint_off` pragma, a
Verilator configuration file or the baseline to make a run clean (a waiver is a
person's decision, and none of the tools writes one), and report an
`engine_error` as clean or a page of findings as all of them.

## Cite with the link

LintCrux has no link of its own to open a finding. Tell the agent to cite every
finding as `file:line`, from its `location`, which every agent host, terminal
and editor makes clickable, and to give the rule as the finding names it
(`verilator/WIDTH`) with its severity. Where a person wants to see a finding in
LintCrux, the [agent link convention](https://edacrux.app/agent-links) page
describes the links the other EDACrux tools use.

Every finding is an engine's, or LintCrux's own CDC and pin-constraint check's.
LintCrux adds no verdict of its own.
