# Changelog

All notable changes to this project will be documented in this file.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/)
and the project adheres to [Semantic Versioning](https://semver.org/).

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
