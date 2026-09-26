// The SDK previously parsed CliRejection.message (documented as "for
// logging") with regexes to recover the positional name and the offending
// argv token. That is untyped and breaks silently if the wording changes.
// This adds two typed fields to CliRejection instead:
//
// - `argument` (String?): the positional name implicated by the rejection.
// - `token` (String?): the offending argv token.
//
// Every CliRejectionKind is covered here, asserting exactly which of the
// two fields is guaranteed non-null for that kind, and which is guaranteed
// null, per the doc comments on CliRejectionKind and CliRejection.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

import 'support.dart';

CliRejection _rejected(CliRouter router, List<String> args) {
  final outcome = router.resolve(args);
  expect(outcome, isA<CliRejection>(), reason: 'for $args, got $outcome');
  return outcome as CliRejection;
}

void main() {
  group('unknownCommand: token is the unmatched word, argument is null', () {
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
      expect(rejection.token, equals('bogus'));
      expect(rejection.argument, isNull);
    });
  });

  group('extraArgument: token is the leftover operand, argument is null', () {
    test('cx version junk', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'version',
        'junk',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.extraArgument));
      expect(rejection.token, equals('junk'));
      expect(rejection.argument, isNull);
    });
  });

  group('incomplete: token only when a specific token failed to continue', () {
    test('cx commands shwo power: token is the word that did not continue', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'commands',
        'shwo',
        'power',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.incomplete));
      expect(rejection.token, equals('shwo'));
      expect(rejection.argument, isNull);
    });

    test('cx commands: argv ran out at a literal-only node, no token', () {
      final rejection = _rejected(buildCalculatrixRouter(), ['commands']);
      expect(rejection.kind, equals(CliRejectionKind.incomplete));
      expect(rejection.token, isNull);
      expect(rejection.argument, isNull);
    });

    test('cx eval: argv ran out at a literal-only node, no token', () {
      final rejection = _rejected(buildCalculatrixRouter(), ['eval']);
      expect(rejection.kind, equals(CliRejectionKind.incomplete));
      expect(rejection.token, isNull);
    });
  });

  group('missingArgument: argument is the positional name, no token', () {
    test('cx commands show', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'commands',
        'show',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.missingArgument));
      expect(rejection.argument, equals('name'));
      expect(rejection.token, isNull);
    });

    test('cx commands search: a different route, a different name', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'commands',
        'search',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.missingArgument));
      expect(rejection.argument, equals('text'));
      expect(rejection.token, isNull);
    });
  });

  group('unknownOption: token is the option as written, argument is null', () {
    test('cx --json 1 2 +: rejected only once the route is known '
        '(optionsMismatch path)', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        '--json',
        '1 2 +',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
      expect(rejection.token, equals('--json'));
      expect(rejection.argument, isNull);
    });

    test('cx eval rpn --trace: undeclared anywhere (readOption path)', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'eval',
        'rpn',
        '--trace',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
      expect(rejection.token, equals('--trace'));
    });
  });

  group('misplacedOption: token is the misplaced option', () {
    test("cx '1 2 +' --json: option after the operand", () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        '1 2 +',
        '--json',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.token, equals('--json'));
      expect(rejection.argument, isNull);
    });

    test('cx --json version: option before a literal child', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        '--json',
        'version',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.token, equals('--json'));
    });
  });

  group('missingValue: token is the option missing its value', () {
    test('cx eval rpn -f', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'eval',
        'rpn',
        '-f',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.missingValue));
      expect(rejection.token, equals('-f'));
      expect(rejection.argument, isNull);
    });
  });

  group('unexpectedValue: token is the flag given a value', () {
    test('cx version --json=x', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'version',
        '--json=x',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.unexpectedValue));
      expect(rejection.token, equals('--json=x'));
      expect(rejection.argument, isNull);
    });
  });

  group('invalidShortOption: token is the malformed short token', () {
    test('cx eval rpn -qh: a cluster', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'eval',
        'rpn',
        '-qh',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.invalidShortOption));
      expect(rejection.token, equals('-qh'));
      expect(rejection.argument, isNull);
    });

    test('cx eval rpn -fprog.rpn: an attached value', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'eval',
        'rpn',
        '-fprog.rpn',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.invalidShortOption));
      expect(rejection.token, equals('-fprog.rpn'));
    });
  });

  group('repeatedOption: token is the repeated occurrence, not the first', () {
    // Both occurrences must be spelled differently, otherwise the token
    // value alone cannot distinguish the first occurrence from the second:
    // '-f' twice would pass whether the router reported the first '-f' or
    // the second one by mistake.
    test('cx eval rpn -f a.rpn --file=b.rpn: short then long', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'eval',
        'rpn',
        '-f',
        'a.rpn',
        '--file=b.rpn',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.repeatedOption));
      expect(rejection.token, equals('--file=b.rpn'));
      expect(rejection.argument, isNull);
    });

    test('cx eval rpn --file=a.rpn -f b.rpn: long then short', () {
      final rejection = _rejected(buildCalculatrixRouter(), [
        'eval',
        'rpn',
        '--file=a.rpn',
        '-f',
        'b.rpn',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.repeatedOption));
      expect(rejection.token, equals('-f'));
      expect(rejection.argument, isNull);
    });
  });

  group('missingRequiredOption: neither field applies, both null', () {
    test('cx deploy with no --target', () {
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
      expect(rejection.argument, isNull);
      expect(rejection.token, isNull);
    });
  });
}
