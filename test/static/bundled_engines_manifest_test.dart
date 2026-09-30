// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards `tool/bundled_engines.yaml` against unfetchable version pins.
///
/// Why this exists: the Verible entry shipped as
/// `v0.0-3795-g6b8c10b1` with an N-1 of `v0.0-3780-g28e84a0d`. Neither
/// tag exists upstream — the real release is `v0.0-3795-gf4d72375`, and
/// upstream never cut a `3780` at all. Every download URL the manifest
/// generated for Verible returned 404, and nothing noticed, because:
///
///  * `.github/workflows/bundled-engines.yml` is `workflow_dispatch`
///    only. It never ran on a push, a PR, or the nightly.
///  * Its Verible macOS and Windows rows fall through to the "no
///    published URL yet" skip notice and never fetch anything at all.
///  * Its Verible *linux* row fetched with `curl -L` (no `--fail`) and
///    extracted with `tar ... || true`, so a 404 HTML body was written
///    to disk, extraction failed silently, and the step still exited 0.
///  * `nminus1Version` is consumed only as documentation. The reader,
///    `test/fixtures/cross_version_engine_test.dart`, resolves the N-1
///    binary from `*_NMINUS1_BIN` env vars and skips when they are
///    unset — it never turns the manifest field into a URL.
///
/// So the pin was load-bearing for release packaging but was never once
/// dereferenced by an automated check. These tests assert, offline, the
/// properties that would have caught it: tag *shape*, N-1 *ordering*,
/// URL *well-formedness*, and — for Verible, whose tags embed a commit
/// hash that cannot be derived from the version number — membership in
/// a checked-in list of tags verified to exist upstream.
///
/// The same rot was then found in three more rows, and fixing it needed
/// two different answers, so the guards below cover both:
///
///  * Verilator publishes **no release assets at all** — the repo has
///    only tags. Its three templates named archives that have never
///    existed. The manifest now declares `install: package-manager` and
///    writes down no URL, and [_engineDeclaresExactlyOneSource] keeps a
///    fictional one from being reintroduced.
///  * Slang and GHDL *do* publish assets; their pins simply named
///    releases that carry none (slang) or used a naming scheme upstream
///    never adopted (ghdl). Both were corrected, and both are now in
///    the live sweep.
///
/// A live network check of every generated URL also exists below, gated
/// behind `LINTCRUX_CHECK_ENGINE_URLS=1` so the default suite stays
/// hermetic. CI runs it as the `preflight` job in
/// `.github/workflows/bundled-engines.yml`. It covers **every** declared
/// template by default; anything left out must appear in
/// [_liveCheckExclusions] with a reason, and that map is itself
/// asserted against the manifest so it cannot go stale.
void main() {
  final manifest = File('${_repoRoot().path}/tool/bundled_engines.yaml');

  late String manifestText;
  late List<_Engine> engines;

  setUpAll(() {
    expect(
      manifest.existsSync(),
      isTrue,
      reason: 'tool/bundled_engines.yaml must exist at the package root',
    );
    manifestText = manifest.readAsStringSync();
    engines = _parseEngines(manifestText);
  });

  group('bundled engine manifest', () {
    test('declares the schema version these tests understand', () {
      final match = RegExp(
        r'^schemaVersion:\s*(\d+)\s*$',
        multiLine: true,
      ).firstMatch(manifestText);
      expect(
        match,
        isNotNull,
        reason: 'the manifest must declare a top-level `schemaVersion`',
      );
      expect(
        int.parse(match!.group(1)!),
        _supportedSchemaVersion,
        reason:
            'The manifest schema changed. Update the parser and the '
            'guards in this file to match, then bump '
            '`_supportedSchemaVersion`.',
      );
    });

    test('declares every engine the resolver and CI matrix expect', () {
      expect(
        engines.map((e) => e.id).toSet(),
        containsAll(<String>{
          'verilator',
          'verible',
          'slang',
          'ghdl',
          'svlint',
        }),
        reason:
            'An engine disappeared from the manifest. The CI matrix in '
            '.github/workflows/bundled-engines.yml and '
            'BundledBinaryResolver both key off these ids.',
      );
    });

    test('every engine pins a version and a distinct N-1 version', () {
      for (final engine in engines) {
        expect(
          engine.version,
          isNotEmpty,
          reason: '${engine.id}: `version` must not be empty',
        );
        expect(
          engine.nminus1Version,
          isNotEmpty,
          reason: '${engine.id}: `nminus1Version` must not be empty',
        );
        expect(
          engine.nminus1Version,
          isNot(equals(engine.version)),
          reason:
              '${engine.id}: `nminus1Version` equals `version`, so the '
              'cross-version harness would compare a build against '
              'itself and never detect a behavior change.',
        );
      }
    });

    test('every engine declares exactly one of `sources` / `install`', () {
      // Verilator's three templates were fiction: upstream publishes no
      // release assets whatsoever (`gh api repos/verilator/verilator/
      // releases` returns `[]`), so no download URL for it can ever
      // resolve. The manifest says `install: package-manager` instead of
      // writing down a plausible-looking 404. This guard keeps the two
      // states mutually exclusive so nobody "helpfully" re-adds a URL
      // next to the declaration that says one does not exist — and so
      // an engine can never end up declaring neither.
      for (final engine in engines) {
        final hasSources = engine.sources != null;
        final hasInstall = engine.install != null;

        expect(
          hasSources || hasInstall,
          isTrue,
          reason:
              '${engine.id}: declares neither `sources` nor `install`, so '
              'nothing says how the binary is obtained.',
        );
        expect(
          hasSources && hasInstall,
          isFalse,
          reason:
              '${engine.id}: declares both `sources` and `install`. '
              '`install: ${engine.install}` means upstream publishes no '
              'downloadable binary at all, which contradicts having a '
              'download URL. Pick one.',
        );

        if (hasInstall) {
          expect(
            _knownInstallModes,
            contains(engine.install),
            reason:
                '${engine.id}: unknown `install` mode '
                '"${engine.install}". Known modes: '
                '${_knownInstallModes.join(', ')}.',
          );
        } else {
          expect(
            engine.sources!.values.any((v) => v != null),
            isTrue,
            reason:
                '${engine.id}: declares a `sources` block in which every '
                'platform is null. If no platform has a download, say '
                '`install: package-manager` instead.',
          );
        }
      }
    });

    test('every pinned version matches its upstream tag shape', () {
      // Keyed by engine id. These encode the shape of the upstream
      // release tag, which is what gets substituted into the download
      // URL — a pin in the wrong shape cannot resolve.
      const shapes = <String, String>{
        // Verible: v0.0-<commit-count>-g<8 hex chars>.
        'verible': r'^v0\.0-\d+-g[0-9a-f]{8}$',
        // Verilator: <major>.<minor>, e.g. 5.024.
        'verilator': r'^\d+\.\d+$',
        // Slang: <major>.<minor>.
        'slang': r'^\d+\.\d+$',
        // GHDL: <major>.<minor>.<patch>.
        'ghdl': r'^\d+\.\d+\.\d+$',
        // Svlint: <major>.<minor>.<patch>.
        'svlint': r'^\d+\.\d+\.\d+$',
      };

      for (final engine in engines) {
        final pattern = shapes[engine.id];
        if (pattern == null) continue;
        final regex = RegExp(pattern);
        for (final entry in <String, String>{
          'version': engine.version,
          'nminus1Version': engine.nminus1Version,
        }.entries) {
          expect(
            regex.hasMatch(entry.value),
            isTrue,
            reason:
                '${engine.id}: `${entry.key}` is "${entry.value}", which '
                'does not match the upstream tag shape $pattern. The '
                'value is substituted verbatim into the download URL, '
                'so a malformed pin 404s at fetch time.',
          );
        }
      }
    });

    test('Verible pins name releases verified to exist upstream', () {
      // Verible tags embed the upstream commit hash, which is NOT
      // derivable from the commit count — `v0.0-3795-g6b8c10b1` looks
      // perfectly well-formed and does not exist. The only offline
      // defense is to check the pin against tags a human confirmed.
      //
      // Regenerate this list when bumping the pin:
      //   gh api repos/chipsalliance/verible/releases --paginate \
      //     --jq '.[].tag_name'
      //
      // Copy the tag from that output verbatim. Do not hand-edit the
      // hash, and do not assume a commit count exists just because it
      // falls between two that do — upstream skips numbers freely
      // (3773 → 3791 → 3793 → 3795 → 3798, with no 3780).
      const verifiedVeribleTags = <String>{
        'v0.0-3752-g8b64887e',
        'v0.0-3754-g17e909b0',
        'v0.0-3756-gda9a0f8c',
        'v0.0-3769-gbfb6c2c1',
        'v0.0-3773-g14ca40e1',
        'v0.0-3791-g88bf4fb8',
        'v0.0-3793-g27720255',
        'v0.0-3795-gf4d72375',
        'v0.0-3798-ga602f072',
        'v0.0-3802-gd7bc1590',
        'v0.0-3804-g0657a400',
        'v0.0-3808-gd0f6c1d1',
      };

      final verible = engines.firstWhere((e) => e.id == 'verible');
      for (final entry in <String, String>{
        'version': verible.version,
        'nminus1Version': verible.nminus1Version,
      }.entries) {
        expect(
          verifiedVeribleTags,
          contains(entry.value),
          reason:
              'verible: `${entry.key}` is "${entry.value}", which is not '
              'in the list of upstream tags this repo has verified. If '
              'you are bumping the pin, add the new tag to '
              '`verifiedVeribleTags` in this test — copied verbatim from '
              '`gh api repos/chipsalliance/verible/releases --paginate '
              "--jq '.[].tag_name'`. If you did not expect this, the pin "
              'is wrong and its download URLs will 404.',
        );
      }
    });

    test('Verible N-1 is genuinely older than the pinned version', () {
      final verible = engines.firstWhere((e) => e.id == 'verible');
      final current = _veribleCommitCount(verible.version);
      final previous = _veribleCommitCount(verible.nminus1Version);
      expect(
        previous,
        lessThan(current),
        reason:
            'verible: `nminus1Version` ($previous commits) must be older '
            'than `version` ($current commits). The cross-version '
            'harness treats N-1 as the *older* build when diffing rule '
            'output; inverting them inverts every regression verdict.',
      );
    });

    test('every source template substitutes into a well-formed URL', () {
      for (final engine in engines) {
        for (final source
            in (engine.sources ?? const <String, String?>{}).entries) {
          final template = source.value;
          if (template == null) continue; // no upstream asset; see manifest

          expect(
            template.contains(r'${version}'),
            isTrue,
            reason:
                '${engine.id}/${source.key}: the source template does '
                r'not interpolate ${version}, so bumping the pin would '
                'silently keep fetching the old binary.',
          );

          for (final entry in <String, String>{
            'version': engine.version,
            'nminus1Version': engine.nminus1Version,
          }.entries) {
            final url = template.replaceAll(r'${version}', entry.value);

            expect(
              url.contains(r'${'),
              isFalse,
              reason:
                  '${engine.id}/${source.key}: unresolved placeholder '
                  'left in "$url". Only \${version} is substituted at '
                  'fetch time.',
            );

            final uri = Uri.tryParse(url);
            expect(
              uri,
              isNotNull,
              reason:
                  '${engine.id}/${source.key}: "$url" is not a parseable '
                  'URI for ${entry.key}.',
            );
            expect(
              uri!.scheme,
              'https',
              reason:
                  '${engine.id}/${source.key}: engine binaries must be '
                  'fetched over https, got "${uri.scheme}" for '
                  '${entry.key}.',
            );
            expect(
              uri.host,
              isNotEmpty,
              reason:
                  '${engine.id}/${source.key}: "$url" has no host for '
                  '${entry.key}.',
            );
            expect(
              uri.pathSegments.last,
              isNotEmpty,
              reason:
                  '${engine.id}/${source.key}: "$url" ends in a slash, '
                  'so it names a directory rather than an archive for '
                  '${entry.key}.',
            );
          }
        }
      }
    });

    // The heart of the regression. Broken templates survived because
    // *nothing asserted anything about them*: the live sweep was scoped
    // to an allow-list, and three engines sat outside it indefinitely.
    // The sweep is now deny-list shaped — it covers everything by
    // default — and these two tests make the deny-list answer for
    // itself.
    test('every declared template is live-checked or explicitly excused', () {
      final unexcused = <String>[];
      var checked = 0;

      for (final engine in engines) {
        if (engine.sources == null) continue;
        if (!engine.sources!.values.any((v) => v != null)) continue;
        for (final pin in _pinFields) {
          final reason = _liveCheckExclusion(engine.id, pin);
          if (reason == null) {
            checked++;
            continue;
          }
          if (reason.trim().isEmpty) {
            unexcused.add('${engine.id}/$pin');
          }
        }
      }

      expect(
        unexcused,
        isEmpty,
        reason:
            'These templates are excluded from the live URL sweep with '
            'an empty reason:\n${unexcused.join('\n')}\n'
            'An exclusion without a stated reason is how the previous '
            'three broken rows stayed broken. Say why, truthfully, in '
            '`_liveCheckExclusions`.',
      );
      expect(
        checked,
        greaterThan(0),
        reason:
            'The live sweep would check nothing at all — every declared '
            'template is excluded. That is the failure mode this file '
            'exists to prevent.',
      );
    });

    test('no exclusion outlives the template it excuses', () {
      final byId = {for (final e in engines) e.id: e};

      for (final key in _liveCheckExclusions.keys) {
        final parts = key.split('/');
        expect(
          parts.length,
          anyOf(1, 2),
          reason:
              '`_liveCheckExclusions` key "$key" must be "<engineId>" or '
              '"<engineId>/<pinField>".',
        );

        final engine = byId[parts.first];
        expect(
          engine,
          isNotNull,
          reason:
              '`_liveCheckExclusions` excuses "$key", but no engine with '
              'id "${parts.first}" is in the manifest. Delete the stale '
              'entry.',
        );
        expect(
          engine!.sources?.values.any((v) => v != null) ?? false,
          isTrue,
          reason:
              '`_liveCheckExclusions` excuses "$key", but '
              '"${engine.id}" declares no download URL at all, so there '
              'is nothing to exclude. Delete the stale entry.',
        );
        if (parts.length == 2) {
          expect(
            _pinFields,
            contains(parts[1]),
            reason:
                '`_liveCheckExclusions` key "$key" names pin field '
                '"${parts[1]}", which is not one of '
                '${_pinFields.join(', ')}.',
          );
        }
      }
    });

    test('CI can extract every pinned version from the manifest', () {
      // `.github/workflows/bundled-engines.yml` reads the pin out of
      // this file with shell text processing, keyed on the `^    version:`
      // line inside each `- id:` block. That extraction has already
      // silently returned an empty string once, when a comment was added
      // between `- id: verible` and its `version:` line and the
      // workflow's `grep -A 1` walked straight past it. An empty version
      // interpolates into `.../download/v/...`, which 404s.
      //
      // This mirrors the workflow's rule in Dart so a manifest edit that
      // breaks the extraction fails here, offline, instead of in a
      // manually dispatched workflow nobody runs.
      for (final engine in engines) {
        expect(
          _extractVersionAsCiDoes(manifestText, engine.id),
          engine.version,
          reason:
              '${engine.id}: the version the CI workflow would extract '
              'does not match the pinned `version`. The workflow keys on '
              'the first `    version:` line after `  - id: ${engine.id}` '
              'and before the next `  - id:`; keep the manifest in that '
              'shape.',
        );
      }
    });
  });

  // Live check. Opt-in so the default suite needs no network; CI runs it
  // via the `preflight` job in .github/workflows/bundled-engines.yml.
  group(
    'bundled engine URLs resolve upstream',
    skip: Platform.environment['LINTCRUX_CHECK_ENGINE_URLS'] == '1'
        ? false
        : 'set LINTCRUX_CHECK_ENGINE_URLS=1 to check URLs over the network',
    () {
      test(
        'every generated download URL resolves',
        () async {
          final failures = <String>[];
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 20);

          try {
            for (final engine in engines) {
              final sources = engine.sources;
              if (sources == null) continue; // installed, never downloaded
              for (final pin in _pinFields) {
                if (_liveCheckExclusion(engine.id, pin) != null) continue;
                final version = pin == 'version'
                    ? engine.version
                    : engine.nminus1Version;
                for (final source in sources.entries) {
                  final template = source.value;
                  if (template == null) continue;
                  final url = template.replaceAll(r'${version}', version);
                  final status = await _headStatus(client, url);
                  // GitHub answers a valid release asset with a 302 to the
                  // CDN; 200 covers hosts that serve the bytes directly.
                  final ok = status == 200 || (status >= 300 && status < 400);
                  if (!ok) {
                    failures.add(
                      '${engine.id}/${source.key} ($pin): HTTP $status $url',
                    );
                  }
                }
              }
            }
          } finally {
            client.close(force: true);
          }

          expect(
            failures,
            isEmpty,
            reason:
                'These pinned engine binaries are not fetchable:\n'
                '${failures.join('\n')}',
          );
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );
    },
  );
}

