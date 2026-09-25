[![pub package](https://img.shields.io/pub/v/cli_router.svg)](https://pub.dev/packages/cli_router)

# cli_router

A trie based router for CLIs, using **spaces** between segments instead of
`/`, with POSIX option ordering and a declarative, typed option schema.

> Designed for the MACSS ecosystem: define commands like routes
> (`cmd('module use-case', handler, options: [...], globals: true)`), nest
> routers with `mount`, and resolve an invocation to a route, its bound
> parameters, and every option that was read, losslessly.

Version 0.2.0 is a breaking rewrite of option parsing and resolution. See
[CHANGELOG.md](CHANGELOG.md) for the full list of changes if you are
upgrading from 0.1.x.

---

## Features

- `cmd('route subroute <id>', handler, options: [...], globals: true)` to
  register commands. Every behavior-changing detail (the route's own
  options, whether the router's global options apply) is a required, named,
  declared parameter — nothing is inferred or defaulted.
- `mount('prefix', subRouter)` to graft a subrouter under a single literal
  word, flattening transitively.
- Route patterns: literal words, required `<name>` parameters, a single
  trailing optional `[<name>]` parameter, or a single trailing `*` wildcard.
- POSIX option ordering: **route, then options, then operands**. `--` ends
  option parsing.
- A declarative option schema: `OptionSpec.flag` and `OptionSpec.value`,
  with `abbr`, `required` and `repeatable` all explicit.
- Lossless option parsing: every occurrence of every option is kept, in
  argv order, exactly as written.
- `resolve(argv)` is pure — no I/O, never throws for a malformed
  invocation — so it can be tested, or driven by something other than
  `run()`, without touching stdout/stderr/exit codes.
- Eleven rejection kinds, precisely defined (see below). The router only
  classifies; deciding what to print and which exit code to use is left to
  the caller.
- Shelf-like middleware with `use()`.

---

## Installation

In your `pubspec.yaml`:

```yaml
dependencies:
  cli_router: ^0.2.0
```

Or:

```bash
dart pub add cli_router
```

---

## Quick start

```dart
import 'dart:io';
import 'package:cli_router/cli_router.dart';

final dryRunOption = OptionSpec.flag('dry-run', repeatable: false);
final threadsOption =
    OptionSpec.value('threads', required: false, repeatable: false);

Future<void> main(List<String> args) async {
  final cli = CliRouter();

  cli.cmd(
    'module use-case <id>',
    (req) async {
      final id = req.param('id');
      final dryRun = req.option('dry-run') != null;
      final threads = int.tryParse(req.option('threads')?.value ?? '') ?? 1;
      req.stdout.writeln('id=$id dryRun=$dryRun threads=$threads');
      return 0;
    },
    options: [dryRunOption, threadsOption],
    globals: false,
    description: 'Main use-case for the module',
  );

  final code = await cli.run(
    args,
    onReject: (rejection) async {
      stderr.writeln('error: ${rejection.message ?? rejection.kind}');
      return 64; // EX_USAGE, your call, the router never picks one for you.
    },
  );
  exit(code);
}
```

Example invocation (options precede the operand):

```bash
dart run bin/main.dart module use-case --dry-run --threads 4 1234
```

---

## Route definition

- **Segments** are separated by **spaces**: `'users show <id>'`.
- **Required parameters**: `<id>` must be present, and captures exactly one
  token.
- **A trailing optional parameter**: `[<id>]`, only as the very last
  segment, captures the next token if there is one.
- **A trailing wildcard**: `*`, only as the very last segment, captures every
  remaining operand into `CliRequest.rest`.
- A route's own required `<name>` continuation cannot coexist with a
  `[<name>]` or `*` at the same position, and a `[<name>]`/`*` must be the
  last segment: both are build-time (registration) errors.

```dart
router.cmd('eval rpn [<program>]', handler, options: [...], globals: true);
router.cmd('run *', handler, options: const [], globals: false);
```

---

## Options: `OptionSpec` and `ParsedOption`

Every option is declared, not guessed:

```dart
final jsonOption = OptionSpec.flag('json', abbr: 'j', repeatable: false);
final fileOption = OptionSpec.value(
  'file',
  abbr: 'f',
  required: false,
  repeatable: true, // may occur more than once
);
```

- `OptionSpec.flag(name, {abbr, required repeatable})`: present or absent,
  never takes a value. A flag is never `required` — either it was read or it
  was not, there is no missing value to report.
- `OptionSpec.value(name, {abbr, required required, required repeatable})`:
  takes a value, via `--name value`, `--name=value`, or `-n value` (never
  `-n=value`, which is not a valid short form).

A router's own options apply to every route it declares with
`globals: true`:

```dart
final router = CliRouter(globalOptions: [jsonOption]);
router.cmd('version', handler, options: const [], globals: true);
router.cmd('eval rpn', handler, options: [fileOption], globals: true);
```

At `eval rpn`, both `--json` and `--file`/`-f` are in scope. At `version`,
only `--json` is.

Reading options back on a resolved request:

```dart
final id = req.param('id');           // a bound positional, or null
final file = req.option('file')?.value; // the first occurrence, or null
final allFiles = req.options
    .where((o) => o.spec.name == 'file')
    .map((o) => o.value);              // every occurrence, in order
```

### POSIX option ordering

A route's own tokens come first, then its options, then its operands
(required parameters that end the route, the optional trailing parameter,
or wildcard operands). An option written after an operand has already
started, or before the route word it is declared on, is `misplacedOption`:

```bash
cli eval rpn --json '1 2 +'   # valid: option before the operand
cli eval rpn '1 2 +' --json   # misplacedOption: option after the operand
```

`--` ends option parsing; every token after it is an operand, even if it
looks like an option.

### Which tokens count as options?

`looksLikeOption(token)` is the single predicate: `-` followed by a letter,
`--` followed by a letter, or exactly `--`. Negative numbers (`-1`, `-2.5`),
a bare `-`, and anything else are operands, never options, whether or not
they happen to be declared somewhere.

---

## Resolving and running

`resolve(argv)` is pure and returns a `CliOutcome`: either a `CliResolution`
(the matched route, bound `params`, `rest`, and every `ParsedOption`) or a
`CliRejection`.

```dart
final outcome = router.resolve(args);
switch (outcome) {
  case CliResolution(:final route, :final params, :final options):
    print('matched ${route.pattern} with $params');
  case CliRejection(:final kind, :final consumed, :final options):
    print('rejected: $kind after $consumed, options read so far: $options');
}
```

`run()` is the I/O entry point built on `resolve`: it dispatches to the
matched handler, or calls the required `onReject` for anything that did not
resolve. The router never maps a rejection to an exit code; that decision
belongs to `onReject`.

```dart
final code = await router.run(
  args,
  onReject: (rejection) async {
    stderr.writeln(rejection.message ?? rejection.kind.toString());
    return 64;
  },
);
```

### Rejection kinds

| Kind | Meaning |
| --- | --- |
| `unknownCommand` | The first token matches no route at all. |
| `extraArgument` | A resolved route was reached, but a leftover token fits nowhere in it. |
| `incomplete` | The invocation ends, or a token fits nothing, at a node that is not itself a route and has no pending required parameter. |
| `missingArgument` | The invocation ends at a node still waiting on a required parameter. |
| `unknownOption` | The token is option shaped but declared nowhere reachable. |
| `misplacedOption` | Declared, but not readable here: written too early or too late for the route it belongs to. |
| `missingValue` | A value option is the last token, or the next token is option shaped. |
| `unexpectedValue` | A flag was given a value (`--flag=x`); flags never take one. |
| `invalidShortOption` | A single-dash token is not exactly one letter (`-qh`, `-f=v`). |
| `repeatedOption` | A non-repeatable option occurred more than once, under any spelling. |
| `missingRequiredOption` | A required option was never read, decided only after every option on the invocation was read. |

`CliRejection.options` and `.consumed` always reflect everything read before
the rejection, including global options like `--help`, even at a node that
has not resolved to a route of its own yet:

```dart
// A router with 'eval rpn' and 'eval infix', and a global --help.
router.resolve(['eval', '--help']);
// -> CliRejection(incomplete, consumed: ['eval'], options: [ParsedOption(help)])
```

---

## Middlewares

```dart
cli.use((next) {
  return (req) async {
    final t0 = DateTime.now();
    final code = await next(req);
    final dt = DateTime.now().difference(t0);
    req.stderr.writeln(
      '[${DateTime.now().toIso8601String()}] '
      '"${req.route.pattern}" -> $code in ${dt.inMilliseconds}ms',
    );
    return code;
  };
});
```

---

## Modular example (the `example/` folder)

See [`example/example.dart`](example/example.dart) for a full, runnable
CLI built from separate modules (`user`, `order`, `system`), mounted under a
root router with a global `--help` option, a logging middleware, and a
`help` command that lists every registered route via `listCommands()`.

```bash
dart run example/example.dart user list --limit 5 --active
dart run example/example.dart user show 42
dart run example/example.dart order process --dry-run --threads 4 900
dart run example/example.dart order report daily
dart run example/example.dart order report monthly 2025-09
dart run example/example.dart system version
```

---

## Listing commands

```dart
for (final c in cli.listCommands()) {
  print('${c.command}${c.description == null ? '' : ' - ${c.description}'}');
}
```

`listCommands()` returns every registered route, mounts flattened in, with
its full pattern (mount prefixes included), description, and positional
parameter names. Formatting a help screen from this is an application (or
`modular_cli_sdk`) concern; the router does not print anything itself.

---

## Compile to executable

- **Windows**
  ```bash
  dart compile exe example/example.dart -o build/cli_example.exe
  ```

- **Linux**
  ```bash
  dart compile exe example/example.dart -o build/cli_example
  ```

---

## License
MIT © [ccisne.dev](https://www.ccisne.dev)
