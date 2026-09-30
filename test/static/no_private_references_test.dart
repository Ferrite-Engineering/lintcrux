// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// This repository is public. The Pro overlay, the product websites, the
/// update and commerce services and the suite's planning documents are not.
///
/// A reference to any of them is a pointer a reader cannot follow: a path into
/// a repository they cannot clone, a plan section they cannot open, a tracking
/// id from a board they cannot see. Worse, it hides the reasoning — "see the
/// plan" replaces the sentence that should have said why. So nothing tracked
/// here names a private repository or cites a private plan; the reason is
/// stated inline, the Pro overlay is "the Pro overlay", and a suite policy is
/// linked by its public page (`https://edacrux.app/telemetry`,
/// `https://edacrux.app/cxp`, `https://edacrux.app/policy-reference`).
///
/// Scope: every file `git ls-files` reports, except binaries, the
/// `crux-shared` submodule (its own repository runs its own guard), generated
/// l10n output and build output. That covers code, comments, tests, ARB
/// descriptions, workflows, verification guides and the user docs.
///
/// A bare section mark in a code file must name the public document it cites
/// (SARIF, CXP, a document in this repository) on its own line, the line
/// before, or in the table row it sits in. Prose documents (Markdown, NOTICES)
/// number their own sections, so the check does not apply to them.
///
/// The allowlist is an exact file list with a reason per file, and it waives
/// one thing only: the name of a shipped executable that happens to match a
/// private repository's name. A path into that repository is still a finding.
void main() {
  test('no tracked file references a private repository or plan', () {
    final findings = <String>[];
    for (final path in _trackedTextFiles()) {
      final text = _readText(path);
      if (text == null) continue;
      findings.addAll(scanForPrivateReferences(path, text));
    }
    expect(
      findings,
      isEmpty,
      reason:
          'These lines reference a private repository, a private plan or a '
          'tracking id. State the reasoning inline, call the Pro overlay "the '
          'Pro overlay", and link a suite policy by its public page:\n'
          '${findings.join('\n')}',
    );
  });

  test('every allowlisted file exists and still needs its exemption', () {
    for (final entry in _executableNameAllowlist.entries) {
      final file = File(entry.key);
      expect(
        file.existsSync(),
        isTrue,
        reason: '${entry.key} is allowlisted but no longer exists; remove it.',
      );
      expect(
        _executableName.hasMatch(file.readAsStringSync()),
        isTrue,
        reason:
            '${entry.key} is allowlisted for "${entry.value}" but no longer '
            'names a shipped executable; remove the entry.',
      );
    }
  });

  group('the scanner', () {
    const planted = <String, String>{
      'a private repository path': 'see `edacrux/docs/process/guide.md`',
      'a Pro overlay path': 'wired in lintcrux-pro/lib/overrides.dart',
      'a Pro overlay name': 'the `wavecrux-pro` overlay does this',
      'a private service repository': 'the crux-updates Worker validates it',
      'a website repository': 'grep the lintcrux-website repo',
      'the planning repository': 'lives in the private planning repo',
      'a project plan': 'see the LintCrux project plan for details',
      'a suite plan section': 'suite plan §9.3 bans it',
      'a charter file': 'per ui-consistency-charter.md',
      'a ruling': 'moved per Ruling A #2',
      'a plan phase': 'lands in Phase 1.6',
      'a work-stream id': 'the WS4 stress corpus',
      'a lettered work-stream id': 'the WS-E consumer',
      'a prompt id': 'desktop import (P25)',
      'an audit finding id': 'found as F-21',
      'a beta bug id': 'reported as beta bug L4',
      'a beta bug sub-id': 'the L4(c) shape',
      'a campaign path': 'recorded under campaigns/2026-06',
      'a robustness plan section': 'the contract (robustness §2)',
      'a bare plan section in code': 'counts the §9.9.1 event',
    };

    for (final entry in planted.entries) {
      test('flags ${entry.key}', () {
        expect(
          scanForPrivateReferences('lib/planted.dart', '// ${entry.value}\n'),
          isNotEmpty,
          reason: 'planted: ${entry.value}',
        );
      });
    }

    test('passes public references', () {
      const clean = '''
// The CXP spec (https://edacrux.app/cxp#sec-4-2) and CXP §4.2 define it.
// `crux-shared/packages/crux_cxp` and `wavecrux/docs/ARCHITECTURE.md` §6.4.
// SARIF §3.27.23 maps onto the waiver; see the Pro overlay for the store.
// Settings > Engines, key F5, `edacrux-edu-packs/packs/` fixtures.
''';
      expect(scanForPrivateReferences('lib/clean.dart', clean), isEmpty);
    });

    test('a prose document may number its own sections', () {
      expect(
        scanForPrivateReferences('docs/guide.md', 'See §6.5.2 below.\n') +
            scanForPrivateReferences('NOTICES', 'See §1.2.\n'),
        isEmpty,
      );
    });

    test('the executable allowlist waives the name, not a path', () {
      const file = 'docs-site/docs/baselines.md';
      expect(
        scanForPrivateReferences(file, 'Run `lintcrux-pro baseline set`.\n'),
        isEmpty,
      );
      expect(
        scanForPrivateReferences(file, 'See lintcrux-pro/lib/main.dart.\n'),
        isNotEmpty,
      );
      expect(
        scanForPrivateReferences('lib/x.dart', '// run lintcrux-pro\n'),
        isNotEmpty,
      );
    });
  });
}

