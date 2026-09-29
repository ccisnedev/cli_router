// Differential test for issue #8, rule 2: every invocation the existing
// suite expects to be accepted under OptionOrdering.strict (cli_router
// 0.2.0's own grammar) must resolve identically under OptionOrdering.permute
// (resolve()'s new default). This holds by construction: an accepted
// invocation, by definition, never has an option token after an operand, so
// normalization is a true no-op on it (see _normalizeForPermute's dartdoc).
// This file checks that guarantee across a representative corpus, not just
// a hand picked example.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A structural snapshot of a [CliResolution], compared field by field so a
/// failure names exactly what differs, instead of two opaque object
/// identities.
class _Snapshot {
  _Snapshot(CliResolution r)
    : routePattern = r.route.pattern,
      params = Map.of(r.params),
      rest = List.of(r.rest),
      options = [
        for (final o in r.options)
          (
            name: o.spec.name,
            abbr: o.spec.abbr,
            written: o.written,
            argvIndex: o.argvIndex,
            value: o.value,
            attached: o.attached,
          ),
      ];

  final String routePattern;
  final Map<String, String> params;
  final List<String> rest;
  final List<
    ({
      String name,
      String? abbr,
      String written,
      int argvIndex,
      String? value,
      bool attached,
    })
  >
  options;

  @override
  String toString() =>
      'route=$routePattern params=$params rest=$rest options=$options';

  @override
  bool operator ==(Object other) =>
      other is _Snapshot &&
      routePattern == other.routePattern &&
      _mapEquals(params, other.params) &&
      _listEquals(rest, other.rest) &&
      _listEquals(options, other.options);

  @override
  int get hashCode => Object.hash(routePattern, params.length, rest.length);
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

bool _listEquals(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Asserts [args] is accepted by [router] under both orderings, and that the
/// two resolutions are identical.
void _expectSameAcceptance(CliRouter router, List<String> args) {
  final strict = router.resolve(args, ordering: OptionOrdering.strict);
  expect(
    strict,
    isA<CliResolution>(),
    reason: 'for $args, strict mode was expected to accept but got $strict',
  );
  final permuted = router.resolve(args);
  expect(
    permuted,
    isA<CliResolution>(),
    reason: 'for $args, permute mode was expected to accept but got $permuted',
  );
  final strictSnapshot = _Snapshot(strict as CliResolution);
  final permutedSnapshot = _Snapshot(permuted as CliResolution);
  expect(
    permutedSnapshot,
    equals(strictSnapshot),
    reason: 'for $args, permute mode diverged from strict mode',
  );
}

void main() {
  group('calculatrix router: every previously accepted invocation resolves '
      'identically in permute mode', () {
    final accepted = <List<String>>[
      [''],
      ['version'],
      ['version', '--json'],
      ['doctor'],
      ['upgrade', '--plan'],
      ['upgrade', '--apply', '--plan'],
      ['help'],
      ['help', 'math'],
      ['help', '--json', 'math'],
      ['eval', 'rpn'],
      ['eval', 'rpn', '1 2 +'],
      ['eval', 'rpn', '--json', '1 2 +'],
      ['eval', 'rpn', '--file', 'a.rpn'],
      ['eval', 'rpn', '-f', 'a.rpn'],
      ['eval', 'rpn', '--stdin'],
      ['eval', 'rpn', '-q', '-h'],
      ['eval', 'rpn', '--', '--help'],
      ['eval', 'infix', '2 + 2'],
      ['eval', 'infix', '--stdin', '--json'],
      ['commands', 'list'],
      ['commands', 'list', '--category', 'math'],
      ['commands', 'show', 'power'],
      ['commands', 'show', '--json', 'power'],
      ['commands', 'search', 'square root'],
      ['-1'],
      ['-1 2 +'],
      ['-2.5'],
      ['--3'],
      ['eval', 'rpn', '-1'],
      ['--', '-x'],
      ['--', 'version'],
      ['bogus-and-unknown-but-shortcut-absorbs-it'],
    ];

    for (final args in accepted) {
      test(args.join(' ').isEmpty ? '<empty>' : args.join(' '), () {
        final router = buildCalculatrixRouter();
        _expectSameAcceptance(router, args);
      });
    }
  });

  group('permute demo router (wildcard and multi parameter routes): every '
      'previously accepted invocation resolves identically in permute '
      'mode', () {
    final accepted = <List<String>>[
      ['run'],
      ['run', 'a', 'b', 'c'],
      ['run', '--verbose', 'a', 'b', 'c'],
      ['run', '--', 'a'],
      ['sync', 'push'],
      ['sync', 'push', 'a', 'b'],
      ['sync', '--force', 'push', 'a', 'b'],
      ['copy', 'a', 'b'],
      ['copy', '--force', 'a', 'b'],
      ['build', 'app'],
      ['build', '--verbose', 'app'],
      ['build', '--tag', 'v1', '--verbose', 'app'],
    ];

    for (final args in accepted) {
      test(args.join(' '), () {
        final router = buildPermuteDemoRouter();
        _expectSameAcceptance(router, args);
      });
    }
  });
}
