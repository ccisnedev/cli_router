// Rejection kinds of spec 8.5 that are not about options: unknownCommand,
// extraArgument, incomplete, missingArgument.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

import 'support.dart';

CliRejection _rejected(CliRouter router, List<String> args) {
  final outcome = router.resolve(args);
  expect(outcome, isA<CliRejection>(), reason: 'for $args, got $outcome');
  return outcome as CliRejection;
}

void main() {
  group(
    'unknownCommand: root, the word is no route, root has no parameter',
    () {
      test('a bad word at the root of a router with no parameter route', () {
        final router = CliRouter();
        router.cmd(
          'version',
          (req) async => 0,
          options: const [],
          globals: false,
        );
        final rejection = _rejected(router, ['bogus']);
        expect(rejection.kind, equals(CliRejectionKind.unknownCommand));
        expect(rejection.consumed, isEmpty);
      });

      test('a router with a root parameter never reaches unknownCommand', () {
        // The shortcut absorbs any word, per G3.
        final router = buildCalculatrixRouter();
        final outcome = router.resolve(['totally-unknown-word']);
        expect(outcome, isA<CliResolution>());
        expect(
          (outcome as CliResolution).params['program'],
          equals('totally-unknown-word'),
        );
      });
    },
  );

  group('extraArgument: terminal node, an operand left over', () {
    test('cx version junk', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['version', 'junk']);
      expect(rejection.kind, equals(CliRejectionKind.extraArgument));
      expect(rejection.route?.pattern, equals('version'));
    });

    test('an extra operand after a bound optional parameter', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['eval', 'rpn', '1 2 +', 'extra']);
      expect(rejection.kind, equals(CliRejectionKind.extraArgument));
    });

    test('cx 1 2 + unquoted: the shortcut takes exactly one operand (G4)', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['1', '2', '+']);
      expect(rejection.kind, equals(CliRejectionKind.extraArgument));
    });
  });

  group('incomplete: non-terminal node, the operand fits no child', () {
    test('cx commands shwo power', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['commands', 'shwo', 'power']);
      expect(rejection.kind, equals(CliRejectionKind.incomplete));
      expect(rejection.consumed, equals(['commands']));
    });

    test('cx commands: end of argv at a node with only literal children', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['commands']);
      expect(rejection.kind, equals(CliRejectionKind.incomplete));
    });

    test('cx eval: end of argv, lists rpn and infix', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['eval']);
      expect(rejection.kind, equals(CliRejectionKind.incomplete));
      expect(rejection.consumed, equals(['eval']));
    });
  });

  group('missingArgument: end of argv at a node that needs a parameter', () {
    test('cx commands show', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, ['commands', 'show']);
      expect(rejection.kind, equals(CliRejectionKind.missingArgument));
      expect(rejection.consumed, equals(['commands', 'show']));
    });
  });

  group('rejections always carry the consumed literals and options so far', () {
    test('options parsed before a later rejection are preserved', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(router, [
        'commands',
        'show',
        '--json',
        'power',
        'extra',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.extraArgument));
      expect(rejection.options.single.spec.name, equals('json'));
      expect(rejection.consumed, equals(['commands', 'show']));
    });
  });
}
