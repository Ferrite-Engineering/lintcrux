# Appearance & themes

LintCrux is themed by the shared theme engine used across the EDACrux suite, so a preset you pick here looks the same in WaveCrux, NetCrux and SimCrux. `Settings → Appearance` is the single theming surface: the language picker, six built-in presets, per-token color overrides on top of the active preset, and importable theme packs.

## Color theme presets {#presets}

Open Settings (++cmd+comma++ / ++ctrl+comma++) and select **Appearance**. Under **Presets**, six presets ship built in, listed here in the order they render:

| Preset | Brightness |
|---|---|
| Crux Dark *(the default)* | Dark |
| Crux Light | Light |
| Solarized Dark | Dark |
| High Contrast Dark | Dark |
| Oscilloscope | Dark |
| OLED XR | Dark |

Only one light preset ships — **Crux Light**. The other five are dark. OLED XR is a true-black, high-luminance palette tuned for Micro-OLED XR and AR glasses.

## Light, dark, and the toggle {#light-dark}

The active preset *is* the light/dark control. LintCrux derives its theme mode from the brightness of whichever preset is selected: pick Crux Light and the whole app goes light; pick any of the five dark presets and it goes dark. There is no separate Light / Dark / System setting.

**Toggle Theme** in the `View` menu and the command palette, bound to ++cmd+shift+k++ / ++ctrl+shift+k++, switches between the two built-in presets of opposite brightness: from any dark preset to Crux Light, and from Crux Light to Crux Dark. The preset picker shows the new selection.

## Per-token color overrides {#overrides}

Under **Color overrides**, individual named colors can be overridden per category, on top of whichever preset is active. Click a token's swatch to pick a new color, or reset it to the preset's value. LintCrux registers three categories:

- **Application chrome** — Scaffold background, Panel background, Panel header background and foreground, Toolbar background, Toolbar icon, Toolbar icon (active), Status bar background and foreground, Splitter, Splitter (hover), Tab bar background, Tab bar (selected), Tab bar label.
- **Severity** — Fatal, Error, Warning, Note, None. These drive the severity column, chips and counts; see [Severity & pragmas](severity-and-pragmas.md#colors).
- **Trend** — Improving, Worsening, Unchanged, Baseline. Used by the Pro trend charts; making them deuteranopia-safe is a supported customization.

Overrides persist with your settings, so they survive restarts.

## Theme packs {#packs}

A theme pack is a `.crux-theme.json` file. Under **Theme packs** you can **Import theme pack…** and **Export current theme…**; installed packs are listed and live in the `themes` directory inside LintCrux's application-support folder. Because packs are plain files, a team can commit one to a repository and everyone triages against the same palette — including the same severity colors.

## What LintCrux does not have {#not-included}

!!! note "Not configurable"
    LintCrux has no accent-color picker, no UI density setting, and no font-size setting. Appearance is the language, the color preset, the per-token overrides and theme packs — nothing else.

!!! note "Next steps"
    For where Settings and the rest of the layout live, see [The interface](interface.md). For every binding, see the [Keyboard & mouse reference](keyboard-mouse.md).
