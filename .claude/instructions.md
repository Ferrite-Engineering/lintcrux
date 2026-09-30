# LintCrux Localization Guidelines

**Canonical source:** the suite-wide CJK house style lives in the WaveCrux repo at `wavecrux/.claude/instructions.md`. This file is the LintCrux-adapted copy: the Core Principles, Suite-Wide Terms, acronym/brand lists, Placeholder Rules, Formatting Rules, Language-Specific Rules, and Prohibited Patterns are kept in sync with the canonical file and must not contradict it. Only the glossary table below is LintCrux-specific.

## Core Principles

1. **Precision over politeness** – Users are EDA professionals. Technical accuracy trumps marketing fluff.
2. **Conciseness** – UI space is limited. Keep buttons short; tooltips can be longer.
3. **Consistency** – Same English term → same translation everywhere in a given language.
4. **Preserve placeholders** – Never break ICU MessageFormat syntax.

## LintCrux Glossary (Mandatory Mappings — 2026-07-18 standardization)

These are the standardized post-sweep renderings actually used in the LintCrux ARB files (core and Pro overlay). Same English term → same rendering everywhere.

| English | zh-CN | ja | ko |
|---------|-------|-----|-----|
| lint (the activity) | Lint (Latin, capitalized) | リント | 린트 |
| lint engine | Lint 引擎 | リントエンジン | 린트 엔진 |
| lint cache | Lint 缓存 | リントキャッシュ | 린트 캐시 |
| violation | 违规 (never 违例) | 違反 | 위반 |
| waiver / waive | 豁免 | ウェイバー | 면제 |
| review waivers (action) | 审阅豁免 | ウェイバーをレビュー | 면제 검토 |
| severity | 严重程度 | 重大度 (never 重要度) | 심각도 |
| severity: Note | 提示 | 注記 | 참고 |
| severity: Unclassified | 未分类 | 未分類 | 미분류 |
| severity drift (chart) | 严重性漂移图 | 重大度ドリフトチャート | 심각도 추이 차트 |
| rule | 规则 | ルール | 규칙 |
| baseline | 基线 | ベースライン | 기준선 |
| engine | 引擎 | エンジン | 엔진 |
| bookmark | 书签 (never 收藏) | ブックマーク | 북마크 (never 책갈피) |
| stale (bookmark) | 陈旧 (never 过期 — that is waiver-Expired) | 古い | 오래됨 |
| dry-run | 试运行 | ドライラン | 드라이런 (never 시험 실행) |
| preset | 预设 | プリセット | 프리셋 (never 사전 설정) |
| filter (noun) | 筛选器 (never 过滤器) | フィルター | 필터 |
| filter preset | 筛选预设 | フィルタープリセット | 필터 프리셋 |
| glob | glob (Latin in all locales) | glob | glob |
| filelist (.f) | 文件列表 | ファイルリスト | 파일 리스트 |
| custom (rule/binary) | 自定义 | カスタム | 사용자 정의 (never 사용자 지정) |
| bundled (binary source) | 内置 | バンドル | 번들 |
| pragma | 编译指示 | プラグマ | 프래그마 |
| line (source line) | 行 | 行 | 라인 |
| run (lint run) | 运行 | 実行 | 실행 |
| cancel run | 取消运行 | 実行をキャンセル | 실행 중단 (never 실행 취소 — reads as Undo) |
| peer (CXP) | 对等端 (never 对端) | ピア | 피어 |
| diagnostic / diagnostics | 诊断 | 診断 | 진단 |

## Suite-Wide Terms (identical in every Crux app — 2026-07-18 rulings)

These concepts appear in more than one Crux app (CXP, shared chrome, settings). Every app — core and Pro overlay — must use exactly these renderings. App-local glossaries may add terms but may never override this table.

| English | zh-CN | ja | ko |
|---------|-------|-----|-----|
| cross-probe / cross-probing | 交叉探测 | クロスプローブ | 교차 프로브 |
| Remote Control (settings section) | 远程控制 | リモートコントロール | 원격 제어 |
| waiver / waive | 豁免 | ウェイバー | 면제 |
| workspace | 工作区 | ワークスペース | 워크스페이스 |
| preset | 预设 | プリセット | 프리셋 |
| editor | 编辑器 | エディター | 에디터 |
| viewer | 查看器 | ビューアー | 뷰어 |
| open-core (edition name) | 开放核心版 | オープンコア | 오픈 코어 |
| command palette | 命令面板 | コマンドパレット | 명령 팔레트 |
| panel | 面板 | パネル | 패널 |
| pane | 窗格 | ペイン | 창 |

Note: 开放核心版, never 开源核心版 — "open-core" names the free edition, not a licence, and must not read as "open-source core".

## Acronyms (Never Translate)

VCD, FST, GHW, LXT, LXT2, FSDB, PCAP, CSV, JSON, XML, YAML, HTML, SVG, PNG, RGB, LED, LCD, OLED, FSM, RTL, API, SDK, ABI, CLI, GUI, WASM, TCP, UDP, HTTP, JSON-RPC, CXP, WCP, SARIF

