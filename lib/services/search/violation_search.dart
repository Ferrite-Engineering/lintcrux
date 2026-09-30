// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:lintcrux/domain/models/violation.dart';

/// Matching mode for the search dialog.
enum SearchMode {
  /// Plain substring (case-insensitive) over the searchable text.
  substring,

  /// Glob with `*` (any chars) / `?` (one char). Anchored.
  glob,

  /// Java/JavaScript-style regex. Anchored on `^` only if the pattern
  /// explicitly asks.
  regex,
}

/// One match from the search.
class SearchMatch {
  /// Creates a [SearchMatch].
  const SearchMatch({required this.violation, required this.matchedField});

  /// The violation that matched.
  final Violation violation;

  /// Which field caused the match — `'rule'` or `'message'`. Surfaced
  /// in the results list so the user can tell at a glance which side
  /// fired.
  final String matchedField;
}

/// Stateless search service over a violation list.
///
/// Supports substring (default), glob, and regex modes. Each mode
/// is case-insensitive and searches both the engine-namespaced
/// `ruleId` and the engine `message`. Invalid regex patterns produce
/// no matches (the dialog renders the "no matches" empty state rather
/// than throwing).
class ViolationSearch {
  /// Creates a [ViolationSearch].
  const ViolationSearch();

  /// Searches [haystack] for [query] under [mode]. Returns an empty
  /// list when the query is empty.
  List<SearchMatch> search({
    required Iterable<Violation> haystack,
    required String query,
    required SearchMode mode,
  }) {
    if (query.isEmpty) return const <SearchMatch>[];
    final matcher = _matcherFor(query: query, mode: mode);
    if (matcher == null) return const <SearchMatch>[];
    final out = <SearchMatch>[];
    for (final v in haystack) {
      if (matcher(v.ruleId)) {
        out.add(SearchMatch(violation: v, matchedField: 'rule'));
      } else if (matcher(v.message)) {
        out.add(SearchMatch(violation: v, matchedField: 'message'));
      }
    }
    return out;
  }

  /// Returns a predicate-style matcher for [query] under [mode], or
  /// `null` when the query cannot be compiled (invalid regex).
  bool Function(String)? _matcherFor({
    required String query,
    required SearchMode mode,
  }) {
    switch (mode) {
      case SearchMode.substring:
        final needle = query.toLowerCase();
        return (s) => s.toLowerCase().contains(needle);
      case SearchMode.glob:
        final re = _compileGlob(query);
        return re.hasMatch;
      case SearchMode.regex:
        try {
          final re = RegExp(query, caseSensitive: false);
          return re.hasMatch;
        } on FormatException {
          return null;
        }
    }
  }

  /// Compile a simple glob to a case-insensitive [RegExp]. `*` matches
  /// any number of characters; `?` matches one. The pattern is
  /// implicitly anchored so callers don't have to think about `^…$`.
  static RegExp _compileGlob(String pattern) {
    final buf = StringBuffer('^');
    for (final c in pattern.split('')) {
      if (c == '*') {
        buf.write('.*');
      } else if (c == '?') {
        buf.write('.');
      } else if (r'\^$.|+()[]{}'.contains(c)) {
        buf
          ..write(r'\')
          ..write(c);
      } else {
        buf.write(c);
      }
    }
    buf.write(r'$');
    return RegExp(buf.toString(), caseSensitive: false);
  }
}
