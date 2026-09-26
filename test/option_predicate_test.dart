// G11: a token looks like an option iff it is `-` + letter, `--` + letter,
// or exactly `--`. Negative numbers and similar tokens are operands.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

void main() {
  group('looksLikeOption (G11)', () {
    const optionLike = [
      '-a',
      '-Z',
      '--file',
      '--file=value',
      '-f=value',
      '--',
      '-q',
    ];

    const operandLike = [
      '-1',
      '-2.5',
      '-.5',
      '-1e3',
      '-',
      '-1 2 +',
      '--3',
      '-?',
      '--?',
      '---name',
      '->ARRY',
      '-[...]',
      'plain text',
      '',
      '5',
    ];

    for (final token in optionLike) {
      test('${_label(token)} looks like an option', () {
        expect(looksLikeOption(token), isTrue);
      });
    }

    for (final token in operandLike) {
      test('${_label(token)} is an operand, not an option', () {
        expect(looksLikeOption(token), isFalse);
      });
    }
  });
}

String _label(String s) => s.isEmpty ? '(empty string)' : s;