/// The schema version of `tool/bundled_engines.yaml` this file parses.
const _supportedSchemaVersion = 2;

/// Accepted values of the manifest's `install` key.
const _knownInstallModes = <String>{'package-manager'};

/// The manifest fields that get substituted into a URL template.
const _pinFields = <String>['version', 'nminus1Version'];

/// Templates deliberately left out of the live URL sweep, and why.
///
/// The sweep covers **every** declared template by default — that
/// inversion is the point. The predecessor of this map was an allow-list
/// naming the two engines that worked, which let `verilator`, `slang`
/// and `ghdl` sit broken and unasserted. Anything named here is a
/// standing claim that a URL cannot be made to resolve, and the tests
/// above check that each entry still corresponds to a real declared
/// template.
///
/// Keys are `<engineId>` or `<engineId>/<pinField>`. Values must be
/// true. If a reason stops being true, delete the entry — do not soften
/// it.
///
/// Note what is *not* here any more:
///  * `verilator` — no longer declares any URL. Upstream publishes zero
///    release assets, so the manifest says `install: package-manager`
///    and there is nothing to sweep.
///  * `ghdl` — templates corrected to upstream's actual 5.x/6.x asset
///    names; both pins now resolve on linux and windows.
///  * `slang` — pin corrected to the first release that carries binary
///    assets; `version` now resolves on linux and windows.
const _liveCheckExclusions = <String, String>{
  'slang/nminus1Version':
      'v10.0 carries no release assets: upstream cut its first binaries '
      'at v11.0, so every slang tag before it is source-only.',
};

