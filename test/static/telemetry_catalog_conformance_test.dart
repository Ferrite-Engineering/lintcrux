// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The telemetry catalog's conformance guard.
//
// WHY THIS TEST EXISTS, AND WHY IT IS WORTH ITS LENGTH:
//
// The telemetry ingestion Worker validates every
// event it receives, and every one of its rejections is SILENT.
//
//   * An event NAME that fails `^[a-z0-9_]+(\.[a-z0-9_]+){1,2}$` is skipped.
//     The batch still returns 202; the row is counted only in the response's
//     `dropped` field, which the client does not read and no dashboard shows.
//   * A property KEY that fails `^[a-z][a-z0-9_]{0,31}$`, or a VALUE that is
//     neither `[a-z0-9_]{1,64}`, nor a bool, nor an integer with |v| <= 100000,
//     is dropped while the event is KEPT. That is the worse failure: the
//     counter looks healthy and one of its dimensions is permanently empty.
//
// Nothing in the app, the queue, the response, or the SQL API can distinguish
// "nobody used this feature" from "every row was discarded at the edge". A
// capital letter in an event name costs the whole event, forever, with no
// error anywhere. So the grammar is asserted HERE, client-side, where a
// violation is a failing build instead of a quiet hole in the data.
//
// The LintCrux-specific hazard is the one the suite telemetry policy
// (https://edacrux.app/telemetry) names outright: rule
// names paired with file content, and lint output bodies, are never collected.
// Engine names ARE application vocabulary and are fine. The rule that keeps
// those apart is `telemetryEngineToken`, and the tests below pin its output to
// the engine registry so a new engine cannot arrive as free text.
//
// The rules enforced:
//
//  1. Every event name recorded anywhere in `lib/` appears in the pinned
//     `kLintcruxEventCatalog`. An undocumented event cannot ship.
//  2. Conversely, every catalog entry is still recorded somewhere (Pro-only
//     entries excepted, since they live in the other repo, and the shared
//     `app.uncaught_error`, which `crux_telemetry` records) — a catalog that
//     accumulates dead names stops being a description of the product.
//  3. Every catalog name matches the Worker's event-name class.
//  4. Every property key matches the Worker's property-key class.
//  5. Every enumerated property value matches the Worker's value class.
//  6. The catalog's enum-derived value sets equal what `telemetryEnumToken`
//     produces from the Dart enums they came from, so adding a camelCase
//     constant to `SearchMode` (or a new `EditorPreset`) fails here rather
//     than losing a property at the edge.
//  7. No duplicate names; no event over the Worker's six-property cap.
//  8. `telemetryEngineToken` maps every registered engine id to itself, and
//     everything else to a literal from the catalog's own list.
//
// The scanner reads string literals passed to `TelemetryEvent(...)`, which is
// why instrumentation call sites spell their event names as literals rather
// than referencing constants: a constant would make rule 1 vacuous.

import 'dart:io';

import 'package:crux_license/crux_license.dart' show LicenseTier;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lintcrux/app.dart' show ExportFormat;
import 'package:lintcrux/domain/enums/violation_view_mode.dart';
import 'package:lintcrux/domain/models/custom_regex_rule.dart';
import 'package:lintcrux/domain/models/editor/editor_command.dart';
import 'package:lintcrux/domain/models/engine_run_outcome.dart';
import 'package:lintcrux/services/engines/default_engine_registry.dart';
import 'package:lintcrux/services/rules/custom_rule_evaluator.dart';
import 'package:lintcrux/services/search/violation_search.dart';
import 'package:lintcrux/services/telemetry/telemetry_event_catalog.dart';

/// The ingestion Worker's `EVENT_NAME`.
final _eventName = RegExp(r'^[a-z0-9_]+(\.[a-z0-9_]+){1,2}$');

/// The ingestion Worker's `PROPERTY_KEY`.
final _propertyKey = RegExp(r'^[a-z][a-z0-9_]{0,31}$');

/// The ingestion Worker's `PROPERTY_VALUE`.
final _propertyValue = RegExp(r'^[a-z0-9_]{1,64}$');

/// The Worker's `MAX_PROPERTIES`.
const int _maxProperties = 6;

/// Matches the event-name argument of a `TelemetryEvent('…')` construction, or
/// of the workspace notifier's `_emit('…')` wrapper around one.
///
/// Single-quoted only — the house style throughout `lib/`, and a double-quoted
/// literal would be caught by the analyzer's quote lint first.
final _recordedEvent = RegExp(
  r"(?:TelemetryEvent|_emit|_record)\(\s*'([^']+)'",
);

