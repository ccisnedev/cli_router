// Grammar table of issue #6 / spec 8.2: value options, flags, missing
// value, unexpected value, invalid short options, repeated options.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

import 'support.dart';

CliResolution _resolveOk(CliRouter router, List<String> args) {
  final outcome = router.resolve(args);
  expect(outcome, isA<CliResolution>(), reason: 'for $args, got $outcome');
  return outcome as CliResolution;
}

CliRejection _resolveRejected(CliRouter router, List<String> args) {
  final outcome = router.resolve(args);
  expect(outcome, isA<CliRejection>(), reason: 'for $args, got $outcome');
  return outcome as CliRejection;
}

void main() {
  group('value options: --x v, --x=v, -x v', () {
    for (final args in [
      ['eval', 'rpn', '--file', 'prog.rpn'],
      ['eval', 'rpn', '--file=prog.rpn'],
      ['eval', 'rpn', '-f', 'prog.rpn'],
    ]) {
      test(args.join(' '), () {
        final router = buildCalculatrixRouter();
        final result = _resolveOk(router, args);
        expect(result.options, hasLength(1));
        final opt = result.options.single;
        expect(opt.spec.name, equals('file'));
        expect(opt.value, equals('prog.rpn'));
      });
    }

    test('--x= gives the empty string', () {
      final router = buildCalculatrixRouter();
      final result = _resolveOk(router, ['eval', 'rpn', '--file=']);
      expect(result.options.single.value, equals(''));
      expect(result.options.single.attached, isTrue);
    });

    test('value option at the end: missingValue', () {
      final router = buildCalculatrixRouter();
      final rejection = _resolveRejected(router, ['eval', 'rpn', '--file']);
      expect(rejection.kind, equals(CliRejectionKind.missingValue));
    });

    test('value option followed by something option-like: missingValue', () {
      final router = buildCalculatrixRouter();
      final rejection = _resolveRejected(router, [
        'eval',
        'rpn',
        '--file',
        '--stdin',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.missingValue));
    });

    test('a value that looks like an option must be attached with =', () {
      final router = buildCalculatrixRouter();
      final result = _resolveOk(router, ['eval', 'rpn', '--file=-x.rpn']);
      expect(result.options.single.value, equals('-x.rpn'));
    });
  });

  group('flags: --x or -x present; --x=v is unexpectedValue', () {
    test('--stdin is present', () {
      final router = buildCalculatrixRouter();
      final result = _resolveOk(router, ['eval', 'rpn', '--stdin']);
      expect(result.options.single.spec.name, equals('stdin'));
      expect(result.options.single.value, isNull);
    });

    test('--stdin=true is unexpectedValue', () {
      final router = buildCalculatrixRouter();
      final rejection = _resolveRejected(router, [
        'eval',
        'rpn',
        '--stdin=true',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.unexpectedValue));
    });

    test('--stdin true takes the operand as the program, not as a value', () {
      final router = buildCalculatrixRouter();
      final result = _resolveOk(router, ['eval', 'rpn', '--stdin', 'true']);
      expect(result.params['program'], equals('true'));
      expect(result.options.where((o) => o.spec.name == 'stdin'), hasLength(1));
    });

    test('--no-x has no special meaning: unknownOption unless declared', () {
      final router = buildCalculatrixRouter();
      final rejection = _resolveRejected(router, [
        'eval',
        'rpn',
        '--no-file',
        'x',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
    });
  });

  group('short options stand alone (G9)', () {
    test('-qh is invalidShortOption', () {
      final router = buildCalculatrixRouter();
      final rejection = _resolveRejected(router, ['eval', 'rpn', '-qh']);
      expect(rejection.kind, equals(CliRejectionKind.invalidShortOption));
    });

    test('-fvalue is invalidShortOption', () {
      final router = buildCalculatrixRouter();
      final rejection = _resolveRejected(router, ['eval', 'rpn', '-fprog.rpn']);
      expect(rejection.kind, equals(CliRejectionKind.invalidShortOption));
    });

    test('-f=value is invalidShortOption (no such form)', () {
      final router = buildCalculatrixRouter();
      final rejection = _resolveRejected(router, [
        'eval',
        'rpn',
        '-f=prog.rpn',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.invalidShortOption));
    });

    test(
      'a two-letter cluster of unknown letters is still invalidShortOption',
      () {
        final router = buildCalculatrixRouter();
        final rejection = _resolveRejected(router, ['eval', 'rpn', '-xy']);
        expect(rejection.kind, equals(CliRejectionKind.invalidShortOption));
      },
    );
  });

  group('repeated options', () {
    test('a repeated non-repeatable value option, same spelling', () {
      final router = buildCalculatrixRouter();
      final rejection = _resolveRejected(router, [
        'eval',
        'rpn',
        '-f',
        'a.rpn',
        '-f',
        'b.rpn',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.repeatedOption));
    });

    test(
      'a repeated non-repeatable option, mixing long and short spelling',
      () {
        final router = buildCalculatrixRouter();
        final rejection = _resolveRejected(router, [
          'eval',
          'rpn',
          '--file',
          'a.rpn',
          '-f',
          'b.rpn',
        ]);
        expect(rejection.kind, equals(CliRejectionKind.repeatedOption));
      },
    );

    test('a repeatable option can occur more than once', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'build',
        (req) async => 0,
        options: [
          OptionSpec.value(
            'define',
            abbr: 'd',
            required: false,
            repeatable: true,
          ),
        ],
        globals: false,
      );
      final outcome = router.resolve(['build', '-d', 'a', '-d', 'b']);
      expect(outcome, isA<CliResolution>());
      expect((outcome as CliResolution).options, hasLength(2));
    });

    test('a repeatable option keeps every occurrence losslessly, in argv '
        'order, with its spelling, index, value and attachment', () {
      final define = OptionSpec.value(
        'define',
        abbr: 'd',
        required: false,
        repeatable: true,
      );
      final router = CliRouter(globalOptions: const []);
      router.cmd('build', (req) async => 0, options: [define], globals: false);

      final argv = [
        'build',
        '--define=a',
        '-d',
        'b',
        '--define',
        'a',
        '--define=',
      ];
      final outcome = router.resolve(argv);

      expect(outcome, isA<CliResolution>());
      final occurrences = (outcome as CliResolution).options;
      for (final o in occurrences) {
        expect(o.written, equals(argv[o.argvIndex]));
      }
      expect(
        occurrences
            .map((o) => (o.spec, o.written, o.argvIndex, o.value, o.attached))
            .toList(),
        equals([
          (define, '--define=a', 1, 'a', true),
          (define, '-d', 2, 'b', false),
          (define, '--define', 4, 'a', false),
          (define, '--define=', 6, '', true),
        ]),
      );
    });
  });

  group('unknown and required options', () {
    test('an option not declared anywhere is unknownOption', () {
      final router = buildCalculatrixRouter();
      final rejection = _resolveRejected(router, [
        'eval',
        'rpn',
        '--trace',
        '1 2 +',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
    });

    test('an option declared elsewhere, not by the resolved route, is '
        'unknownOption naming the route', () {
      final router = buildCalculatrixRouter();
      // --category belongs to `commands list`, not to `commands show <name>`.
      final rejection = _resolveRejected(router, [
        'commands',
        'show',
        '--category',
        'matrix',
        'power',
      ]);
      expect(rejection.kind, equals(CliRejectionKind.unknownOption));
    });

    test('a required option absent is missingRequiredOption', () {
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
      final rejection = _resolveRejected(router, ['deploy']);
      expect(rejection.kind, equals(CliRejectionKind.missingRequiredOption));
    });
  });
}
