// Reproductions for the fifth round of Codex review findings on PR
// ccisnedev/cli_router#7. Each group below is numbered to match the review
// comment it reproduces. The round 4 param+wildcard resolution-time tests
// (edited for round 5) live in test/pr7_round4_findings_test.dart, group 2;
// this file covers the new build-time restriction and the root guard fix.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

CliRejection _rejected(CliRouter router, List<String> args) {
  final outcome = router.resolve(args);
  expect(outcome, isA<CliRejection>(), reason: 'for $args, got $outcome');
  return outcome as CliRejection;
}

void main() {
  group('1: an optional parameter and a wildcard cannot coexist at the '
      'same trie position, in either registration order, because the '
      'optional parameter already matches every operand count the '
      'wildcard could otherwise catch, so the wildcard route would be '
      'unreachable', () {
    test('optional parameter registered first, wildcard second', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'run [<arg>]',
        (req) async => 0,
        options: const [],
        globals: false,
      );

      expect(
        () => router.cmd(
          'run *',
          (req) async => 0,
          options: const [],
          globals: false,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('unreachable'),
          ),
        ),
      );
    });

    test('wildcard registered first, optional parameter second', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd('run *', (req) async => 0, options: const [], globals: false);

      expect(
        () => router.cmd(
          'run [<arg>]',
          (req) async => 0,
          options: const [],
          globals: false,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('unreachable'),
          ),
        ),
      );
    });
  });

  group('2: registering only [<arg>] at the root and resolving with two '
      'leftover tokens is extraArgument naming the [<arg>] route, not '
      'unknownCommand: binding the optional parameter leaves node at '
      '_root, so the root unknownCommand guard must be restricted to the '
      'case where no operand has been consumed', () {
    test("resolve(['x', 'y']) against a root '[<arg>]' route is "
        'extraArgument, not unknownCommand', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        '[<arg>]',
        (req) async => 0,
        options: const [],
        globals: false,
      );

      final rejection = _rejected(router, ['x', 'y']);

      expect(rejection.kind, equals(CliRejectionKind.extraArgument));
      expect(rejection.route?.pattern, equals(''));
      expect(rejection.route?.optionalParam, equals('arg'));
    });

    test("a single token still resolves ['x'] binds arg", () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        '[<arg>]',
        (req) async => 0,
        options: const [],
        globals: false,
      );

      final outcome = router.resolve(['x']);

      expect(outcome, isA<CliResolution>());
      final resolution = outcome as CliResolution;
      expect(resolution.params, equals({'arg': 'x'}));
    });

    test("an unrelated first token still reports unknownCommand when no "
        'route at the root has claimed it as an operand yet: a plain '
        "literal route sibling, 'verison' against 'version', is "
        'unaffected by the guard change', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'version',
        (req) async => 0,
        options: const [],
        globals: false,
      );

      final rejection = _rejected(router, ['verison']);

      expect(rejection.kind, equals(CliRejectionKind.unknownCommand));
      expect(rejection.route, isNull);
    });
  });
}
