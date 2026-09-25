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
  `OptionSpec.flag(name, {required abbr, required repeatable})` for a
  presence-only option; `OptionSpec.value(name, {required abbr, required
  required, required repeatable})` for one that takes a value. `abbr` is a
  required named parameter (its type stays `String?`; pass `abbr: null`
  for an option with no short form) so a caller cannot silently forget it.
  Both validate `name` and `abbr` immediately, at construction.
- `ParsedOption`: one occurrence of an option exactly as written
  (`spec`, `written`, `argvIndex`, `value`, `attached`). Parsing is lossless:
  every occurrence of a repeatable option produces its own `ParsedOption`, in
  argv order.
- `looksLikeOption(String)`: the single public predicate for "is this token
  option shaped" (`-`+letter, `--`+letter, or exactly `--`). Negative numbers
  and anything else are operands, never options.
- `CliRouter({required List<OptionSpec> globalOptions})`: options that apply
  to every route that opts in with `globals: true`. Required, no default:
  pass `const []` for a router with no globals.
- `CliRouter.cmd(pattern, handler, {required options, required globals,
  description})`: `options` and `globals` are now required, named, and
  declared per route, not inferred. `pattern` supports required `<name>`
  parameters, a single trailing optional `[<name>]` parameter, and a single
  trailing `*` wildcard.
