// Reproductions for the third round of Codex review findings on PR
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
  group("1: '--' commits the resolver just like an operand does, so help "
      "loses to an option error once '--' has ruled out every route the "
      "resolver could still be aiming for but one", () {
    test("run --help --: unknownOption naming 'run <x>', not "
        'missingArgument', () {
      final helpOpt = OptionSpec.flag('help', abbr: 'h', repeatable: false);
      final router = CliRouter(globalOptions: [helpOpt]);
      router.cmd(
        'run <x>',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      router.cmd('run sub', (req) async => 0, options: const [], globals: true);

      final rejection = _rejected(router, ['run', '--help', '--']);

      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
      expect(rejection.route?.pattern, equals('run <x>'));
      expect(rejection.options, hasLength(1));
      expect(rejection.options.single.spec.name, equals('help'));
    });

    test('without the trailing "--", the same tokens are still ambiguous '
        'between "run <x>" and "run sub": missingArgument, unaffected', () {
      final helpOpt = OptionSpec.flag('help', abbr: 'h', repeatable: false);
      final router = CliRouter(globalOptions: [helpOpt]);
      router.cmd(
        'run <x>',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      router.cmd('run sub', (req) async => 0, options: const [], globals: true);

      final rejection = _rejected(router, ['run', '--help']);

      expect(rejection.kind, equals(CliRejectionKind.missingArgument));
    });
  });

  group('2: the shape used to read a misplaced option, and to name where it '
      'belongs, must come from the declarations actually reachable in the '
      'current subtree, never from an unrelated route elsewhere in the '
      'router that happens to declare the same name with a different '
      'shape', () {
    OptionSpec valueX() =>
        OptionSpec.value('x', abbr: null, required: false, repeatable: false);
    OptionSpec flagX() => OptionSpec.flag('x', abbr: null, repeatable: false);

    test('other registered first (its value-shaped x is the first global '
        'declaration found): group --x a b still names "group a", not '
        '"group b"', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'other',
        (req) async => 0,
        options: [valueX()],
        globals: false,
      );
      final group = CliRouter(globalOptions: const []);
      group.cmd('a', (req) async => 0, options: [flagX()], globals: false);
      group.cmd('b', (req) async => 0, options: [flagX()], globals: false);
      router.mount('group', group);

      final rejection = _rejected(router, ['group', '--x', 'a', 'b']);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route?.pattern, equals('group a'));
    });

    test('same routers, "other" registered last instead: the result does '
        'not depend on registration order', () {
      final router = CliRouter(globalOptions: const []);
      final group = CliRouter(globalOptions: const []);
      group.cmd('a', (req) async => 0, options: [flagX()], globals: false);
      group.cmd('b', (req) async => 0, options: [flagX()], globals: false);
      router.mount('group', group);
      router.cmd(
        'other',
        (req) async => 0,
        options: [valueX()],
        globals: false,
      );

      final rejection = _rejected(router, ['group', '--x', 'a', 'b']);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route?.pattern, equals('group a'));
    });

    test('when the reachable shapes in the subtree genuinely differ, the '
        'option is still misplaced but no single route can be named: '
        'route is null and both candidates are listed, not a guess', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd('a', (req) async => 0, options: [flagX()], globals: false);
      router.cmd('b', (req) async => 0, options: [valueX()], globals: false);

      final rejection = _rejected(router, ['--x', 'a', 'b']);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route, isNull);
      expect(rejection.message, contains("'a'"));
      expect(rejection.message, contains("'b'"));
    });
  });
}