/// Every `TelemetryEvent(` construction, whether or not its first argument is
/// a literal. Used to prove the scanner above sees all of them.
final _anyConstruction = RegExp(r'TelemetryEvent\(');

/// The files where a `TelemetryEvent` is constructed from a variable rather
/// than a literal: the two thin `_emit`/`_record` wrappers whose callers pass
/// the literal instead and are matched by [_recordedEvent].
const Set<String> _indirectConstructionSites = <String>{
  'lib/features/workspace/providers/workspace_provider.dart',
  'lib/features/run/providers/lint_run_notifier.dart',
  'lib/app.dart',
  'lib/services/telemetry/headless_telemetry.dart',
};

/// Pipeline files that construct a [TelemetryEvent] from stored data rather
/// than recording one. The headless reporter builds its events from the same
/// two `_record` helpers the GUI uses; its wrapper is listed above.
const Set<String> _pipelineFiles = <String>{};

/// Catalog entries that live in the Pro overlay and so cannot be found by a
/// scan of this repository. The Pro repo runs the same rule-2 check over its
/// own tree against the same catalog.
const Set<String> _proOnlyEvents = <String>{
  'tier.gate_hit',
  'waiver.created',
  'waiver.deleted',
  'baseline.set',
  'trend.chart_opened',
  'autofix.run',
  'cache.lookup',
  'custom_rule.evaluated',
  'bookmark.saved',
  'filter_preset.saved',
  'cross_project.searched',
};

/// Catalog entries recorded by a shared package rather than by a call site in
/// either repository. `crux_telemetry` records `app.uncaught_error` from the
/// global error handlers, so no scan of this repository's `lib/` can find it,
/// and it is excused from the "still recorded" rule.
const Set<String> _sharedEvents = <String>{'app.uncaught_error'};

