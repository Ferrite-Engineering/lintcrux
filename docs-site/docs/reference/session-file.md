# Session file format (`.lintcrux-session`)

```json
{
  "version": 1,
  "projectPath": "/work/my-soc/my-soc.lintcrux",
  "selectedRuleId": "verilator/UNUSEDSIGNAL",
  "activeSeverities": ["warning", "error"],
  "activeEngineIds": ["verilator"],
  "ruleSubstring": "unused",
  "fileGlob": "rtl/**/*.sv",
  "sortColumn": "rule",
  "sortAscending": false,
  "savedFilterPresetName": "triage",
  "viewMode": "table"
}
```

| Key | Type | Meaning |
|---|---|---|
| `version` | int | **Required.** Schema version, currently `1`. A file with a higher version is rejected. |
| `projectPath` | string | **Required.** Path of the `.lintcrux` file; the app writes it absolute. |
| `selectedRuleId` | string | Engine-namespaced rule id of the selected row. Omitted when nothing was selected. |
| `activeSeverities` | string list | Severity chips: `fatal`, `error`, `warning`, `note`, `none`. |
| `activeEngineIds` | string list | Engine chips, by engine id. |
| `ruleSubstring` | string | The rule/message filter text. |
| `fileGlob` | string | The file-glob filter text. |
| `sortColumn` | string | `severity` (default), `engine`, `rule`, `file`, `line`, or `message`. |
| `sortAscending` | bool | Defaults to `true`. |
| `savedFilterPresetName` | string | Name of the filter preset active when saved. Omitted when none was. |
| `viewMode` | string | `table` (default) or `detailFocused`. |

Sessions are tab-scoped UI snapshots; the project file is the load-time
source of truth. Unknown keys and unrecognized enum values are ignored
(forward-compatible); a missing `version` or `projectPath` is an error.
