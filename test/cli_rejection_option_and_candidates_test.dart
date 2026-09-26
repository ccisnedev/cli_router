// PR ccisnedev/cli_router#7 round 6 Codex findings 1 and 2: two more typed
// fields on CliRejection, alongside the existing `argument` and `token`:
//
// - `option` (OptionSpec?): the declared option shape this rejection
//   implicates, when the router can name exactly one.
// - `candidates` (List<CliRoute>): every route still reachable that
//   declares an option this rejection could not resolve to a single route,
//   never null, empty when not applicable.
//
// Every CliRejectionKind is covered here, asserting exactly which of the two
// fields is guaranteed for that kind, per the doc comments on
// CliRejectionKind and CliRejection. `dart_router.dart` never uses
// OptionSpec identity: comparisons below rely on OptionSpec's declared-shape
// `==`, so a freshly constructed expected spec matches the one the router
// read internally.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

import 'support.dart';

CliRejection _rejected(CliRouter router, List<String> args) {
  final outcome = router.resolve(args);
  expect(outcome, isA<CliRejection>(), reason: 'for $args, got $outcome');
  return outcome as CliRejection;
}

void main() {
  group('unknownCommand: option is always null, candidates always empty', () {
    test('cx bogus: a router with no root parameter to absorb it', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'version',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      final rejection = _rejected(router, ['bogus']);
      expect(rejection.kind, equals(CliRejectionKind.unknownCommand));
      expect(rejection.option, isNull);
      expect(rejection.candidates, isEmpty);
    });
  });

  group('extraArgument: option is always null, candidates always empty', () {
    test('cx version junk', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'version',
        'junk',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.extraArgument));
      expect(rejection.option, isNull);
      expect(rejection.candidates, isEmpty);
    });
  });

  group('incomplete: option is always null, candidates always empty', () {
    test('cx commands shwo power', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'commands',
        'shwo',
        'power',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.incomplete));
      expect(rejection.option, isNull);
      expect(rejection.candidates, isEmpty);
    });

    test('cx commands: argv ran out, still no option implicated', () {
      final rejection = _rejected(buildCalculatrixRouter(), ['commands']);
      expect(rejection.kind, equals(CliRejectionKind.incomplete));
      expect(rejection.option, isNull);
      expect(rejection.candidates, isEmpty);
    });
  });

  group('missingArgument: option is always null, candidates always empty', () {
    test('cx commands show', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'commands',
        'show',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.missingArgument));
      expect(rejection.option, isNull);
      expect(rejection.candidates, isEmpty);
    });
  });

  group('unknownOption: option only via the optionsMismatch path', () {
    test('cx --json 1 2 +: option was read and matched jsonOpt, then '
        'rejected once the shortcut route is known not to accept it', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        '--json',
        '1 2 +',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
      expect(rejection.option, equals(jsonOpt));
      expect(rejection.candidates, isEmpty);
    });

    test('cx eval rpn --trace: undeclared anywhere reachable, option is '
        'null, there is no spec to report', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'eval',
        'rpn',
        '--trace',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
      expect(rejection.option, isNull);
      expect(rejection.candidates, isEmpty);
    });
  });

  group('misplacedOption: option and candidates depend on the situation', () {
    test("cx '1 2 +' --json: option read after an operand has started, its "
        'declaration is never looked up, option is null', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        '1 2 +',
        '--json',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.option, isNull);
      expect(rejection.candidates, isEmpty);
    });

    test("cx '1 2 +' --: a bare '--' after an operand is not an OptionSpec "
        'at all, option is null', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        '1 2 +',
        '--',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.token, equals('--'));
      expect(rejection.option, isNull);
      expect(rejection.candidates, isEmpty);
    });

    test('cx --json version: a known option read ahead of a literal child, '
        'option names its own spec, no ambiguity so candidates is empty', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        '--json',
        'version',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.option, equals(jsonOpt));
      expect(rejection.candidates, isEmpty);
    });

    test('cx --file p: ambiguous subtree, every reachable declaration '
        'agrees on the shape (eval rpn and eval infix share fileOpt), so '
        'option names that shared shape even though route stays null and '
        'candidates lists both routes', () {
      final rejection = _rejected(buildCalculatrixRouter(), ['--file', 'p']);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route, isNull);
      expect(rejection.option, equals(fileOpt));
      expect(
        rejection.candidates.map((r) => r.pattern),
        orderedEquals(['eval rpn', 'eval infix']),
      );
    });

    test('cx --x a b: ambiguous subtree, the reachable declarations '
        'genuinely differ in shape (a flag vs. a value option), so option '
        'is null but candidates still lists both routes', () {
      final router = CliRouter(globalOptions: const []);
      final flagX = OptionSpec.flag('x', abbr: null, repeatable: false);
      final valueX = OptionSpec.value(
        'x',
        abbr: null,
        required: false,
        repeatable: false,
      );
      router.cmd('a', (req) async => 0, options: [flagX], globals: false);
      router.cmd('b', (req) async => 0, options: [valueX], globals: false);

      final rejection = _rejected(router, ['--x', 'a', 'b']);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route, isNull);
      expect(rejection.option, isNull);
      expect(
        rejection.candidates.map((r) => r.pattern),
        orderedEquals(['a', 'b']),
      );
    });
  });

  group('missingValue: option is always the spec missing its value', () {
    test('cx eval rpn -f', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'eval',
        'rpn',
        '-f',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.missingValue));
      expect(rejection.option, equals(fileOpt));
      expect(rejection.candidates, isEmpty);
    });
  });

  group('unexpectedValue: option is always the flag\'s own spec', () {
    test('cx version --json=x', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'version',
        '--json=x',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.unexpectedValue));
      expect(rejection.option, equals(jsonOpt));
      expect(rejection.candidates, isEmpty);
    });
  });

  group('invalidShortOption: option is always null, candidates always '
      'empty', () {
    test('cx eval rpn -qh: a cluster, the token never resolves to a spec', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'eval',
        'rpn',
        '-qh',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.invalidShortOption));
      expect(rejection.option, isNull);
      expect(rejection.candidates, isEmpty);
    });

    test('cx eval rpn -fprog.rpn: an attached value on a short option', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'eval',
        'rpn',
        '-fprog.rpn',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.invalidShortOption));
      expect(rejection.option, isNull);
      expect(rejection.candidates, isEmpty);
    });
  });

  group('repeatedOption: option is always the repeated spec', () {
    test('cx eval rpn -f a.rpn --file=b.rpn', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'eval',
        'rpn',
        '-f',
        'a.rpn',
        '--file=b.rpn',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.repeatedOption));
      expect(rejection.option, equals(fileOpt));
      expect(rejection.candidates, isEmpty);
    });
  });

  group('missingRequiredOption: option always the spec never read, local '
      'or global', () {
    test('cx deploy with no --target: a route-local required option', () {
      final targetOpt = OptionSpec.value(
        'target',
        abbr: 't',
        required: true,
        repeatable: false,
      );
      final router = CliRouter(globalOptions: const []);
      router.cmd('deploy', (req) async => 0, options: [
        targetOpt,
      ], globals: false);

      final rejection = _rejected(router, ['deploy']);
      expect(rejection.kind, equals(CliRejectionKind.missingRequiredOption));
      expect(rejection.option, equals(targetOpt));
      expect(rejection.candidates, isEmpty);
    });

    test('cx deploy with no --target: a required GLOBAL option, the route '
        'accepts globals (globals: true) and has no local options of its '
        'own at all', () {
      final targetOpt = OptionSpec.value(
        'target',
        abbr: null,
        required: true,
        repeatable: false,
      );
      final router = CliRouter(globalOptions: [targetOpt]);
      router.cmd('deploy', (req) async => 0, options: const [], globals: true);

      final rejection = _rejected(router, ['deploy']);
      expect(rejection.kind, equals(CliRejectionKind.missingRequiredOption));
      expect(rejection.route?.pattern, equals('deploy'));
      expect(rejection.option, equals(targetOpt));
      expect(rejection.candidates, isEmpty);
    });

    test('cx deploy with no --target and no --region: two missing '
        'route-local required options, only the first in spec order '
        '(declaration order in the options list) is reported', () {
      final targetOpt = OptionSpec.value(
        'target',
        abbr: 't',
        required: true,
        repeatable: false,
      );
      final regionOpt = OptionSpec.value(
        'region',
        abbr: null,
        required: true,
        repeatable: false,
      );
      final router = CliRouter(globalOptions: const []);
      router.cmd('deploy', (req) async => 0, options: [
        targetOpt,
        regionOpt,
      ], globals: false);

      final rejection = _rejected(router, ['deploy']);
      expect(rejection.kind, equals(CliRejectionKind.missingRequiredOption));
      expect(rejection.option, equals(targetOpt));
      expect(rejection.candidates, isEmpty);
    });

    test('cx deploy with no --target and no --region: a missing route-local '
        'required option and a missing required global, both unread; spec '
        'order checks the route\'s own options before the globals it '
        'accepts, so the local one is reported', () {
      final targetOpt = OptionSpec.value(
        'target',
        abbr: 't',
        required: true,
        repeatable: false,
      );
      final regionOpt = OptionSpec.value(
        'region',
        abbr: null,
        required: true,
        repeatable: false,
      );
      final router = CliRouter(globalOptions: [regionOpt]);
      router.cmd('deploy', (req) async => 0, options: [
        targetOpt,
      ], globals: true);

      final rejection = _rejected(router, ['deploy']);
      expect(rejection.kind, equals(CliRejectionKind.missingRequiredOption));
      expect(rejection.option, equals(targetOpt));
      expect(rejection.candidates, isEmpty);
    });
  });
}