void main() {
  const catalog = kLintcruxEventCatalog;

  test('no duplicate catalog entries', () {
    final seen = <String>{};
    final duplicates = <String>[];
    for (final event in catalog) {
      if (!seen.add(event.name)) duplicates.add(event.name);
    }
    expect(duplicates, isEmpty, reason: 'each event is listed once');
  });

  test('every catalog name matches the Worker event-name class', () {
    final bad = [
      for (final event in catalog)
        if (!_eventName.hasMatch(event.name)) event.name,
    ];
    expect(
      bad,
      isEmpty,
      reason:
          'The ingestion Worker drops these names without reporting anything, '
          'so the events would never arrive. Names are lowercase, '
          'dot-separated, two or three segments:\n'
          '${bad.join('\n')}',
    );
  });

  test('every property key matches the Worker property-key class', () {
    final bad = <String>[];
    for (final event in catalog) {
      for (final key in event.propertyKeys) {
        if (!_propertyKey.hasMatch(key)) bad.add('${event.name}.$key');
      }
    }
    expect(
      bad,
      isEmpty,
      reason:
          'A key outside the Worker property-key class is dropped while its '
          'event is kept — the counter survives and the dimension is silently '
          'empty:\n${bad.join('\n')}',
    );
  });

  test('every enumerated property value matches the Worker value class', () {
    final bad = <String>[];
    for (final event in catalog) {
      event.enumeratedValues.forEach((key, values) {
        for (final value in values) {
          if (!_propertyValue.hasMatch(value)) {
            bad.add('${event.name}.$key = $value');
          }
        }
      });
    }
    expect(
      bad,
      isEmpty,
      reason:
          'Values are identifiers from our own vocabulary — no capitals, no '
          'dots, no spaces:\n${bad.join('\n')}',
    );
  });

  test('no event exceeds the Worker property cap', () {
    final over = [
      for (final event in catalog)
        if (event.propertyKeys.length > _maxProperties)
          '${event.name} (${event.propertyKeys.length})',
    ];
    expect(
      over,
      isEmpty,
      reason:
          'The Worker encodes at most $_maxProperties properties per event; '
          'the rest are dropped in key order:\n${over.join('\n')}',
    );
  });

  group('enum-derived vocabularies match their Dart enums', () {
    // Each of these pins a catalog value list to the enum it is derived from,
    // so a new constant cannot be added to the enum without the catalog
    // being updated in the same change.

    List<String> valuesFor(String event, String key) =>
        catalog.firstWhere((e) => e.name == event).enumeratedValues[key]!;

    test('run.completed.trigger is LintRunTrigger', () {
      expect(
        valuesFor('run.completed', 'trigger').toSet(),
        LintRunTrigger.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('engine.run.status is EngineRunOutcome', () {
      expect(
        valuesFor('engine.run', 'status').toSet(),
        EngineRunOutcome.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('project.opened.source is ProjectOpenSource', () {
      expect(
        valuesFor('project.opened', 'source').toSet(),
        ProjectOpenSource.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('filter.used.kind is LintcruxFilterKind', () {
      expect(
        valuesFor('filter.used', 'kind').toSet(),
        LintcruxFilterKind.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('view_mode.changed.mode is ViolationViewMode', () {
      // `allViolations` → `all_violations`, not the shorter `all`: the enum
      // is authoritative.
      expect(
        valuesFor('view_mode.changed', 'mode').toSet(),
        ViolationViewMode.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('search.used.mode is SearchMode', () {
      expect(
        valuesFor('search.used', 'mode').toSet(),
        SearchMode.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('editor.launched.preset is EditorPreset', () {
      // `vsCode` → `vs_code`, not `vscode`. Same correction as above.
      expect(
        valuesFor('editor.launched', 'preset').toSet(),
        EditorPreset.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('export.completed.format is ExportFormat', () {
      expect(
        valuesFor('export.completed', 'format').toSet(),
        ExportFormat.values.map(telemetryEnumToken).toSet(),
      );
      // `ExportFormat` constants are already lowercase, so the tokens equal
      // the names. This asserts that stays true.
      expect(
        ExportFormat.values.every((v) => _propertyValue.hasMatch(v.name)),
        isTrue,
      );
    });

    test('trend.chart_opened.chart is TrendChartKind', () {
      expect(
        valuesFor('trend.chart_opened', 'chart').toSet(),
        TrendChartKind.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('autofix.run.stage is AutofixStage', () {
      expect(
        valuesFor('autofix.run', 'stage').toSet(),
        AutofixStage.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('tier.gate_hit.feature is LintcruxGatedFeature', () {
      expect(
        valuesFor('tier.gate_hit', 'feature').toSet(),
        LintcruxGatedFeature.values.map(telemetryEnumToken).toSet(),
      );
      // The catalog reads the same list the enum produces, so the two cannot
      // drift apart without one of them being edited.
      expect(
        kLintcruxGatedFeatureTokens.toSet(),
        LintcruxGatedFeature.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('tier.gate_hit.required is pro or enterprise, and nothing else', () {
      // A gate never demands `edu` (EDU is Pro-equivalent
      // for gating) and never demands `openCore`. Both of those names would
      // also fail the Worker's value class on the way in — `openCore` has a
      // capital — so the dimension would go silently empty rather than wrong.
      expect(valuesFor('tier.gate_hit', 'required').toSet(), <String>{
        'pro',
        'enterprise',
      });
      // The call site sends `requiredTier.name`, so the catalog values have to
      // be exactly those two `LicenseTier` names and not lookalikes.
      expect(
        valuesFor('tier.gate_hit', 'required').toSet(),
        <String>{LicenseTier.pro.name, LicenseTier.enterprise.name},
      );
      expect(
        LicenseTier.values.map((t) => t.name),
        containsAll(valuesFor('tier.gate_hit', 'required')),
      );
    });

    test('custom_rule.evaluated.kind is CustomRulePatternKind', () {
      expect(
        valuesFor('custom_rule.evaluated', 'kind').toSet(),
        CustomRulePatternKind.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('waiver.created.scope is WaiverScope', () {
      expect(
        valuesFor('waiver.created', 'scope').toSet(),
        WaiverScope.values.map(telemetryEnumToken).toSet(),
      );
    });
  });

  group('the commercial group cannot leak the display string', () {
    test('no gated-feature token is a localized label', () {
      // The trap the suite telemetry rules call out by name:
      // `CruxUpgradeDialog.featureName` is localized display text. If a call
      // site ever passed it instead of a `LintcruxGatedFeature`, the value
      // would carry spaces, capitals or CJK and the Worker would drop the
      // property while keeping the event — leaving `feature` permanently empty
      // and the counter looking healthy.
      for (final token in kLintcruxGatedFeatureTokens) {
        expect(_propertyValue.hasMatch(token), isTrue, reason: token);
      }
    });

    test('the vocabulary is not a sanitizer over arbitrary strings', () {
      // `telemetryEnumToken` takes an `Enum`. There is no `String` overload to
      // reach for, so a localized label cannot be washed into a legal token
      // the way a `String → String` helper would allow. This asserts the
      // property that makes that true: every value the event can carry comes
      // from `LintcruxGatedFeature.values` and from nowhere else.
      expect(
        LintcruxGatedFeature.values.map(telemetryEnumToken).toSet(),
        kLintcruxGatedFeatureTokens.toSet(),
      );
    });
  });

  group('the headless binary cannot emit a GUI-only event', () {
    test('HeadlessTelemetry records exactly two names, neither commercial', () {
      // A gate hit is inherently a GUI event — `lintcrux --ci` has no
      // dialog to raise, no tier to deny at, and no user to explain to. The
      // guarantee is structural rather than conventional: `HeadlessTelemetry`
      // has no general `record`, only two named methods, so there is no call
      // shape that could send `tier.gate_hit` (or any other Pro counter) from
      // the CLI. This test is what fails if a third one is ever added.
      final source = File(
        'lib/services/telemetry/headless_telemetry.dart',
      ).readAsStringSync();
      final names = RegExp(
        r"_record\(\s*'([^']+)'",
      ).allMatches(source).map((m) => m.group(1)!).toSet();
      expect(names, <String>{'run.completed', 'engine.run'});
      expect(source.contains('tier.gate_hit'), isFalse);
      // `_record` is private and the only path into `_events`, so the public
      // surface is the two wrappers above it.
      expect(
        RegExp(r'\n  void record[A-Z]\w*\(').allMatches(source).length,
        2,
        reason:
            'a third public recorder on HeadlessTelemetry is a new event the '
            'CLI can send — vet it against the suite telemetry rules '
            '(https://edacrux.app/telemetry) before adding it here',
      );
    });
  });

  group('the engine vocabulary is closed', () {
    test('every registered engine id maps to itself', () {
      // The check that keeps `engine` a real dimension. An engine added to
      // `defaultEngineRegistry()` without a `telemetryEngineToken` case would
      // silently report `other`, and "which engines to invest in" would be
      // answered with the six we already knew about.
      for (final id in defaultEngineRegistry().engineIds) {
        expect(
          telemetryEngineToken(id),
          id,
          reason:
              'engine "$id" is registered but has no telemetryEngineToken '
              'case, so every one of its runs would report `other`',
        );
        expect(kLintcruxEngineTokens, contains(id));
      }
    });

    test('the custom-rule pseudo-engine maps to a listed token', () {
      expect(telemetryEngineToken(kCustomRuleEngineId), 'custom');
      expect(kLintcruxEngineTokens, contains('custom'));
    });

    test('anything else collapses to a literal, never to itself', () {
      // The property that makes this not a sanitizer. Whatever a future engine
      // pack — or a corrupted SARIF import — puts in `Violation.engineId`, the
      // value that leaves the process is one of ours. The inputs below are the
      // shapes the never-collect list bans outright.
      for (final hostile in <String>[
        'verilator/WIDTH',
        'MyEngine',
        '/Users/someone/design/top.sv',
        'width mismatch in top.sv line 42',
        '',
      ]) {
        expect(telemetryEngineToken(hostile), 'other');
      }
    });

    test('every engine token is itself Worker-legal', () {
      for (final token in kLintcruxEngineTokens) {
        expect(_propertyValue.hasMatch(token), isTrue, reason: token);
      }
    });
  });

  test('app.uncaught_error carries the shared counter vocabulary', () {
    // Recorded by `crux_telemetry`, not by this repository, so the lists are
    // the package's: four properties, no free text, a catch-all in each
    // open-ended dimension, and `none` for an error with no framework library.
    final entry = catalog.firstWhere((e) => e.name == 'app.uncaught_error');
    expect(entry.name, kTelemetryUncaughtErrorEvent);
    expect(entry.propertyKeys.toSet(), <String>{
      'source',
      'kind',
      'library',
      'silent',
    });
    expect(entry.boolProperties, <String>['silent']);
    expect(entry.intProperties, isEmpty);
    // The package's constants are the vocabulary, value for value and in
    // order. The catalog has to copy them, because the headless CLI compiles
    // it and cannot import the Flutter-dependent package; this is what keeps
    // the copy from drifting. MUTATION: dropping or adding one bucket in any
    // of the catalog's three lists makes this red.
    expect(entry.enumeratedValues['source'], kTelemetryUncaughtErrorSources);
    expect(entry.enumeratedValues['kind'], kTelemetryUncaughtErrorKinds);
    expect(
      entry.enumeratedValues['library'],
      kTelemetryUncaughtErrorLibraries,
    );
    expect(entry.enumeratedValues['source'], <String>['flutter', 'platform']);
    expect(entry.enumeratedValues['kind'], contains('other'));
    expect(
      entry.enumeratedValues['library'],
      containsAll(<String>['none', 'other']),
    );
  });

  group('source scan', () {
    final recorded = <String, Set<String>>{};
    // Files holding a `TelemetryEvent(` the name scanner could not read a
    // literal out of. Every one is expected to be a listed wrapper.
    final opaqueConstructions = <String>{};

    final libDir = Directory('lib');
    if (!libDir.existsSync()) {
      throw StateError('run from the package root (flutter test)');
    }
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.endsWith('.g.dart')) continue;
      if (_pipelineFiles.contains(path)) continue;
      final source = entity.readAsStringSync();
      var literalConstructions = 0;
      for (final match in _recordedEvent.allMatches(source)) {
        recorded.putIfAbsent(match.group(1)!, () => <String>{}).add(path);
        if (match.group(0)!.startsWith('TelemetryEvent')) {
          literalConstructions++;
        }
      }
      final total = _anyConstruction.allMatches(source).length;
      if (literalConstructions < total) opaqueConstructions.add(path);
    }

    test('the scan found the instrumentation at all', () {
      // A regex that silently stops matching would turn the rules below into
      // tests that assert nothing, so assert the scanner is alive.
      expect(
        recorded.length,
        greaterThan(10),
        reason:
            'the TelemetryEvent scan matched almost nothing — the call-site '
            'idiom probably changed and this guard has gone blind',
      );
    });

    test('no event name is hidden from the scanner behind an indirection', () {
      // The closure property that makes "every recorded name is in the
      // catalog" mean something: an event constructed from a variable is an
      // event this file cannot see, and so an event that could ship
      // undocumented. Four such indirections exist by design, and all four
      // take the name as a literal from their own callers.
      expect(
        opaqueConstructions,
        _indirectConstructionSites,
        reason:
            'A TelemetryEvent built from a non-literal name is invisible to '
            'the catalog check. Spell the name as a literal at the call site, '
            'or — if a new thin wrapper is genuinely warranted — teach '
            '_recordedEvent to read its callers and list it here.',
      );
    });

    test('every recorded event name is in the catalog', () {
      final names = kLintcruxEventNames;
      final undocumented = [
        for (final entry in recorded.entries)
          if (!names.contains(entry.key))
            '${entry.key}  (${entry.value.join(', ')})',
      ];
      expect(
        undocumented,
        isEmpty,
        reason:
            'An event that is not in kLintcruxEventCatalog is an event nobody '
            'vetted against the never-collect list '
            '(https://edacrux.app/telemetry). Add it to the catalog or '
            'remove the call site:\n${undocumented.join('\n')}',
      );
    });

    test('every open-core catalog entry is still recorded', () {
      final dead = [
        for (final event in catalog)
          if (!_proOnlyEvents.contains(event.name) &&
              !_sharedEvents.contains(event.name) &&
              !recorded.containsKey(event.name))
            event.name,
      ];
      expect(
        dead,
        isEmpty,
        reason:
            'These catalog entries have no call site in this repository. If '
            'the feature was removed, remove the entry; if the event moved to '
            'the Pro overlay, add it to _proOnlyEvents:\n${dead.join('\n')}',
      );
    });

    test('no call site smuggles a rule id or a message into a property', () {
      // The LintCrux-specific never-collect ban, checked at the source rather
      // than only in the catalog: a property whose value expression reaches for
      // a rule id, a message, or a file would pass every grammar check above,
      // because the *shape* of the value is fine and only its provenance is
      // not.
      final banned = RegExp(
        r"'(?:rule|rule_id|message|file|path|violation|query)'\s*:",
      );
      final offenders = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        final source = entity.readAsStringSync();
        // Only look inside a TelemetryEvent property map.
        for (final match in RegExp(
          r'TelemetryEvent\((?:.|\n)*?\)\s*,?\s*\)',
        ).allMatches(source)) {
          if (banned.hasMatch(match.group(0)!)) offenders.add(path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'The suite telemetry policy bans rule names paired with file content and '
            'lint output bodies. These call sites put one of those key names '
            'on a telemetry event:\n${offenders.join('\n')}',
      );
    });
  });
}