/// The exclusion reason for [engineId]/[pinField], or `null` when the
/// pair is live-checked. An engine-wide key excuses both pin fields.
String? _liveCheckExclusion(String engineId, String pinField) =>
    _liveCheckExclusions[engineId] ??
    _liveCheckExclusions['$engineId/$pinField'];

/// Mirrors the version extraction in
/// `.github/workflows/bundled-engines.yml`: the first `    version:`
/// line inside the `  - id: <engineId>` block.
String? _extractVersionAsCiDoes(String text, String engineId) {
  var inBlock = false;
  for (final raw in const LineSplitter().convert(text)) {
    if (RegExp('^  - id: $engineId\\s*\$').hasMatch(raw)) {
      inBlock = true;
      continue;
    }
    if (!inBlock) continue;
    if (RegExp('^  - id: ').hasMatch(raw)) return null;
    final match = RegExp(r'^    version:\s*(.+)$').firstMatch(raw);
    if (match != null) return _scalar(match.group(1)!);
  }
  return null;
}

Future<int> _headStatus(HttpClient client, String url) async {
  try {
    final request = await client.headUrl(Uri.parse(url));
    request.followRedirects = false;
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } on Exception {
    return -1;
  }
}

int _veribleCommitCount(String tag) {
  final match = RegExp(r'^v0\.0-(\d+)-g[0-9a-f]{8}$').firstMatch(tag);
  if (match == null) {
    fail('"$tag" is not a Verible release tag of the form v0.0-<n>-g<sha>');
  }
  return int.parse(match.group(1)!);
}

