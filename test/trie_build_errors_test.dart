// Build-time (registration) errors, per issue #6 section 1 and spec 8.1/8.2.
// These must throw immediately when the CLI is built, never at run time.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

void main() {
  group('build-time errors: trie shape (spec 8.1)', () {
    test('two routes with the same pattern', () {
      final router = CliRouter();
      router.cmd('show', (req) async => 0, options: const [], globals: false);
      expect(
        () => router.cmd(
          'show',
          (req) async => 0,
          options: const [],
          globals: false,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('two routes with the same pattern via mount', () {
      final router = CliRouter();
      router.cmd(
        'math show',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      final math = CliRouter();
      math.cmd(
        'show',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      expect(
        () => router.mount('math', math),
        throwsA(isA<StateError>()),
      );
    });

    test('two parameters with different names at the same position', () {
      final router = CliRouter();
      router.cmd(
        'show <id>',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      expect(
        () => router.cmd(
          'show <name>',
          (req) async => 0,
          options: const [],
          globals: false,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('reusing the same parameter name at the same position is fine', () {
      final router = CliRouter();
      router.cmd(
        'show <id>',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      expect(
        () => router.cmd(
          'show <id> details',
          (req) async => 0,
          options: const [],
          globals: false,
        ),
        returnsNormally,
      );
    });

    test('[<name>] anywhere but last', () {
      final router = CliRouter();
      expect(
        () => router.cmd(
          'eval [<program>] extra',
          (req) async => 0,
          options: const [],
          globals: false,
        ),
        throwsArgumentError,
      );
    });

    test('* anywhere but last', () {
      final router = CliRouter();
      expect(
        () => router.cmd(
          'files * extra',
          (req) async => 0,
          options: const [],
          globals: false,
        ),
        throwsArgumentError,
      );
    });

    test('a literal that looks like an option', () {
      final router = CliRouter();
      expect(
        () => router.cmd(
          'show --bad',
          (req) async => 0,
          options: const [],
          globals: false,
        ),
        throwsArgumentError,
      );
    });

    test('a literal that looks like an option, in a mount prefix', () {
      final router = CliRouter();
      final sub = CliRouter();
      sub.cmd('list', (req) async => 0, options: const [], globals: false);
      expect(() => router.mount('--bad', sub), throwsArgumentError);
    });

    test('a parameter and a wildcard cannot both sit at the same node', () {
      final router = CliRouter();
      router.cmd(
        'eval <program>',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      expect(
        () => router.cmd(
          'eval *',
          (req) async => 0,
          options: const [],
          globals: false,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('build-time errors: option scope (spec 8.2)', () {
    test('one option name with two shapes in the same route', () {
      final router = CliRouter();
      expect(
        () => router.cmd(
          'eval rpn',
          (req) async => 0,
          options: [
            OptionSpec.value(
              'file',
              abbr: 'f',
              required: false,
              repeatable: false,
            ),
            OptionSpec.flag('file', abbr: null, repeatable: false),
          ],
          globals: false,
        ),
        throwsArgumentError,
      );
    });

    test('one abbreviation with two shapes in the same route', () {
      final router = CliRouter();
      expect(
        () => router.cmd(
          'eval rpn',
          (req) async => 0,
          options: [
            OptionSpec.value(
              'file',
              abbr: 'f',
              required: false,
              repeatable: false,
            ),
            OptionSpec.flag('force', abbr: 'f', repeatable: false),
          ],
          globals: false,
        ),
        throwsArgumentError,
      );
    });

    test('a route option colliding with a global option, same name', () {
      final router = CliRouter(
        globalOptions: [OptionSpec.flag('json', abbr: null, repeatable: false)],
      );
      expect(
        () => router.cmd(
          'eval rpn',
          (req) async => 0,
          options: [
            OptionSpec.value(
              'json',
              abbr: null,
              required: false,
              repeatable: false,
            ),
          ],
          globals: true,
        ),
        throwsArgumentError,
      );
    });

    test(
      'a route option colliding with a global by shape is fine when globals '
      'is false',
      () {
        final router = CliRouter(
          globalOptions: [
            OptionSpec.flag('json', abbr: null, repeatable: false),
          ],
        );
        expect(
          () => router.cmd(
            'eval rpn',
            (req) async => 0,
            options: [
              OptionSpec.value(
                'json',
                abbr: null,
                required: false,
                repeatable: false,
              ),
            ],
            globals: false,
          ),
          returnsNormally,
        );
      },
    );

    test('same option declared identically twice in the same route list', () {
      final router = CliRouter();
      final file = OptionSpec.value(
        'file',
        abbr: 'f',
        required: false,
        repeatable: false,
      );
      expect(
        () => router.cmd(
          'eval rpn',
          (req) async => 0,
          options: [file, file],
          globals: false,
        ),
        throwsArgumentError,
      );
    });
  });
}
