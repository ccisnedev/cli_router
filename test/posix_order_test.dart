// POSIX order (G6): route, then options, then operands. The three local
// misplaced-option rules of spec 8.2, plus `--` (G10) and short options
// standing alone in that order (G9).
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
  group('rule: an option followed by a literal child of its node', () {
    test('cx --json version', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['--json', 'version']);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
    });

    test('cx version --json is valid (option after the full route)', () {
      final router = buildCalculatrixRouter();
      final result = _ok(router, ['version', '--json']);
      expect(result.route.pattern, equals('version'));
      expect(result.options.single.spec.name, equals('json'));
    });
  });

  group('rule: an option read after an operand', () {
    test("cx eval rpn '1 2 +' --json", () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['eval', 'rpn', '1 2 +', '--json']);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
    });

    test("cx eval rpn --json '1 2 +' is valid (options first)", () {
      final router = buildCalculatrixRouter();
      final result = _ok(router, ['eval', 'rpn', '--json', '1 2 +']);
      expect(result.params['program'], equals('1 2 +'));
      expect(result.options.single.spec.name, equals('json'));
    });

    test('an option after an operand consumed via a wildcard', () {
      final router = CliRouter();
      router.cmd(
        'run *',
        (req) async => 0,
        options: [OptionSpec.flag('verbose', abbr: 'v', repeatable: false)],
        globals: false,
      );
      final rejection = _rejected(router, ['run', 'a', '-v']);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
    });
  });

  group('rule: an option not in scope, declared by a route under the node', () {
    test('cx eval -f p.rpn rpn', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['eval', '-f', 'p.rpn', 'rpn']);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route?.pattern, equals('eval rpn'));
    });

    test('cx -f prog.rpn eval rpn', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['-f', 'prog.rpn', 'eval', 'rpn']);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
    });
  });

  group('-- ends the options (G10)', () {
    test('cx -- -x : the shortcut accepts -- and takes -x as the program', () {
      final router = buildCalculatrixRouter();
      final result = _ok(router, ['--', '-x']);
      expect(result.route.pattern, equals('<program>'));
      expect(result.params['program'], equals('-x'));
    });

    test('cx eval rpn --json -- -x : -x is the program, not an option', () {
      final router = buildCalculatrixRouter();
      final result = _ok(router, ['eval', 'rpn', '--json', '--', '-x']);
      expect(result.params['program'], equals('-x'));
      expect(result.options.single.spec.name, equals('json'));
    });

    test('cx eval rpn -- --help : --help is the program, not help', () {
      final router = buildCalculatrixRouter();
      final result = _ok(router, ['eval', 'rpn', '--', '--help']);
      expect(result.params['program'], equals('--help'));
      expect(result.options, isEmpty);
    });

    test('after --, a token is never taken as a literal route child', () {
      final router = buildCalculatrixRouter();
      // 'version' after -- is the shortcut's program, not the version route.
      final result = _ok(router, ['--', 'version']);
      expect(result.route.pattern, equals('<program>'));
      expect(result.params['program'], equals('version'));
    });
  });

  group('a required positional that ends the route is an operand too', () {
    test('cx commands show power --json is misplaced (option after the '
        'operand)', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, [
        'commands',
        'show',
        'power',
        '--json',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
    });

    test('cx commands show --json power is valid (option before the '
        'operand)', () {
      final router = buildCalculatrixRouter();
      final result = _ok(router, ['commands', 'show', '--json', 'power']);
      expect(result.params['name'], equals('power'));
      expect(result.options.single.spec.name, equals('json'));
    });

    test('a required parameter followed by more literal is still route, '
        'not an operand: an option there is checked by lookahead', () {
      final router = CliRouter();
      router.cmd(
        'show <id> details',
        (req) async => 0,
        options: [OptionSpec.flag('verbose', abbr: 'v', repeatable: false)],
        globals: false,
      );
      final rejection = _rejected(router, ['show', '42', '-v', 'details']);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
    });

    test('a required parameter followed by more literal: the option is '
        'valid once the route is actually complete', () {
      final router = CliRouter();
      router.cmd(
        'show <id> details',
        (req) async => 0,
        options: [OptionSpec.flag('verbose', abbr: 'v', repeatable: false)],
        globals: false,
      );
      final result = _ok(router, ['show', '42', 'details', '-v']);
      expect(result.params['id'], equals('42'));
      expect(result.options.single.spec.name, equals('verbose'));
    });
  });

  group('short options stand alone (G9), in the middle of an invocation', () {
    test('cx eval rpn -q -h is valid (two separate short flags)', () {
      final router = buildCalculatrixRouter();
      final result = _ok(router, ['eval', 'rpn', '-q', '-h']);
      expect(result.options.map((o) => o.spec.name), equals(['quiet', 'help']));
    });

    test('cx eval rpn -qh is invalidShortOption', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['eval', 'rpn', '-qh']);
      expect(rejection.kind, equals(CliRejectionKind.invalidShortOption));
    });
  });
}
