// Reproductions for the fourth round of Codex review findings on PR
// ccisnedev/cli_router#7. Each group below is numbered to match the review
// comment it reproduces.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

CliRejection _rejected(CliRouter router, List<String> args) {
  final outcome = router.resolve(args);
  expect(outcome, isA<CliRejection>(), reason: 'for $args, got $outcome');
  return outcome as CliRejection;
}

void main() {
  group('1: an unrecognized first token is unknownCommand even when the '
      "root itself already owns a route; extraArgument only applies once "
      'an operand has actually been bound', () {
    test("resolve(['verison']) is unknownCommand, not extraArgument naming "
        "the root's own '' route", () {
      final router = CliRouter(globalOptions: const []);
      router.cmd('', (req) async => 0, options: const [], globals: false);
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

    test('a genuinely resolved route still reports extraArgument for a '
        'trailing token that does not fit it', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'version',
        (req) async => 0,
        options: const [],
        globals: false,
      );

      final rejection = _rejected(router, ['version', 'junk']);

      expect(rejection.kind, equals(CliRejectionKind.extraArgument));
      expect(rejection.route?.pattern, equals('version'));
    });
  });

  group('2: a node may have both a required parameter and a final wildcard '
      '(spec 8.1); an operand token always goes to the parameter, '
      'unconditionally, with no last-token exception and no lookahead into '
      "the parameter's own subtree (round 5). The wildcard is reached only "
      'when argv ends exactly at the node and it has no route of its own', () {
    test('run <arg> and run * coexist; a single operand resolves through '
        'the parameter', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'run <arg>',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      router.cmd('run *', (req) async => 0, options: const [], globals: false);

      final outcome = router.resolve(['run', 'x']);

      expect(outcome, isA<CliResolution>());
      final resolution = outcome as CliResolution;
      expect(resolution.route.pattern, equals('run <arg>'));
      expect(resolution.params, equals({'arg': 'x'}));
    });

    test('(round 5) an operand token always goes to the parameter, even '
        'when it alone cannot complete the parameter chain: run <a> <b> '
        "and run *, 'run x' is missingArgument for <b>, not the wildcard", () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'run <a> <b>',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      router.cmd('run *', (req) async => 0, options: const [], globals: false);

      final rejection = _rejected(router, ['run', 'x']);

      expect(rejection.kind, equals(CliRejectionKind.missingArgument));
      expect(rejection.message, contains('<b>'));
    });

    test('(round 5) the wildcard is reached only when argv ends exactly at '
        'the node with no operand left to give the parameter: run <arg> '
        "and run *, 'run' alone resolves through the wildcard with zero "
        'operands', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'run <arg>',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      router.cmd('run *', (req) async => 0, options: const [], globals: false);

      final outcome = router.resolve(['run']);

      expect(outcome, isA<CliResolution>());
      final resolution = outcome as CliResolution;
      expect(resolution.route.pattern, equals('run'));
      expect(resolution.route.hasWildcard, isTrue);
      expect(resolution.rest, equals(<String>[]));
    });

    test('enough tokens for the full parameter chain still resolve through '
        "the parameter: 'run x y' binds <a> and <b>", () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'run <a> <b>',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      router.cmd('run *', (req) async => 0, options: const [], globals: false);

      final outcome = router.resolve(['run', 'x', 'y']);

      expect(outcome, isA<CliResolution>());
      final resolution = outcome as CliResolution;
      expect(resolution.route.pattern, equals('run <a> <b>'));
      expect(resolution.params, equals({'a': 'x', 'b': 'y'}));
    });

    test('the decision is local, not backtracking: once the first token '
        'commits to the parameter chain because more tokens were still '
        "coming, a token beyond the chain's depth is extraArgument against "
        "the parameter route, even though 'run *' could have absorbed all "
        'of them', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'run <a> <b>',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      router.cmd('run *', (req) async => 0, options: const [], globals: false);

      final rejection = _rejected(router, ['run', 'x', 'y', 'z']);

      expect(rejection.kind, equals(CliRejectionKind.extraArgument));
      expect(rejection.route?.pattern, equals('run <a> <b>'));
    });
  });

  group('3: a misplacedOption message names the option by the declaration '
      'reachable from the current subtree, never by an unrelated '
      'declaration found first elsewhere in the router', () {
    OptionSpec archive() =>
        OptionSpec.flag('archive', abbr: 'x', repeatable: false);
    OptionSpec execute() =>
        OptionSpec.flag('execute', abbr: 'x', repeatable: false);

    test("other (--archive/-x) registered before group a (--execute/-x): "
        "'group -x a' still describes -x as --execute, the reachable "
        'declaration', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'other',
        (req) async => 0,
        options: [archive()],
        globals: false,
      );
      router.cmd(
        'group a',
        (req) async => 0,
        options: [execute()],
        globals: false,
      );

      final rejection = _rejected(router, ['group', '-x', 'a']);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route?.pattern, equals('group a'));
      expect(rejection.message, contains('-x (--execute)'));
      expect(rejection.message, isNot(contains('--archive')));
    });

    test('same declarations, registered in the opposite order: the '
        'message still names the reachable declaration', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'group a',
        (req) async => 0,
        options: [execute()],
        globals: false,
      );
      router.cmd(
        'other',
        (req) async => 0,
        options: [archive()],
        globals: false,
      );

      final rejection = _rejected(router, ['group', '-x', 'a']);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route?.pattern, equals('group a'));
      expect(rejection.message, contains('-x (--execute)'));
      expect(rejection.message, isNot(contains('--archive')));
    });
  });

  group('4: ListedCommand.command reflects the full registered pattern, '
      'trailing optional parameter or wildcard segment included', () {
    test('a trailing wildcard segment is kept', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd('run *', (req) async => 0, options: const [], globals: false);

      final listed = router.listCommands().single;

      expect(listed.command, equals('run *'));
    });

    test('a trailing optional parameter segment is kept', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'help [<topic>]',
        (req) async => 0,
        options: const [],
        globals: false,
      );

      final listed = router.listCommands().single;

      expect(listed.command, equals('help [<topic>]'));
    });

    test('a trailing segment is kept through a mount', () {
      final router = CliRouter(globalOptions: const []);
      final sub = CliRouter(globalOptions: const []);
      sub.cmd('exec *', (req) async => 0, options: const [], globals: false);
      router.mount('tools', sub);

      final listed = router.listCommands().single;

      expect(listed.command, equals('tools exec *'));
    });
  });
}
