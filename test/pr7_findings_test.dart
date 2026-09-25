// Reproductions for the 8 review findings on PR ccisnedev/cli_router#7.
// Each group below is numbered to match the review comment it reproduces.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

import 'support.dart';

CliRejection _rejected(CliRouter router, List<String> args) {
  final outcome = router.resolve(args);
  expect(outcome, isA<CliRejection>(), reason: 'for $args, got $outcome');
  return outcome as CliRejection;
}

CliResolution _ok(CliRouter router, List<String> args) {
  final outcome = router.resolve(args);
  expect(outcome, isA<CliResolution>(), reason: 'for $args, got $outcome');
  return outcome as CliResolution;
}

void main() {
  group('1: mount() keeps the mounted router\'s own middleware', () {
    test('a single mount: the child\'s middleware still runs', () async {
      final calls = <String>[];
      final child = CliRouter(globalOptions: const []);
      child.use((next) => (req) async {
        calls.add('child');
        return next(req);
      });
      child.cmd(
        'delete',
        (req) async {
          calls.add('handler');
          return 0;
        },
        options: const [],
        globals: false,
      );
      final parent = CliRouter(globalOptions: const []);
      parent.mount('admin', child);

      final code = await parent.run(
        ['admin', 'delete'],
        onReject: (r) async => 64,
      );

      expect(code, equals(0));
      expect(calls, equals(['child', 'handler']));
    });

    test('the parent\'s middleware wraps outside the mounted router\'s own', () async {
      final calls = <String>[];
      final child = CliRouter(globalOptions: const []);
      child.use((next) => (req) async {
        calls.add('child');
        return next(req);
      });
      child.cmd(
        'delete',
        (req) async {
          calls.add('handler');
          return 0;
        },
        options: const [],
        globals: false,
      );
      final parent = CliRouter(globalOptions: const []);
      parent.use((next) => (req) async {
        calls.add('parent');
        return next(req);
      });
      parent.mount('admin', child);

      await parent.run(['admin', 'delete'], onReject: (r) async => 64);

      expect(calls, equals(['parent', 'child', 'handler']));
    });

    test('nested mounts compose middleware outermost-parent-first at every '
        'level', () async {
      final calls = <String>[];
      final grandchild = CliRouter(globalOptions: const []);
      grandchild.use((next) => (req) async {
        calls.add('grandchild');
        return next(req);
      });
      grandchild.cmd(
        'run',
        (req) async {
          calls.add('handler');
          return 0;
        },
        options: const [],
        globals: false,
      );
      final child = CliRouter(globalOptions: const []);
      child.use((next) => (req) async {
        calls.add('child');
        return next(req);
      });
      child.mount('jobs', grandchild);
      final parent = CliRouter(globalOptions: const []);
      parent.use((next) => (req) async {
        calls.add('parent');
        return next(req);
      });
      parent.mount('admin', child);

      await parent.run(['admin', 'jobs', 'run'], onReject: (r) async => 64);

      expect(calls, equals(['parent', 'child', 'grandchild', 'handler']));
    });
  });

  group('2+3: once the first operand is consumed the resolver is committed '
      '(spec 8.2 rule b)', () {
    test("an optional parameter's value is not reinterpreted as a further "
        'literal route word: run value sub is rejected, not resolved to '
        "'run sub'", () {
      final router = CliRouter(globalOptions: const []);
      router.cmd('run [<arg>]', (req) async => 0, options: const [], globals: false);
      router.cmd('run sub', (req) async => 0, options: const [], globals: false);

      final rejection = _rejected(router, ['run', 'value', 'sub']);

      expect(rejection.kind, equals(CliRejectionKind.extraArgument));
      expect(rejection.route?.pattern, equals('run'));
    });

    test("'run sub' directly still resolves to the literal route", () {
      final router = CliRouter(globalOptions: const []);
      router.cmd('run [<arg>]', (req) async => 0, options: const [], globals: false);
      router.cmd('run sub', (req) async => 0, options: const [], globals: false);

      final result = _ok(router, ['run', 'sub']);

      expect(result.route.pattern, equals('run sub'));
    });

    test("'run value' alone still resolves to the optional-parameter route", () {
      final router = CliRouter(globalOptions: const []);
      router.cmd('run [<arg>]', (req) async => 0, options: const [], globals: false);
      router.cmd('run sub', (req) async => 0, options: const [], globals: false);

      final result = _ok(router, ['run', 'value']);

      expect(result.route.pattern, equals('run'));
      expect(result.params['arg'], equals('value'));
    });

    test('an option between two required parameters is misplaced, naming '
        'the route even though one parameter is still pending', () {
      final json = OptionSpec.flag('json', abbr: null, repeatable: false);
      final router = CliRouter(globalOptions: [json]);
      router.cmd(
        'copy <src> <dst>',
        (req) async => 0,
        options: const [],
        globals: true,
      );

      final rejection = _rejected(router, ['copy', 'a', '--json', 'b']);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route?.pattern, equals('copy <src> <dst>'));
    });

    test('the same invocation resolves once the option precedes both '
        'operands', () {
      final json = OptionSpec.flag('json', abbr: null, repeatable: false);
      final router = CliRouter(globalOptions: [json]);
      router.cmd(
        'copy <src> <dst>',
        (req) async => 0,
        options: const [],
        globals: true,
      );

      final result = _ok(router, ['copy', '--json', 'a', 'b']);

      expect(result.params, equals({'src': 'a', 'dst': 'b'}));
      expect(result.options.single.spec.name, equals('json'));
    });
  });

  group('4+5: an option is identified by its declared shape, not by Dart '
      'object identity (spec 8.2)', () {
    test('two separately declared instances of the same shape are the same '
        'option throughout resolution', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'go',
        (req) async => 0,
        options: [OptionSpec.flag('x', abbr: null, repeatable: false)],
        globals: false,
      );
      router.cmd(
        'go <arg>',
        (req) async => 0,
        options: [OptionSpec.flag('x', abbr: null, repeatable: false)],
        globals: false,
      );

      final result = _ok(router, ['go', '--x', 'a']);

      expect(result.route.pattern, equals('go <arg>'));
      expect(result.params['arg'], equals('a'));
      expect(result.options.single.spec.name, equals('x'));
    });

    test('required-option checks use the same shape equality: a required '
        'option is satisfied even when the route that requires it is '
        'reached through a different OptionSpec instance', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'go',
        (req) async => 0,
        options: [
          OptionSpec.value('x', abbr: null, required: true, repeatable: false),
        ],
        globals: false,
      );
      router.cmd(
        'go <arg>',
        (req) async => 0,
        options: [
          OptionSpec.value('x', abbr: null, required: true, repeatable: false),
        ],
        globals: false,
      );

      final result = _ok(router, ['go', '--x', 'v', 'a']);

      expect(result.route.pattern, equals('go <arg>'));
      expect(result.params['arg'], equals('a'));
    });
  });

  group('6: a route option colliding with a global option is always an '
      'ArgumentError, whatever the route\'s globals flag', () {
    test("'local' with globals: false and a value option 'json' is rejected "
        'at registration, not accepted at resolution', () {
      final router = CliRouter(
        globalOptions: [OptionSpec.flag('json', abbr: null, repeatable: false)],
      );

      expect(
        () => router.cmd(
          'local',
          (req) async => 0,
          options: [
            OptionSpec.value(
              'json',
              abbr: null,
              required: false,
              repeatable: false,
            ),
          ],
          globals: false,
        ),
        throwsArgumentError,
      );
    });
  });

  group('7: misplaced descendant options are decided by subtree '
      'declaration, not by uninterrupted lookahead (spec 8.2 rule a)', () {
    test('an option interrupted by another valid option before reaching its '
        'route is still misplaced, not unknown, and its message lists every '
        'candidate route since none can be named for certain', () {
      final router = buildCalculatrixRouter();

      final rejection = _rejected(router, [
        'eval',
        '--file',
        'p.rpn',
        '--help',
        'rpn',
      ]);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route, isNull);
      expect(rejection.message, contains('eval rpn'));
      expect(rejection.message, contains('eval infix'));
    });

    test('uninterrupted, the same option is still correctly named to its '
        'one reachable route', () {
      final router = buildCalculatrixRouter();

      final rejection = _rejected(router, ['eval', '--file', 'p.rpn', 'rpn']);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route?.pattern, equals('eval rpn'));
    });
  });

  group('8: mount() preserves reserved words from a nested empty mount', () {
    test("a router's own empty mount reserves the word directly", () {
      final child = CliRouter(globalOptions: const []);
      final grandchild = CliRouter(globalOptions: const []);
      child.mount('reserved', grandchild);
      child.cmd('<arg>', (req) async => 0, options: const [], globals: false);

      final rejection = _rejected(child, ['reserved']);

      expect(rejection.kind, equals(CliRejectionKind.incomplete));
    });

    test('the same reservation survives being mounted under a parent router', () {
      final child = CliRouter(globalOptions: const []);
      final grandchild = CliRouter(globalOptions: const []);
      child.mount('reserved', grandchild);
      child.cmd('<arg>', (req) async => 0, options: const [], globals: false);

      final parent = CliRouter(globalOptions: const []);
      parent.mount('a', child);

      final rejection = _rejected(parent, ['a', 'reserved']);

      expect(rejection.kind, equals(CliRejectionKind.incomplete));
    });

    test('a genuinely free word is still absorbed by the param route once '
        'mounted', () {
      final child = CliRouter(globalOptions: const []);
      final grandchild = CliRouter(globalOptions: const []);
      child.mount('reserved', grandchild);
      child.cmd('<arg>', (req) async => 0, options: const [], globals: false);

      final parent = CliRouter(globalOptions: const []);
      parent.mount('a', child);

      final result = _ok(parent, ['a', 'somethingElse']);

      expect(result.params['arg'], equals('somethingElse'));
    });
  });
}