/// Returns one `path:line: rule — text` finding per offending line.
List<String> scanForPrivateReferences(String path, String text) {
  final findings = <String>[];
  final lines = const LineSplitter().convert(text);
  final isCode = _codeExtensions.any(path.endsWith);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final rule in _rules) {
      if (!rule.pattern.hasMatch(line)) continue;
      if (rule.executableNameRule && _isAllowedExecutableName(path, line)) {
        continue;
      }
      if (rule.exemptFiles.contains(path)) continue;
      findings.add('$path:${i + 1}: ${rule.name} — ${line.trim()}');
    }
    if (isCode && _bareSection.hasMatch(line)) {
      final previous = i > 0 ? lines[i - 1] : '';
      final named =
          _publicSectionSource.hasMatch(line) ||
          _publicSectionSource.hasMatch(previous) ||
          line.contains('|');
      if (!named) {
        findings.add(
          '$path:${i + 1}: section mark with no public document — '
          '${line.trim()}',
        );
      }
    }
  }
  return findings;
}

class _Rule {
  const _Rule(
    this.name,
    this.pattern, {
    this.executableNameRule = false,
    this.exemptFiles = const <String>{},
  });

  final String name;
  final RegExp pattern;

  /// Whether a match may be a shipped executable's name (see
  /// [_executableNameAllowlist]).
  final bool executableNameRule;

  /// Files that define the very pattern this rule matches, and why.
  final Set<String> exemptFiles;
}

final _rules = <_Rule>[
  _Rule(
    'private repository path',
    RegExp(r'(?<![\w.-])edacrux/|`edacrux` repo|\bedacrux repo\b'),
  ),
  _Rule(
    'Pro overlay repository',
    RegExp(r'\b(?:wavecrux|netcrux|lintcrux|simcrux)-pro\b'),
    executableNameRule: true,
  ),
  // The beta repos close at the open-core flip (L4): they are the beta
  // cohort's public record, and archived-then-private is a 404 to anyone
  // who follows a link into one.
  _Rule(
    'beta-period repository',
    RegExp(
      r'\b(?:wavecrux|netcrux|lintcrux|simcrux)-beta\b',
      caseSensitive: false,
    ),
  ),
  _Rule(
    'private repository',
    RegExp(
      r'\b(?:crux-updates|crux-commerce|pulsecrux|wavecrux-updates|'
      r'vcd_parser|anneal)\b|\b[a-z]+-website\b|'
      r'\bprivate (?:planning |docs )?repo\b|\bplanning repo\b|'
      r'\bthe docs repo\b',
      caseSensitive: false,
    ),
  ),
  _Rule(
    'private plan',
    RegExp(
      r'\b(?:project|suite|strategic|ecosystem|integration|robustness|'
      r'LintCrux|WaveCrux|NetCrux|SimCrux) plan\b|-project-plan\b|'
      'robustness-and-performance-plan|ecosystem-plan|'
      'commercial-launch-plan|RISCV_ECOSYSTEM_PLAN|ui-consistency-charter|'
      r'consistency-rulings|CONSISTENCY_RULINGS|\bcharter §|'
      r'execution[- ]prompt|close-out\.md',
      caseSensitive: false,
    ),
    // The comment-hygiene guard's own pattern list spells out a phrase this
    // rule bans; the pattern is data there, not a citation.
    exemptFiles: const {'test/static/comment_hygiene_test.dart'},
  ),
  _Rule('private ruling', RegExp(r'\bRuling [A-Z]\b')),
  _Rule(
    'plan phase',
    RegExp(
      r'\bPhase \d+(?:\.\d+)?\b|§Phase|\bSection \d+\.\d+|'
      r'\bsub-phases? \d|\bstep F\d+\b',
    ),
  ),
  _Rule(
    'tracking id',
    RegExp(
      r'\bWS-?(?:\d{1,2}|[A-Z])\b|(?<![\w-])P\d{1,2}(?![\w-])|\bF-\d{2}\b|'
      r'\bCS\d{1,2}\b|\bR-CS\d*\b|\bPrompt \d+\b|\bIssue-\d+\b',
    ),
  ),
  _Rule(
    'beta bug id',
    RegExp(r'\b[Bb]eta(?: bug)?[- ]?\s*[A-Z]\d\b|\bL\d\([a-z]\)|\bW2/S1\b'),
  ),
  _Rule(
    'campaign',
    RegExp(
      r'campaigns?/|\bcampaign \d{4}-\d{2}|\d{4}-\d{2}-[a-z0-9-]*phase\d|'
      r'quality backlog|consistency pass|\baudit [A-Z]-?\d',
      caseSensitive: false,
    ),
  ),
  _Rule(
    'private plan section',
    RegExp(
      r'(?:robustness|audit|charter|telemetry-guide|plan)(?:\.md)?`?\s*'
      r'(?:edge case\s*)?§',
      caseSensitive: false,
    ),
  ),
];

