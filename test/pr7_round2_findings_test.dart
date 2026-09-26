// Reproductions for the second round of review findings on PR
// ccisnedev/cli_router#7. Each group below is numbered to match the review
// comment it reproduces. Finding 6 (OptionSpec.abbr becoming a required
// named parameter) has no test here: it is a compile-time guarantee, not a
// runtime behavior, so it is proven by every call site in this package
// compiling with `abbr:` explicit, checked by `dart analyze`.
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
  group("1: mount() requires the mounted router's globalOptions to equal the "
      "parent's, by shape, as a set (one program, one set of globals)", () {
    test('mismatched globalOptions: mount() throws ArgumentError', () {
      final targetOpt = OptionSpec.value(
        'target',
        abbr: null,
        required: true,
        repeatable: false,
      );
      final child = CliRouter(globalOptions: [targetOpt]);
      child.cmd('push', (req) async => 0, options: const [], globals: true);

      final parent = CliRouter(globalOptions: const []);

      expect(() => parent.mount('remote', child), throwsArgumentError);
    });

    test("matching globalOptions: mount() succeeds, and the child's "
        'required global is still enforced after mounting (the original '
        'defect: it used to be silently lost)', () {
      final targetOpt = OptionSpec.value(
        'target',
        abbr: null,
        required: true,
        repeatable: false,
      );
      final child = CliRouter(globalOptions: [targetOpt]);
      child.cmd('push', (req) async => 0, options: const [], globals: true);

      final parent = CliRouter(globalOptions: [targetOpt]);
      parent.mount('remote', child);

      final missing = _rejected(parent, ['remote', 'push']);
      expect(missing.kind, equals(CliRejectionKind.missingRequiredOption));

      final ok = _ok(parent, ['remote', 'push', '--target', 'prod']);
      expect(ok.route.pattern, equals('remote push'));
    });

    test('globalOptions equal as a set: declaration order does not '
        'matter', () {
      final a = OptionSpec.flag('a', abbr: null, repeatable: false);
      final b = OptionSpec.flag('b', abbr: null, repeatable: false);
      final child = CliRouter(globalOptions: [b, a]);
      child.cmd('go', (req) async => 0, options: const [], globals: false);
      final parent = CliRouter(globalOptions: [a, b]);

      expect(() => parent.mount('sub', child), returnsNormally);
    });
  });

  group(
    '2: missingArgument revalidates parsed options against the one route '
    'still reachable before reporting it, rather than reporting the '
    'missing parameter over an option the eventual route does not accept',
    () {
      test('go --force --help a: unknownOption naming "go <a> <b>", not '
          'missingArgument', () {
        final helpOpt = OptionSpec.flag('help', abbr: 'h', repeatable: false);
        final forceOpt = OptionSpec.flag(
          'force',
          abbr: null,
          repeatable: false,
        );
        final router = CliRouter(globalOptions: [helpOpt]);
        router.cmd('go', (req) async => 0, options: [forceOpt], globals: true);
        router.cmd(
          'go <a> <b>',
          (req) async => 0,
          options: const [],
          globals: true,
        );

        final rejection = _rejected(router, ['go', '--force', '--help', 'a']);

        expect(rejection.kind, equals(CliRejectionKind.unknownOption));
        expect(rejection.route?.pattern, equals('go <a> <b>'));
      });

      test('go --help a b still resolves fine (help is accepted by both '
          'routes)', () {
        final helpOpt = OptionSpec.flag('help', abbr: 'h', repeatable: false);
        final forceOpt = OptionSpec.flag(
          'force',
          abbr: null,
          repeatable: false,
        );
        final router = CliRouter(globalOptions: [helpOpt]);
        router.cmd('go', (req) async => 0, options: [forceOpt], globals: true);
        router.cmd(
          'go <a> <b>',
          (req) async => 0,
          options: const [],
          globals: true,
        );

        final ok = _ok(router, ['go', '--help', 'a', 'b']);
        expect(ok.route.pattern, equals('go <a> <b>'));
      });
    },
  );

  group('3: option lookahead must not consume an option-shaped token as if it '
      'were a parameter; misplacement is decided from the subtree, not from '
      'a lookahead an option token wrongly walked past', () {
    test('--file p --help eval rpn: misplacedOption naming "eval rpn", not '
        'unknownOption naming "<program>"', () {
      final helpOpt = OptionSpec.flag('help', abbr: 'h', repeatable: false);
      final fileOpt = OptionSpec.value(
        'file',
        abbr: 'f',
        required: false,
        repeatable: false,
      );
      final router = CliRouter(globalOptions: [helpOpt]);
      final eval = CliRouter(globalOptions: [helpOpt]);
      eval.cmd('rpn', (req) async => 0, options: [fileOpt], globals: false);
      router.mount('eval', eval);
      router.cmd(
        '<program>',
        (req) async => 0,
        options: const [],
        globals: false,
      );

      final rejection = _rejected(router, [
        '--file',
        'p',
        '--help',
        'eval',
        'rpn',
      ]);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route?.pattern, equals('eval rpn'));
    });
  });

  group('3b: a parent route of its own (root\'s literal "" route) must not '
      'make an interrupted lookahead misreport misplacedOption as '
      'unknownOption against that route, on the real calculatrix fixture', () {
    test('--file p --help eval rpn: misplacedOption, not unknownOption '
        'naming the root banner route', () {
      final router = buildCalculatrixRouter();

      final rejection = _rejected(router, [
        '--file',
        'p',
        '--help',
        'eval',
        'rpn',
      ]);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(
        rejection.route == null ||
            rejection.route?.pattern == 'eval rpn' ||
            rejection.route?.pattern == 'eval infix',
        isTrue,
        reason: 'got route ${rejection.route?.pattern}',
      );
      if (rejection.route == null) {
        expect(
          rejection.candidates.map((r) => r.pattern),
          unorderedEquals(['eval rpn', 'eval infix']),
        );
      }
      // eval rpn and eval infix declare the exact same fileOpt shape, so
      // the router can still name it even though it cannot name a single
      // route.
      expect(rejection.option, equals(fileOpt));
    });

    test('--file p: misplacedOption with both eval rpn and eval infix as '
        'candidates, not unknownOption naming the root banner route', () {
      final router = buildCalculatrixRouter();

      final rejection = _rejected(router, ['--file', 'p']);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route, isNull);
      expect(
        rejection.candidates.map((r) => r.pattern),
        unorderedEquals(['eval rpn', 'eval infix']),
      );
      expect(rejection.option, equals(fileOpt));
    });

    test('--bogus eval rpn: unknownOption, since no route anywhere '
        'declares "bogus"', () {
      final router = buildCalculatrixRouter();

      final rejection = _rejected(router, ['--bogus', 'eval', 'rpn']);

      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
    });

    test('eval --file p rpn: misplacedOption naming "eval rpn" (the '
        'uninterrupted case still names its one reachable route)', () {
      final router = buildCalculatrixRouter();

      final rejection = _rejected(router, ['eval', '--file', 'p', 'rpn']);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route?.pattern, equals('eval rpn'));
    });
  });

  group('4: registered options and globalOptions are defensive copies, not '
      "references to the caller's lists", () {
    test("mutating the caller's options list after cmd() does not affect "
        'the registered route', () {
      final xOpt = OptionSpec.flag('x', abbr: null, repeatable: false);
      final yOpt = OptionSpec.flag('y', abbr: null, repeatable: false);
      final opts = <OptionSpec>[xOpt];
      final router = CliRouter(globalOptions: const []);
      router.cmd('go', (req) async => 0, options: opts, globals: false);

      opts.add(yOpt);

      final rejection = _rejected(router, ['go', '--y']);
      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
    });

    test("mutating the caller's globalOptions list after construction does "
        'not affect the router', () {
      final targetOpt = OptionSpec.value(
        'target',
        abbr: null,
        required: true,
        repeatable: false,
      );
      final globals = <OptionSpec>[targetOpt];
      final router = CliRouter(globalOptions: globals);
      router.cmd('push', (req) async => 0, options: const [], globals: true);

      globals.clear();

      final rejection = _rejected(router, ['push']);
      expect(rejection.kind, equals(CliRejectionKind.missingRequiredOption));
    });
  });

  group('5: "--" after the first operand is misplacedOption, not silently '
      'dropped', () {
    test('<program>: "one --" is misplacedOption naming "<program>", not '
        'resolved the same as just "one"', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        '<program>',
        (req) async => 0,
        options: const [],
        globals: false,
      );

      final rejection = _rejected(router, ['one', '--']);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route?.pattern, equals('<program>'));
    });

    test('run *: "run a -- --help" is misplacedOption, not resolved with '
        'rest: [a, --help]', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd('run *', (req) async => 0, options: const [], globals: false);

      final rejection = _rejected(router, ['run', 'a', '--', '--help']);

      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
    });

    test('"--" before any operand still ends option parsing, unaffected', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        '<program>',
        (req) async => 0,
        options: const [],
        globals: false,
      );

      final ok = _ok(router, ['--', 'one']);
      expect(ok.params['program'], equals('one'));
    });
  });
}
