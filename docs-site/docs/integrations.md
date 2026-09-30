# Cross-probe & the suite

LintCrux is part of the EDACrux suite, and it talks to its siblings — WaveCrux, NetCrux and SimCrux — through cross-probe, and to your editor through click-to-source. A lint finding is rarely the end of the investigation; this is how you carry it into the tool that shows you the next layer.

## Cross-probe (CXP) {#cxp}

Cross-probe (CXP) is the suite's lightweight protocol for "show me this location over there". It is [specified publicly](https://edacrux.app/cxp). The CXP server is configured in `Settings → CXP Cross-Probe`:

- **Enable CXP server** turns it on, and **CXP port** sets where it listens. The section also shows whether the server is running and how many peers are connected.
- **Request attention on cross-probe** bounces the dock icon (or flashes the taskbar) when a peer sends a cross-probe. It never steals focus.
- **Broadcast selection automatically** (on by default) announces every violation you select to connected peers, so a waveform or schematic viewer can follow along. Turn it off to keep selections to yourself; explicit sends still work.

Two directions exist:

- **Receive** — a connected peer can ask LintCrux to highlight a rule or a source location, which filters the table and selects the matching violation; to open a source location in your editor; or to open a design's LintCrux project that the suite's shared workspace knows about. Every request is acknowledged, including the ones LintCrux cannot act on, so the sending tool can tell you why.
- **Originate** <span class="tier tier-pro">Pro</span> — right-click a violation and choose **Cross-probe to peer…**, pick a connected peer, and LintCrux sends it the violation's location. The send is acknowledged: LintCrux tells you whether the peer acted on it (*Sent to …*), declined it with the peer's reason, or did not respond.

![Two EDACrux apps running side by side with their Cross-Probe panels open: NetCrux showing the VexRiscv schematic with its peer list (simcrux, wavecrux, lintcrux), and WaveCrux showing waveform lanes with the same connected peers plus a live 'Selection received' cross-probe event from LintCrux.](img/CrossProbe.png)

*Two suite apps discovering each other over CXP — each Cross-Probe panel lists the connected peers, and inbound selections appear in the event feed.*

## The Cross-Probe panel {#panel}

The [Cross-Probe panel](interface.md#crossprobe) (++cmd+shift+x++ / ++ctrl+shift+x++) lists connected peers, shows the event log of probes sent and received, and reports the server status, so you can see at a glance which suite tools are wired up. It opens as a tab in the right dock, and you can drag it to the bottom dock. A CDC finding in LintCrux, for example, can be sent to NetCrux to inspect the crossing in the schematic.

## Editor presets & click-to-source {#editors}

Click-to-source opens the offending `file:line` in your editor — from a double-click on a table row or the Inspector's **Open in editor** button. Configure the command under `Settings → Editors → Click-to-source editor` with a preset or a custom template:

| Editor | Command |
|---|---|
| Visual Studio Code | `code -g {file}:{line}:{column}` |
| Sublime Text | `subl {file}:{line}:{column}` |
| Vim / Neovim | `vim +{line} {file}` |
| Emacs | `emacs +{line} {file}` |
| Custom | an **Executable** and an **Arguments template** using `{file}`, `{line}` and `{column}` |

A **Live preview** shows the command a sample location would produce, and **Reset to default (VS Code)** restores the default.

## Multi-project workspaces <span class="tier tier-pro">Pro</span> {#workspace}

Large efforts span many projects. Open Core already opens several projects as tabs and split panes; Pro replaces its single-project registry with a persistent multi-project one, so your open projects, their pinned state and your recent projects survive a restart. What that registry drives:

- **Pin Project Tab** — keep the projects you always want open out of the way of a bulk close.
- **Close All Projects** — clear the working set in one action; pinned projects stay open.
- **Reopen Recent Project** — closed projects are remembered across restarts.

The project switcher, **Switch Project…** (++cmd+p++ / ++ctrl+p++), lists your open projects and your recents together, so reopening one lands in the same place rather than in a second dialog showing half the picture. **Search Across Projects…** (++cmd+shift+f++ / ++ctrl+shift+f++) searches every open project's violations at once. These actions are in the `File` and `Search` menus and the command palette.

All of them are Pro. In Open Core they are visible and badged, and choosing one tells you it requires LintCrux Pro rather than doing nothing — a deliberate press answered with silence is indistinguishable from a broken build. The Open Core **Close All Tabs** and **Close Active Project** actions work at every tier.

!!! note "Next steps"
    The suite siblings have their own documentation — WaveCrux for waveforms, NetCrux for netlists, SimCrux for regressions. For sharing trend data across a team, see the [team trend database](team-database.md) <span class="tier tier-enterprise">Enterprise</span>.
