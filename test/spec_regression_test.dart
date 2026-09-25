// Translated regressions from calculatrix_cli.md section 13 (rows marked
// with a dagger are 0.1.1 behaviors that the new grammar deliberately
// changes), plus G11 (negative numbers are operands, never options), in full
// router context.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('regression: a value option with no value, at the end', () {
    test('cx eval rpn -f used to bind path="true"; now missingValue', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['eval', 'rpn', '-f']);
      expect(outcome, isA<CliRejection>());
      expect((outcome as CliRejection).kind, equals(CliRejectionKind.missingValue));
    });
  });

  group('regression: --no-x negation is gone', () {
    test('cx eval rpn --no-file x used to set file=false; now unknownOption', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['eval', 'rpn', '--no-file', 'x']);
      expect(outcome, isA<CliRejection>());
      expect((outcome as CliRejection).kind, equals(CliRejectionKind.unknownOption));
    });
  });

  group('regression: repeated non-repeatable options no longer let the last '
      'one win', () {
    test('cx eval rpn -f a.rpn -f b.rpn used to keep b.rpn; now '
        'repeatedOption', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(
        ['eval', 'rpn', '-f', 'a.rpn', '-f', 'b.rpn'],
      );
      expect(outcome, isA<CliRejection>());
      expect(
        (outcome as CliRejection).kind,
        equals(CliRejectionKind.repeatedOption),
      );
    });
  });

  group('regression: a flag never takes an attached value', () {
    test('cx --json=garbage version used to be accepted (exit 0); now '
        'unexpectedValue', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['--json=garbage', 'version']);
      expect(outcome, isA<CliRejection>());
      expect(
        (outcome as CliRejection).kind,
        equals(CliRejectionKind.unexpectedValue),
      );
    });
  });

  group('regression: a leftover operand is never silently ignored', () {
    test('cx version junk used to be ignored; now extraArgument', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['version', 'junk']);
      expect(outcome, isA<CliRejection>());
      expect(
        (outcome as CliRejection).kind,
        equals(CliRejectionKind.extraArgument),
      );
    });
  });

  group('regression: -abc no longer expands to a short-option cluster', () {
    test('cx eval rpn -qh used to set {q:true,h:true}; now '
        'invalidShortOption', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['eval', 'rpn', '-qh']);
      expect(outcome, isA<CliRejection>());
      expect(
        (outcome as CliRejection).kind,
        equals(CliRejectionKind.invalidShortOption),
      );
    });
  });

  group('regression: -o=value is no longer a valid short-option form', () {
    test('cx eval rpn -f=prog.rpn used to bind f="prog.rpn"; now '
        'invalidShortOption', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['eval', 'rpn', '-f=prog.rpn']);
      expect(outcome, isA<CliRejection>());
      expect(
        (outcome as CliRejection).kind,
        equals(CliRejectionKind.invalidShortOption),
      );
    });
  });

  group('G11: negative numbers are operands, never options', () {
    test('cx -1 : the shortcut binds program="-1"', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['-1']);
      expect(outcome, isA<CliResolution>());
      expect((outcome as CliResolution).params['program'], equals('-1'));
    });

    test("cx '-1 2 +' : the shortcut binds the whole expression", () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['-1 2 +']);
      expect(outcome, isA<CliResolution>());
      expect(
        (outcome as CliResolution).params['program'],
        equals('-1 2 +'),
      );
    });

    test('cx -2.5 : a negative float is an operand', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['-2.5']);
      expect(outcome, isA<CliResolution>());
      expect((outcome as CliResolution).params['program'], equals('-2.5'));
    });

    test('cx --3 : not shaped like an option (no letter after --), an '
        'operand', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['--3']);
      expect(outcome, isA<CliResolution>());
      expect((outcome as CliResolution).params['program'], equals('--3'));
    });

    test('cx eval rpn -1 : a negative number after a route is still an '
        'operand, bound as the program', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['eval', 'rpn', '-1']);
      expect(outcome, isA<CliResolution>());
      expect((outcome as CliResolution).params['program'], equals('-1'));
    });
  });
}
