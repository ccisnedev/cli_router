// Shared fixtures for cli_router 0.2.0 tests. Not a `_test.dart` file, so
// `dart test` does not try to run it as its own suite.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

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

  final eval = CliRouter(globalOptions: globalOptions);
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

  final commands = CliRouter(globalOptions: globalOptions);
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

final permuteVerboseOpt = OptionSpec.flag(
  'verbose',
  abbr: 'v',
  repeatable: false,
);
final permuteForceOpt = OptionSpec.flag('force', abbr: null, repeatable: false);
final permuteTagOpt = OptionSpec.value(
  'tag',
  abbr: 't',
  required: false,
  repeatable: false,
);

/// A small router with a trailing `*` wildcard and multi parameter routes,
/// used by the `OptionOrdering.permute` tests (issue #8) to exercise
/// permutation next to required parameters and a wildcard, which
/// [buildCalculatrixRouter] does not have. No globals: each route declares
/// only the options it needs.
CliRouter buildPermuteDemoRouter() {
  final router = CliRouter(globalOptions: const []);
  router.cmd(
    'run *',
    (req) async => 0,
    options: [permuteVerboseOpt],
    globals: false,
  );
  router.cmd(
    'sync <mode> *',
    (req) async => 0,
    options: [permuteForceOpt],
    globals: false,
  );
  router.cmd(
    'copy <src> <dst>',
    (req) async => 0,
    options: [permuteForceOpt],
    globals: false,
  );
  router.cmd(
    'build <target>',
    (req) async => 0,
    options: [permuteVerboseOpt, permuteTagOpt],
    globals: false,
  );
  return router;
}

/// Resolves [args] under `OptionOrdering.strict`, exactly as
/// `router.resolve(args, ordering: OptionOrdering.strict)` used to, and
/// returns that same outcome unchanged.
///
/// Additionally, whenever that strict resolution succeeds, this also
/// resolves [args] under the default `OptionOrdering.permute` and asserts
/// the two outcomes agree: same route, same params, same rest, and the same
/// options read (by name, abbreviation, value and how the value was
/// written), independent of where in argv each option ended up after
/// permutation. This makes every pinned strict-mode success in the suite
/// double as a differential check: whatever strict mode accepts, permute
/// mode must accept too, with an identical result (issue #8, review fix 4).
///
/// A strict-mode rejection is returned as-is, with no permute-mode check:
/// permute mode is free to accept an argv that strict mode rejects (that is
/// the entire point of permutation), so there is nothing to compare there.
CliOutcome resolveStrict(CliRouter router, List<String> args) {
  final strict = router.resolve(args, ordering: OptionOrdering.strict);
  if (strict is! CliResolution) return strict;

  final permuted = router.resolve(args);
  expect(
    permuted,
    isA<CliResolution>(),
    reason:
        'permute mode must accept whatever strict mode accepts, for $args, '
        'got $permuted',
  );
  final resolution = permuted as CliResolution;
  expect(
    resolution.route.pattern,
    equals(strict.route.pattern),
    reason: 'route pattern diverged between strict and permute for $args',
  );
  expect(
    resolution.route.hasWildcard,
    equals(strict.route.hasWildcard),
    reason: 'route shape diverged between strict and permute for $args',
  );
  expect(
    resolution.params,
    equals(strict.params),
    reason: 'params diverged between strict and permute for $args',
  );
  expect(
    resolution.rest,
    equals(strict.rest),
    reason: 'rest diverged between strict and permute for $args',
  );
  expect(
    _optionSignatures(resolution.options),
    equals(_optionSignatures(strict.options)),
    reason: 'options diverged between strict and permute for $args',
  );
  return strict;
}

/// A structural projection of [options], for comparing across strict and
/// permute mode. [ParsedOption.argvIndex] is deliberately left out:
/// permutation moves tokens around by design, so the same option can sit at
/// a different argv index in each mode while still being the same read.
List<({String name, String? abbr, String? value, bool attached})>
_optionSignatures(List<ParsedOption> options) => [
  for (final o in options)
    (
      name: o.spec.name,
      abbr: o.spec.abbr,
      value: o.value,
      attached: o.attached,
    ),
];
