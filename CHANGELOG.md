# Changelog

All notable changes to this project will be documented in this file.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/)
and the project adheres to [Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-09-25

A trie based router and a declarative, typed option schema, replacing the
longest-prefix matcher and the lossy GNU-style flag parser. Breaking release,
no compatibility shims: this is a rewrite of the option-parsing and
resolution model, not an incremental change.

### Added
- `OptionSpec`: a route's or router's option schema, declared up front.
  `OptionSpec.flag(name, {abbr, required repeatable})` for a presence-only
  option; `OptionSpec.value(name, {abbr, required required, required
  repeatable})` for one that takes a value. Both validate `name` and `abbr`
  immediately, at construction.
- `ParsedOption`: one occurrence of an option exactly as written
  (`spec`, `written`, `argvIndex`, `value`, `attached`). Parsing is lossless:
  every occurrence of a repeatable option produces its own `ParsedOption`, in
  argv order.
- `looksLikeOption(String)`: the single public predicate for "is this token
  option shaped" (`-`+letter, `--`+letter, or exactly `--`). Negative numbers
  and anything else are operands, never options.
- `CliRouter({List<OptionSpec> globalOptions = const []})`: options that
  apply to every route that opts in with `globals: true`.
- `CliRouter.cmd(pattern, handler, {required options, required globals,
  description})`: `options` and `globals` are now required, named, and
  declared per route, not inferred. `pattern` supports required `<name>`
  parameters, a single trailing optional `[<name>]` parameter, and a single
  trailing `*` wildcard.
- `CliRouter.mount(prefix, router)`: grafts a subrouter's routes under a
  single literal `prefix` word. Flattens transitively for nested mounts, and
  re-runs every build-time check (duplicate patterns, option-scope
  collisions, conflicting parameter names) in the parent router's context.
- `CliRouter.reservedWords`: every literal word reachable as a route's or
  mount's first token, so a caller can check a name is free before adding
  one.
- `CliRouter.resolve(List<String> argv) -> CliOutcome`: pure, side-effect
  free resolution. Never throws for a malformed invocation.
- `CliOutcome`, `CliResolution`, `CliRejection`, `CliRejectionKind`,
  `CliRoute`: the resolution result types. `CliRejectionKind` has exactly
  eleven members (`unknownCommand`, `extraArgument`, `incomplete`,
  `missingArgument`, `unknownOption`, `misplacedOption`, `missingValue`,
  `unexpectedValue`, `invalidShortOption`, `repeatedOption`,
  `missingRequiredOption`); the router only classifies, it never maps a
  rejection to an exit code.
- `CliRejection.options` and `.consumed` always reflect every option and
  route word read before the rejection, including global options like
  `--help`, even at a node that has not resolved to a route of its own yet
  (e.g. `eval --help` on a router with `eval rpn`/`eval infix` reports
  `incomplete` carrying `[help]`).
- `CliRouter.run(args, {required onReject, stdout, stderr})`: the I/O entry
  point built on `resolve`. `onReject` is required at the call site; there
  is no silent default reporting.
- `CliRequest.param(name)` and `.option(name)` helpers, alongside
  `route`, `params`, `rest`, `options`, `originalArgs`.

### Changed
- POSIX option ordering is now enforced: route words, then options, then
  operands. An option written after an operand, or before the route word it
  belongs to, is `misplacedOption`. `--` still ends option parsing.
- Value options require a separate value: `--file value`, `--file=value`, or
  `-f value`. `-f=value` is not a valid short form (`invalidShortOption`).
- Flags never take a value; `--flag=x` is `unexpectedValue`.
- A short option token must be exactly `-` plus one letter; short clusters
  (`-qh`) are `invalidShortOption`, not expanded.
- A repeated non-repeatable option is `repeatedOption`, under any spelling
  (mixing `--file` and `-f` still counts as a repeat of the same option).
- A required option absent at the end of the invocation is
  `missingRequiredOption`, decided only once every option on the invocation
  has been read.

### Removed
- `CliRequest.flags` (the lossy, string-keyed flag map) and the
  `flagBool`/`flagInt`/`flagDouble`/`flagString`/`isHelpRequested` helpers.
  Use `option(name)` on the typed `ParsedOption`.
- `CliRequest.matchedCommand` and `.positionals`. Use `route.pattern` and
  `params`/`rest`.
- `onNotFound`/`CliNotFound`/`CliNotFoundHandler`. Use `run`'s required
  `onReject` with a `CliRejection`.
- `--no-x` negation and short-option cluster expansion (`-abc` no longer
  expands to `a=true, b=true, c=true`); neither had a declared, typed
  meaning.
- `CliRouter.printHelp`. Help formatting is an application (or `modular_cli_sdk`) concern; the router only exposes `listCommands()`.
- `cmd(pattern, router)` as sugar for mounting a subrouter. Use `mount`.

## [0.1.1] - 2026-09-23

### Fixed

- Use one option-token predicate for route matching, flag parsing, and option value lookahead. An option starts with one or two dashes followed by an ASCII letter, and its name (the part before `=`) contains no whitespace; the value after `=` may contain anything, so `--title=two words` is still an option. Negative numbers, bare `-`, quoted expressions, and other non-option tokens remain available as positionals or option values, so `--offset -3` now assigns `-3` to `offset`. The `--` marker still ends options.

## [0.1.0] - 2026-07-13
### Added
- `CliRouter({CliNotFoundHandler? onNotFound})`: an application can now decide how an unmatched invocation is reported and with which exit code. The hook receives a `CliNotFound` (original args + sinks) and is inherited by every mounted subrouter. Presentation belongs to the application; the router only knows *what* failed to match.
- `ListedCommand` now carries the route metadata the router already had and used to discard: `positionals` (the names of the `<param>` segments, in order) and `module` (the mount the command was registered under).
- `ListedCommand`, `CliNotFound` and `CliNotFoundHandler` are exported from `package:cli_router/cli_router.dart`.

### Fixed
- Positionals after the matched route were dropped when the invocation carried no flags (`help math` reached the handler with an empty `positionals`). They are now captured whether or not a flag follows.

### Changed
- Minor version bump: `^0.0.z` permits no upgrade under Dart's caret semantics, so `0.0.x` releases pinned consumers to an exact patch. From `^0.1.0` on, consumers receive compatible updates without editing their pubspec.

Nothing breaks: with no `onNotFound` supplied, the router still prints `Command not found or invalid usage.` plus its listing to stderr and returns 64.

## [0.0.3] - 2026-04-18
### Fixed
- Empty route `''` no longer acts as catch-all. It now only matches when `args` is genuinely empty, preventing it from intercepting flag-only (`--help`) or positional args before mounts are evaluated.

## [0.0.2] - 2025-10-13
### Changed
- Shortened `description` in `pubspec.yaml` to meet pub.dev guidelines.
- Updated `homepage` → GitHub and `documentation` → pub.dev for valid URLs.
- Applied `dart format .` and `dart fix --apply` to match Dart style.
- Updated `README.md` with version `^0.0.2` and added pub badge.
- Completed MIT `LICENSE` text.

### Removed
- Removed unused `test/cli_router_test.dart`.

### Docs
- Improved DartDoc coverage for `CliRequest` methods.
- Fixed unresolved reference in doc comment for `CliRequest.matchedCommand`.

### Fixed
- Minor analyzer and formatting warnings reported by pana.

## [0.0.1] - 2025-10-13
### Added
- Initial release of **cli_router**.
  - Space-based routing for commands: `cmd('route subroute', handler)`.
  - Nested routers via `mount('prefix', subRouter)` or `cmd('prefix', subRouter)`.
  - Dynamic parameters `<id>` and wildcard `*`.
  - GNU-style flag parsing (`--k v`, `--k=v`, `-abc`, `--no-k`).
  - Shelf-like middlewares with `use()`.
  - Helpers: `flagBool`, `flagInt`, `flagDouble`, `flagString`, `param('id')`.
  - Simple help output and exit codes (`0`, `64`).
