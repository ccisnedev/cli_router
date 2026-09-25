// Shared fixtures for cli_router 0.2.0 tests. Not a `_test.dart` file, so
// `dart test` does not try to run it as its own suite.
import 'package:cli_router/cli_router.dart';

final jsonOpt = OptionSpec.flag('json', abbr: null, repeatable: false);
final quietOpt = OptionSpec.flag('quiet', abbr: 'q', repeatable: false);
final helpOpt = OptionSpec.flag('help', abbr: 'h', repeatable: false);
final globalOptions = <OptionSpec>[jsonOpt, quietOpt, helpOpt];

final fileOpt = OptionSpec.value(
  'file',
  abbr: 'f',
  required: false,
  repeatable: false,
);
final stdinOpt = OptionSpec.flag('stdin', abbr: null, repeatable: false);

/// A router shaped like the calculatrix catalog (spec section 5): a root
/// banner, a shortcut, an `eval` module and a `commands` module. Reused by
/// the grammar, POSIX-order, rejection and spec-regression tests, so those
/// tests exercise the same trie a real consumer would build.
CliRouter buildCalculatrixRouter() {
  final router = CliRouter(globalOptions: globalOptions);

  router.cmd('', (req) async => 0, options: const [], globals: true);
  router.cmd('version', (req) async => 0, options: const [], globals: true);
  router.cmd('doctor', (req) async => 0, options: const [], globals: true);
  router.cmd(
    'upgrade',
    (req) async => 0,
    options: [
      OptionSpec.flag('plan', abbr: null, repeatable: false),
      OptionSpec.flag('apply', abbr: null, repeatable: false),
    ],
    globals: true,
  );
  router.cmd(
    'help [<topic>]',
    (req) async => 0,
    options: const [],
    globals: true,
  );

  final eval = CliRouter();
  eval.cmd(
    'rpn [<program>]',
    (req) async => 0,
    options: [fileOpt, stdinOpt],
    globals: true,
  );
  eval.cmd(
    'infix [<expression>]',
    (req) async => 0,
    options: [fileOpt, stdinOpt],
    globals: true,
  );
  router.mount('eval', eval);

  final commands = CliRouter();
  commands.cmd(
    'list',
    (req) async => 0,
    options: [
      OptionSpec.value(
        'category',
        abbr: null,
        required: false,
        repeatable: false,
      ),
    ],
    globals: true,
  );
  commands.cmd(
    'show <name>',
    (req) async => 0,
    options: const [],
    globals: true,
  );
  commands.cmd(
    'search <text>',
    (req) async => 0,
    options: const [],
    globals: true,
  );
  router.mount('commands', commands);

  // The shortcut: a root route with a parameter, no options, no globals.
  router.cmd('<program>', (req) async => 0, options: const [], globals: false);

  return router;
}
