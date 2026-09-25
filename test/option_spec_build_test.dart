// Build-time validation of OptionSpec itself: an abbreviation must be
// exactly one letter, and the fields fixed by each constructor cannot be
// contradicted (no negatable/negated, ever).
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

void main() {
  group('OptionSpec.flag', () {
    test('never takes a value and is never required', () {
      final spec = OptionSpec.flag('json', abbr: null, repeatable: false);
      expect(spec.takesValue, isFalse);
      expect(spec.required, isFalse);
    });

    test('accepts a null abbreviation', () {
      final spec = OptionSpec.flag('json', abbr: null, repeatable: false);
      expect(spec.abbr, isNull);
    });

    test('accepts a one-letter abbreviation', () {
      final spec = OptionSpec.flag('quiet', abbr: 'q', repeatable: true);
      expect(spec.abbr, equals('q'));
      expect(spec.repeatable, isTrue);
    });

    test('rejects an abbreviation longer than one letter', () {
      expect(
        () => OptionSpec.flag('quiet', abbr: 'qq', repeatable: false),
        throwsArgumentError,
      );
    });

    test('rejects an empty-string abbreviation', () {
      expect(
        () => OptionSpec.flag('quiet', abbr: '', repeatable: false),
        throwsArgumentError,
      );
    });
  });

  group('OptionSpec.value', () {
    test('always takes a value', () {
      final spec = OptionSpec.value(
        'file',
        abbr: 'f',
        required: false,
        repeatable: false,
      );
      expect(spec.takesValue, isTrue);
    });

    test('required and repeatable are both settable', () {
      final spec = OptionSpec.value(
        'file',
        abbr: 'f',
        required: true,
        repeatable: true,
      );
      expect(spec.required, isTrue);
      expect(spec.repeatable, isTrue);
    });

    test('rejects an abbreviation longer than one letter', () {
      expect(
        () => OptionSpec.value(
          'file',
          abbr: 'fi',
          required: false,
          repeatable: false,
        ),
        throwsArgumentError,
      );
    });
  });
}