**Protocol/Interface names (never translate):**
SPI, I2C, I²C, UART, AXI, AXI4, AXI4-Lite, APB, AHB, AHB-Lite, Wishbone, JTAG, MDIO, CAN, CAN-FD, USB, PCIe, Ethernet, MII, RMII, GMII, RGMII, AXIS, RISC-V, RV32, RV64, Cocotb, GTKWave, Synopsys

**Tools/commands (never translate):**
fsdb2vcd, vcd2fst, xml2stems, vermin, dlopen, LoadLibrary, make, cmake, ghdl, iverilog, verible-verilog-lint

**Product / brand names (never translate — 2026-07-18 ruling):**
WaveCrux, NetCrux, LintCrux, SimCrux, EDACrux, Ferrite Engineering, Stage, Stage Pro, Rive, Yosys, Verible, Verilator, svlint, GHDL, Icarus Verilog, FuseSoC, Vivado, Quartus

"Stage" is the WaveCrux Stage brand and stays in Latin script everywhere (never 舞台 / ステージ / 스테이지). Legacy translated occurrences are defects to sweep.

## Placeholder Rules (ICU MessageFormat)

All plural placeholders MUST include both `=1` and `other` cases:

Correct:
"{count, plural, =1{1 signal} other{{count} signals}}"

Incorrect (missing =1 case):
"{count, plural, other{{count} signals}}"

For Chinese, Japanese, Korean (no grammatical number), use:

zh-CN:
"{count, plural, =1{1个信号} other{{count}个信号}}"

ja:
"{count, plural, =1{1シグナル} other{{count}シグナル}}"

ko:
"{count, plural, =1{1개 신호} other{{count}개 신호}}"

## Formatting Rules

### Ellipsis (…)
- All languages: No space before … (U+2026)
- Use single character …, not three dots

### Units
- Use localized unit symbols where standard: ms, ns, μs, MB, GB, Hz, kHz, MHz, GHz, FPS
- For frequency: {freq} Hz, {freq} MHz (keep space before unit in all languages)

### Symbols
- Δ (delta) → keep as Δ
- f (frequency) → keep as f (lowercase)
- × (multiply) → use ×, not x or *

### Punctuation width (2026-07-18 sweep)
- zh: full-width ，；？： directly after CJK text; never half-width , ; ? : there. Enforced by `test/static/l10n_house_style_guard_test.dart`.
- ja: full-width ？ after kana/kanji (enforced). Colons follow the core-dominant style: half-width `:` with a space before a following value ("検出: {version}"); trailing label colons are bare `:`. Full-width ： is not used.
- ja quotes: 「」, never ASCII '…'. zh quotes: “”, never 「」 or ASCII '…'.
- ja katakana compounds are closed up (リントエンジン, プロジェクトファイル, フィルタープリセットライブラリ — no interior space).

## Language-Specific Rules

### Chinese (zh-CN)
- Use Simplified Chinese only
- 跳变 = signal edge transition; 转换 = format conversion
- 注释 = comment (never 评论)
- 显示 = show/display; 隐藏 = hide
- 无法 = cannot/failed; 失败 = failed
- Prefer 4-character phrases where natural (节省空间)

### Japanese (ja)
- **signal = 信号, never シグナル** (2026-07-18 ruling). Sweep legacy シグナル occurrences.
- **Long-vowel (ー) forms for -er/-or katakana loanwords** (2026-07-18 ruling): デコーダー、インスペクター、エディター、ビューアー (not ビューワー)、サーバー、フォルダー、ドライバー、ワイヤー、シミュレーター、フィルター. Short forms are defects.
- 表示中の = "visible"
- 履歴 = "recent files history" (shorter than 最近のファイル)
- できません = polite negative; 失敗 = failure
- Never use あなた; use passive or drop subject
- Use kanji for common terms, katakana for technical imports

### Korean (ko)
- Use 10진수 (with Arabic numeral) for decimal
- No space before … (U+2026) – fix all instances
- Use subject-drop where natural
- Use native Korean words over Sino-Korean when shorter
- Particles attach directly to placeholders with no space ({ruleId}가, {currentCount}까지); counters likewise ({count}회, never {count} 회)

## Prohibited Patterns (All Languages)

- Never translate version numbers (v0.1.0 stays as-is)
- Never translate placeholder variable names ({count}, {filename}, {reason})
- Never translate help/documentation URLs (lintcrux.app)
- Never translate license names (MIT, BSD-3-Clause)
- Never translate company names (Ferrite Engineering)
- Never translate brand/trademark disclaimers except for localization (keep original company names)

## Button Label Length Targets

| Language | Max chars for primary button | Max chars for tooltip |
|----------|------------------------------|----------------------|
| zh-CN | 8 | unlimited |
| ja | 10 | unlimited |
| ko | 8 | unlimited |

Example shortening:
- "Generate & Open in New Tab" → zh: "生成并打开", ja: "生成して開く", ko: "생성 후 열기"
- "Remove from recent files" → zh: "移除", ja: "削除", ko: "제거" (tooltip explains)

## Quality Checklist

Before outputting any ARB translation:
- [ ] All plural placeholders have `=1` case
- [ ] Acronyms are untouched
- [ ] URLs unchanged
- [ ] No English leftover (except acronyms and rulings that keep Latin: Lint in zh, glob everywhere)
- [ ] Consistent with glossary
- [ ] Button labels reasonably short
- [ ] `flutter test test/static/l10n_house_style_guard_test.dart` passes