final _bareSection = RegExp(r'§\s*\d');

/// Files whose section marks can only point outside themselves. Prose
/// documents (Markdown, NOTICES) number their own sections.
const _codeExtensions = <String>[
  '.dart', '.yaml', '.yml', '.sh', '.py', '.swift', '.cpp', '.cc', '.h', //
  '.json', '.arb', '.js', '.ts', '.v', '.sv', '.vhd', '.toml', '.cmake',
];

/// Documents a section mark in code may cite.
final _publicSectionSource = RegExp(
  'ARCHITECTURE|VERIFICATION_(?:GUIDE|CHECKLIST)|[Vv]erification [Gg]uide|'
  r'\bguide\b|\bchecklist\b|SARIF|CXP|edacrux\.app/cxp|Apache|MPL|NOTICES|'
  r'\bEAR\b|LRM|IEEE|RFC|README|CONTRIBUTING',
);

/// Shipped executables whose names match a Pro overlay repository's.
final _executableName = RegExp(r'\b(?:lintcrux|simcrux)-pro\b(?!/)');

/// Exact files allowed to name a shipped executable, with the reason.
const _executableNameAllowlist = <String, String>{
  'docs-site/docs/administration.md':
      'the `lintcrux-pro` CLI enforces the Enterprise CI gate threshold',
  'docs-site/docs/baselines.md':
      'the `lintcrux-pro baseline` commands set and clear a baseline',
  'docs-site/docs/cdc.md': 'the `lintcrux-pro` CLI reads cdc.yaml',
  'docs-site/docs/cli/invocation.md':
      'the CLI reference documents the `lintcrux-pro` exit codes',
  'docs-site/docs/cookbook-baseline-ci.md':
      'the CI recipe runs `lintcrux-pro baseline` and `push-trends`',
  'docs-site/docs/cookbook-track-regressions.md':
      'the recipe runs `lintcrux-pro push-trends`',
  'docs-site/docs/cookbook/ci-integration.md':
      'the CI recipe runs `lintcrux-pro baseline` and `push-trends`',
  'docs-site/docs/exports-and-ci.md':
      'the exit-code table covers `lintcrux-pro` and `push-trends`',
  'docs-site/docs/index.md': 'the tier summary names the Pro command line',
  'docs-site/docs/team-database.md':
      'the page runs `lintcrux-pro push-trends` and compares '
      '`simcrux-pro push-results` exit codes',
  'docs-site/docs/trends.md': 'the page links `lintcrux-pro push-trends`',
};

/// Whether every Pro-repository-shaped token on [line] is an allowlisted
/// executable name: with the executable names removed, nothing matches.
bool _isAllowedExecutableName(String path, String line) =>
    _executableNameAllowlist.containsKey(path) &&
    !_proRepositoryName.hasMatch(line.replaceAll(_executableName, ''));

final _proRepositoryName = RegExp(
  r'\b(?:wavecrux|netcrux|lintcrux|simcrux)-pro\b',
);

/// File extensions that are never text.
const _binaryExtensions = <String>{
  '.png', '.jpg', '.jpeg', '.gif', '.ico', '.icns', '.webp', '.pdf', //
  '.ttf', '.otf', '.woff', '.woff2', '.zip', '.gz', '.zst', '.riv', //
  '.db', '.sqlite', '.fst', '.lock',
};

/// Tracked paths that are not this repository's own prose.
const _skippedPrefixes = <String>[
  'crux-shared/',
  'lib/l10n/generated/',
  'build/',
  'docs-site/site/',
];

const _selfPath = 'test/static/no_private_references_test.dart';

Iterable<String> _trackedTextFiles() {
  final result = Process.runSync('git', <String>['ls-files', '-z']);
  if (result.exitCode != 0) {
    fail('git ls-files failed (${result.exitCode}): ${result.stderr}');
  }
  return (result.stdout as String)
      .split('\x00')
      .where((path) => path.isNotEmpty)
      .where((path) => path != 'crux-shared' && path != _selfPath)
      .where((path) => !_skippedPrefixes.any(path.startsWith))
      .where((path) {
        final dot = path.lastIndexOf('.');
        return dot < 0 || !_binaryExtensions.contains(path.substring(dot));
      });
}

/// The file's text, or null when it is missing or not UTF-8 text.
String? _readText(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final bytes = file.readAsBytesSync();
  if (bytes.contains(0)) return null;
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}
