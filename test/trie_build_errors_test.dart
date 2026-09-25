// Build-time (registration) errors, per issue #6 section 1 and spec 8.1/8.2.
// These must throw immediately when the CLI is built, never at run time.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

void main() {
  group('build-time errors: trie shape (spec 8.1)', () {
    test('two routes with the same pattern', () {
      final router = CliRouter(globalOptions: const []);
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
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'math show',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      final math = CliRouter(globalOptions: const []);
      math.cmd('show', (req) async => 0, options: const [], globals: false);
      expect(() => router.mount('math', math), throwsA(isA<StateError>()));
    });

    test('two parameters with different names at the same position', () {
      final router = CliRouter(globalOptions: const []);
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
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'show <id>',
        (req) async => 0,
        options: const [],
        globals: false,
      );
      expect(
        () => router.cmd(
          'show <id> <detail>',
          (req) async => 0,
          options: const [],
          globals: false,
        ),
        returnsNormally,
      );
    });

    test('a literal segment after a required parameter is an ArgumentError '
        '(grammar G: route words come before operands)', () {
      final router = CliRouter(globalOptions: const []);
      expect(
        () => router.cmd(
          'show <id> details',
          (req) async => 0,
          options: const [],
          globals: false,
        ),
        throwsArgumentError,
      );
    });

    test('[<name>] anywhere but last', () {
      final router = CliRouter(globalOptions: const []);
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
      final router = CliRouter(globalOptions: const []);
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
      final router = CliRouter(globalOptions: const []);
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
      final router = CliRouter(globalOptions: const []);
      final sub = CliRouter(globalOptions: const []);
      sub.cmd('list', (req) async => 0, options: const [], globals: false);
      expect(() => router.mount('--bad', sub), throwsArgumentError);
    });

    test('a parameter and a wildcard cannot both sit at the same node', () {
      final router = CliRouter(globalOptions: const []);
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
      final router = CliRouter(globalOptions: const []);
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
      final router = CliRouter(globalOptions: const []);
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

    test('a route option colliding with a global option, same name, is an '
        'ArgumentError even when globals is false (no shadowing)', () {
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
          globals: false,
        ),
        throwsArgumentError,
      );
    });

    test('a route option colliding with a global option, same abbreviation, '
        'is an ArgumentError even when globals is false (no shadowing)', () {
      final router = CliRouter(
        globalOptions: [OptionSpec.flag('quiet', abbr: 'q', repeatable: false)],
      );
      expect(
        () => router.cmd(
          'local',
          (req) async => 0,
          options: [
            OptionSpec.value(
              'quality',
              abbr: 'q',
              required: false,
              repeatable: false,
            ),
          ],
          globals: false,
        ),
        throwsArgumentError,
      );
    });

    test('same option declared identically twice in the same route list', () {
      final router = CliRouter(globalOptions: const []);
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

  group('build-time errors: sibling option scope by shape (spec 8.2)', () {
    test('two routes sharing a param chain declaring the same option name '
        'with different shapes is an ArgumentError', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'go',
        (req) async => 0,
        options: [OptionSpec.flag('x', abbr: null, repeatable: false)],
        globals: false,
      );
      expect(
        () => router.cmd(
          'go <arg>',
          (req) async => 0,
          options: [
            OptionSpec.value(
              'x',
              abbr: null,
              required: false,
              repeatable: false,
            ),
          ],
          globals: false,
        ),
        throwsArgumentError,
      );
    });

    test('two routes sharing a param chain declaring the same abbreviation '
        'with different shapes is an ArgumentError, even under different '
        'names', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'go',
        (req) async => 0,
        options: [OptionSpec.flag('extra', abbr: 'x', repeatable: false)],
        globals: false,
      );
      expect(
        () => router.cmd(
          'go <arg>',
          (req) async => 0,
          options: [
            OptionSpec.value(
              'exec',
              abbr: 'x',
              required: false,
              repeatable: false,
            ),
          ],
          globals: false,
        ),
        throwsArgumentError,
      );
    });

    test('two routes sharing a param chain declaring the same option with '
        'the identical shape is fine (it is the same option)', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'go',
        (req) async => 0,
        options: [OptionSpec.flag('x', abbr: null, repeatable: false)],
        globals: false,
      );
      expect(
        () => router.cmd(
          'go <arg>',
          (req) async => 0,
          options: [OptionSpec.flag('x', abbr: null, repeatable: false)],
          globals: false,
        ),
        returnsNormally,
      );
    });

    test('the same option name with different shapes on unrelated branches '
        '(not reachable through each other via params) is fine', () {
      final router = CliRouter(globalOptions: const []);
      router.cmd(
        'alpha',
        (req) async => 0,
        options: [OptionSpec.flag('x', abbr: null, repeatable: false)],
        globals: false,
      );
      expect(
        () => router.cmd(
          'beta',
          (req) async => 0,
          options: [
            OptionSpec.value(
              'x',
              abbr: null,
              required: false,
              repeatable: false,
            ),
          ],
          globals: false,
        ),
        returnsNormally,
      );
    });
  });
}