- `CliRouter.mount(prefix, router)`: grafts a subrouter's routes under a
  single literal `prefix` word. Flattens transitively for nested mounts, and
  re-runs every build-time check (duplicate patterns, option-scope
  collisions, conflicting parameter names) in the parent router's context.
  The mounted router's own middleware (added to it with `use`) is preserved:
  each grafted handler is wrapped in the mounted router's middleware first,
  then in the mounting router's own middleware, so nested mounts compose
  outermost-mounting-router-first at every level. A word the mounted router
  reserves without a route of its own (e.g. through one of its own empty
  mounts) stays reserved here too. The mounted router's own `globalOptions`
  must equal the mounting router's, by shape, as a set (declaration order
  does not matter): a program has exactly one set of global options, shared
  by every mounted subrouter, so `mount()` throws an `ArgumentError` when
  they differ, rather than silently dropping the mounted router's globals
  (only each route's own `options` and `globals` flag were ever carried
  across; the subrouter's `_globalOptions` itself was not).
- Grammar (spec G): a route pattern where a literal word follows a
  parameter, optional parameter, or wildcard segment is an `ArgumentError`
  at `cmd()`, e.g. `'show <id> details'`. Route words are grammar; params,
  the optional param, and the wildcard are operands; and once an operand
  starts, the pattern cannot go back to route vocabulary. Every pattern
  used anywhere in this package (tests, README, the example) now places its
  literal words before its parameters.
- Grammar, at resolution time: once the first operand of an invocation is
  consumed (a required parameter, the optional parameter, or the
  wildcard), the resolver is committed. No further token can be read as a
  literal route word, and no further option can be read: an option after
  that point is `misplacedOption`, naming the route when it is already
  known unambiguously (which can happen even with a further required
  parameter still pending, as long as exactly one route remains reachable
  from there through parameters alone).
- `OptionSpec` now overrides `==`/`hashCode` by declared shape: two
  separately constructed `OptionSpec`s with the same `name`, `abbr`,
  `takesValue`, `required` and `repeatable` are the same option throughout
  resolution (consumed-option tracking, required-option checks, scope
  checks), not two unrelated ones, even when registered as two distinct
  instances on different routes.
- Build-time: two routes reachable from one another through required
  parameters only (i.e. in the same `_scopeAt` option-reading position) that
  declare an option sharing a name or abbreviation but not the identical
  shape are an `ArgumentError` at `cmd()`. Declaring the identical shape on
  both is fine (`OptionSpec.==` treats it as the same option); declaring it
  on unrelated branches that are never reachable through each other is
  fine too.
- Build-time: a route option colliding with a global option, by name or
  abbreviation, is always an `ArgumentError` at `cmd()`, regardless of that
  route's `globals` flag. `globals: false` only means the route does not
  accept its own router's globals; it is not license to redeclare their
  names or abbreviations for something else.
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
- Every `CliRejection` carries a non-null, human readable `message`, and a
  non-null `route` whenever the route is already unambiguously resolved at
  rejection time (every literal segment leading to it consumed, no
  continuation left).
- `CliRejectionKind.unknownOption` now also covers an option that is in
  scope while still resolving (offered by some route reachable ahead) but
  is not actually declared by the specific route the invocation resolves
  to, e.g. a global option on a route with `globals: false`, or a route
  option declared by a sibling route (spec 8.2: "option in scope but not
  accepted by the resolved route: `unknownOption`, naming the route").
  Checked once resolution lands on a route (on a successful resolution and
  on `extraArgument`), against every option parsed since the start of the
  invocation.
- `CliRouter.run(args, {required onReject, stdout, stderr})`: the I/O entry
  point built on `resolve`. `onReject` is required at the call site; there
  is no silent default reporting. `stdout`/`stderr` are the one deliberate
  default in the router: when left `null`, they fall back to `io.stdout`
  and `io.stderr`; pass a fake sink explicitly (e.g. in a test) to capture
  what a handler writes instead.
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
- `misplacedOption` for an option not in scope but declared somewhere ahead
  is now decided by whether *some* route still reachable from the current
  node (through its param child and every literal child, recursively)
  declares that option, not only by an uninterrupted lookahead walk. An
  uninterrupted lookahead that reaches exactly one route still names that
  route, as before; when a second option token interrupts the lookahead
  before it reaches a route, the option is still reported as
  `misplacedOption` (naming the one route that declares it, if only one
  subtree route does; otherwise `route: null`, with every candidate route
  listed in the message) rather than falling back to `unknownOption`.
- The option scope at a node not yet resolved to a route (spec 8.2) is now
  the globals plus the options of *every* route reachable from that node
  through required parameters only, not just one deterministic route. A
  node with both a literal child and a param child (e.g. a root that has
  its own route and a parameter shortcut, like `''` and `<program>`) offers
  the union, so an option belonging only to the parameter route is still
  readable there; whether it is actually accepted is still decided by the
  specific route resolution lands on (see `unknownOption` above).
- `missingArgument` (a required parameter with no value left in argv) now
  revalidates every option already read against the one route still
  reachable, before reporting the missing value: once the resolver knows
  unambiguously which route the invocation would land on, an option that
  route rejects is `unknownOption`, naming it, in preference to
  `missingArgument` (spec 8.6: help, and any other option, loses to an
  option error once the route is known). `missingArgument` at a position
  where more than one route is still reachable, or where none of the
  already-read options mismatch, is unaffected and still carries no route.
- `_lookAheadRoute` (used only to name a route in a `misplacedOption`
  message) no longer treats an option-shaped token as a literal route word
  or a required parameter's value while walking ahead: an option token now
  always makes the lookahead return `null`, rather than the node it started
  from, so a node's own preexisting route (for example a root that has its
  own `''` route) is never reported as the walk's conclusion just because
  the walk broke on the first token. Subtree declaration (spec 8.2 rule a)
  is now checked before, not only after, an uninterrupted lookahead: a
  route the lookahead actually reaches is only named when that route is
  itself one of the routes declaring the option somewhere in the subtree,
  so a route that merely happens to be where the walk lands, without
  declaring the option, can no longer be misreported as `unknownOption` in
  place of `misplacedOption`.
- `cmd()` and `CliRouter`'s constructor now store `List.unmodifiable`
  copies of a route's `options` and of `globalOptions`: mutating the list
  passed in after registration no longer changes the registered route or
  router.
- `'--'` after the first operand has started is now `misplacedOption`
  ("'--' goes before the program"), not silently absorbed. Previously
  `<program> one --` resolved the same as `<program> one`, and `run *`
  with `run a -- --help` resolved with `rest: [a, --help]`, both silently
  dropping or reinterpreting the `--` the caller actually typed. `'--'`
  before the first operand is unaffected: it still ends option parsing.

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
- `ListedCommand.module`. It was always `null`: mount flattening threads the
  mount prefix into the route's own `pattern` (`commands show <name>`), it
  never tracked the mount name separately. Use `reservedWords` to check
  whether a word is already a mount prefix.

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
