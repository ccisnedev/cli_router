// Coordinator review of feat/0.2.0-trie-and-option-schema, probed with the
// calculatrix fixture (support.dart):
//
// 1. BUG: a route with `globals: false` accepts global options read before
//    its operand. `resolve(['--json', '1 2 +'])` wrongly resolves on the
//    `<program>` route (globals: false); same for `-h`. Spec 8.2: "option in
//    scope but not accepted by the resolved route: unknownOption, naming the
//    route".
// 2. Every CliRejection must carry a non-null message, and a route whenever
//    the route is already resolved at rejection time.
// 3. Scope rule (spec 8.2): at a node, the options in scope are the globals
//    plus the options of every route whose literal segments are all
//    consumed at that node, not just one deterministic route. Covered here
//    for a node that has both a literal child and a param child.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

import 'support.dart';

CliRejection _rejected(CliRouter router, List<String> args) {
  final outcome = router.resolve(args);
  expect(outcome, isA<CliRejection>(), reason: 'for $args, got $outcome');
  return outcome as CliRejection;
}

void main() {
  group('bug: a route with globals: false still rejects a global option '
      'read before its operand', () {
    test('cx --json 1 2 + : --json is not accepted by <program>', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['--json', '1 2 +']);
      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
      expect(rejection.route?.pattern, equals('<program>'));
      expect(rejection.message, isNotNull);
      expect(rejection.message, contains('json'));
    });

    test('cx -h 1 2 + : -h (--help) is not accepted by <program>', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['-h', '1 2 +']);
      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
      expect(rejection.route?.pattern, equals('<program>'));
      expect(rejection.message, isNotNull);
    });

    test('the same option is still fine on a route that does accept '
        'globals', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['--json', 'version']);
      // 'version' is a literal child of root, so the option is misplaced
      // (it must come after the route, not before); it is never silently
      // accepted at the wrong position either. This just documents that the
      // scope-vs-accepts distinction is not the same bug as G6 ordering.
      expect(outcome, isA<CliRejection>());
      expect(
        (outcome as CliRejection).kind,
        equals(CliRejectionKind.misplacedOption),
      );
    });
  });

  group('every rejection carries a non-null message', () {
    test('missingValue: cx eval rpn -f', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['eval', 'rpn', '-f']);
      expect(rejection.kind, equals(CliRejectionKind.missingValue));
      expect(rejection.message, isNotNull);
      expect(rejection.route?.pattern, equals('eval rpn'));
    });

    test('unexpectedValue: cx version --json=x', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['version', '--json=x']);
      expect(rejection.kind, equals(CliRejectionKind.unexpectedValue));
      expect(rejection.message, isNotNull);
      expect(rejection.route?.pattern, equals('version'));
    });

    test("misplacedOption: cx '1 2 +' --json (option after the operand)", () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['1 2 +', '--json']);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.message, isNotNull);
      expect(rejection.route?.pattern, equals('<program>'));
    });

    test('misplacedOption: cx --json version (option before a literal '
        'child)', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['--json', 'version']);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.message, isNotNull);
    });

    test('invalidShortOption, a cluster: cx eval rpn -qh', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['eval', 'rpn', '-qh']);
      expect(rejection.kind, equals(CliRejectionKind.invalidShortOption));
      expect(rejection.message, isNotNull);
      expect(rejection.message, contains('-q'));
      expect(rejection.message, contains('-h'));
      expect(rejection.route?.pattern, equals('eval rpn'));
    });

    test('invalidShortOption, an attached value: cx eval rpn -fprog.rpn', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['eval', 'rpn', '-fprog.rpn']);
      expect(rejection.kind, equals(CliRejectionKind.invalidShortOption));
      expect(rejection.message, isNotNull);
      expect(rejection.message, contains('-f'));
      expect(rejection.message, contains('prog.rpn'));
    });

    test('repeatedOption: cx eval rpn -f a.rpn -f b.rpn', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, [
        'eval',
        'rpn',
        '-f',
        'a.rpn',
        '-f',
        'b.rpn',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.repeatedOption));
      expect(rejection.message, isNotNull);
      expect(rejection.route?.pattern, equals('eval rpn'));
    });

    test('unknownOption, undeclared anywhere: cx eval rpn --trace', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['eval', 'rpn', '--trace']);
      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
      expect(rejection.message, isNotNull);
    });

    test('unknownOption, declared by an unrelated route, naming the route '
        'reached: cx commands show --category matrix power', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, [
        'commands',
        'show',
        '--category',
        'matrix',
        'power',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
      expect(rejection.message, isNotNull);
      expect(rejection.route?.pattern, equals('commands show <name>'));
    });

    test('missingRequiredOption: cx deploy with no --target', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'deploy',
        (req) async => 0,
        options: [
          OptionSpec.value(
            'target',
            abbr: 't',
            required: true,
            repeatable: false,
          ),
        ],
        globals: false,
      );
      final rejection = _rejected(router, ['deploy']);
      expect(rejection.kind, equals(CliRejectionKind.missingRequiredOption));
      expect(rejection.message, isNotNull);
      expect(rejection.route?.pattern, equals('deploy'));
    });

    test('unknownCommand: cx bogus', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'version',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      final rejection = _rejected(router, ['bogus']);
      expect(rejection.kind, equals(CliRejectionKind.unknownCommand));
      expect(rejection.message, isNotNull);
      expect(rejection.route, isNull);
    });

    test('extraArgument: cx version junk', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['version', 'junk']);
      expect(rejection.kind, equals(CliRejectionKind.extraArgument));
      expect(rejection.message, isNotNull);
      expect(rejection.route?.pattern, equals('version'));
    });

    test('incomplete: cx commands', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['commands']);
      expect(rejection.kind, equals(CliRejectionKind.incomplete));
      expect(rejection.message, isNotNull);
      expect(rejection.route, isNull);
    });

    test('missingArgument: cx commands show', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['commands', 'show']);
      expect(rejection.kind, equals(CliRejectionKind.missingArgument));
      expect(rejection.message, isNotNull);
      expect(rejection.route, isNull);
    });
  });

  group('scope at a node with both a literal child and a param child', () {
    CliRouter buildDualNodeRouter() {
      final router = CliRouter(
        globalOptions: [
          OptionSpec.flag('verbose', abbr: 'v', repeatable: false),
        ],
      );
      router.cmd('build', (req) async => 0, options: const [], globals: true);
      router.cmd(
        '<target>',
        (req) async => 0,
        options: [OptionSpec.flag('force', abbr: null, repeatable: false)],
        globals: false,
      );
      return router;
    }

    test('an option only the param route declares is readable at the root, '
        'before either child is chosen, and accepted once that route is '
        'the one resolved', () {
      final router = buildDualNodeRouter();
      final outcome = router.resolve(['--force', 'anything']);
      expect(outcome, isA<CliResolution>());
      expect((outcome as CliResolution).params['target'], equals('anything'));
      expect(outcome.options.single.spec.name, equals('force'));
    });

    test('a global is readable at the root too, but rejected once '
        'resolution lands on the globals: false route', () {
      final router = buildDualNodeRouter();
      final rejection = _rejected(router, ['--verbose', 'anything']);
      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
      expect(rejection.route?.pattern, equals('<target>'));
      expect(rejection.message, isNotNull);
    });

    test('the param-only option is readable at the root even ahead of the '
        'literal child: it is recognized as an option at all (not '
        'invalidShortOption/unknownOption-undeclared), but is then '
        'misplaced, since it sits right before the literal route it does '
        'not belong to', () {
      final router = buildDualNodeRouter();
      final rejection = _rejected(router, ['--force', 'build']);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route?.pattern, equals('build'));
      expect(rejection.message, isNotNull);
    });

    test('the literal route itself still resolves normally', () {
      final router = buildDualNodeRouter();
      final outcome = router.resolve(['build']);
      expect(outcome, isA<CliResolution>());
      expect((outcome as CliResolution).route.pattern, equals('build'));
    });
  });
}