/// Minimal reader for the manifest's fixed two-level shape. Deliberately
/// dependency-free: `yaml` is only a transitive dependency here, and the
/// CI workflow reads this same file with shell text processing, so the
/// test stays aligned with how the file is actually consumed.
List<_Engine> _parseEngines(String text) {
  final engines = <_Engine>[];

  String? id;
  String? version;
  String? nminus1Version;
  String? install;
  Map<String, String?>? sources;
  var inSources = false;

  void flush() {
    if (id == null) return;
    engines.add(
      _Engine(
        id: id,
        version: version ?? '',
        nminus1Version: nminus1Version ?? '',
        install: install,
        sources: sources == null
            ? null
            : Map<String, String?>.unmodifiable(sources),
      ),
    );
  }

  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trimRight();
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;

    final idMatch = RegExp(r'^  - id:\s*(\S+)').firstMatch(line);
    if (idMatch != null) {
      flush();
      id = idMatch.group(1);
      version = null;
      nminus1Version = null;
      install = null;
      sources = null;
      inSources = false;
      continue;
    }
    if (id == null) continue;

    final nMatch = RegExp(r'^    nminus1Version:\s*(.+)$').firstMatch(line);
    if (nMatch != null) {
      nminus1Version = _scalar(nMatch.group(1)!);
      inSources = false;
      continue;
    }

    final vMatch = RegExp(r'^    version:\s*(.+)$').firstMatch(line);
    if (vMatch != null) {
      version = _scalar(vMatch.group(1)!);
      inSources = false;
      continue;
    }

    final iMatch = RegExp(r'^    install:\s*(.+)$').firstMatch(line);
    if (iMatch != null) {
      install = _scalar(iMatch.group(1)!);
      inSources = false;
      continue;
    }

    if (RegExp(r'^    sources:\s*$').hasMatch(line)) {
      inSources = true;
      sources = <String, String?>{};
      continue;
    }

    if (inSources) {
      final sMatch = RegExp(
        r'^      ([A-Za-z0-9_-]+):\s*(.+)$',
      ).firstMatch(line);
      if (sMatch != null) {
        final value = _scalar(sMatch.group(2)!);
        sources![sMatch.group(1)!] = value == 'null' ? null : value;
      }
    }
  }
  flush();

  return engines;
}

/// Strips an inline comment and surrounding quotes from a YAML scalar.
String _scalar(String raw) {
  var value = raw.trim();
  if (value.startsWith('"')) {
    final end = value.indexOf('"', 1);
    if (end > 0) return value.substring(1, end);
  }
  final hash = value.indexOf(' #');
  if (hash >= 0) value = value.substring(0, hash).trim();
  return value;
}

class _Engine {
  const _Engine({
    required this.id,
    required this.version,
    required this.nminus1Version,
    required this.install,
    required this.sources,
  });

  final String id;
  final String version;
  final String nminus1Version;

  /// How the binary is obtained when upstream publishes no downloadable
  /// asset. Mutually exclusive with [sources]; `null` when [sources] is
  /// declared.
  final String? install;

  /// Per-platform download URL templates, or `null` when the engine
  /// declares no downloads at all. An individual platform maps to `null`
  /// when upstream ships no asset for it.
  final Map<String, String?>? sources;
}

/// Walks up from the test's working directory to the package root (the
/// directory holding pubspec.yaml).
Directory _repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) return Directory.current;
    dir = parent;
  }
  return dir;
}
