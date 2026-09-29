part of 'cli_router.dart';

/// Handler type. Returns an exit code (0 OK, 64 invalid usage, etc.)
typedef CliHandler = FutureOr<int> Function(CliRequest req);

/// Shelf-like middleware: receives the next handler and returns a wrapped one.
typedef CliMiddleware = CliHandler Function(CliHandler next);

/// Decides how a rejected invocation is reported, and with which exit code.
///
/// The router knows exactly what failed to resolve (see [CliRejection]); how
/// that is presented to a human, including help precedence, belongs to the
/// application built on top of it. There is no default: [CliRouter.run]
/// requires a [CliRejectionHandler] at the call site.
typedef CliRejectionHandler = FutureOr<int> Function(CliRejection rejection);

/// How [CliRouter.resolve] treats an option written after an operand has
/// already started.
///
/// [permute] (the default) follows GNU `getopt`'s convention: before the
/// strict grammar runs, argv is rewritten so that every option (with its
/// value, for a value option) moves in front of the first operand, keeping
/// the relative order of the options among themselves and of the operands
/// among themselves. `--` still ends the rewrite: everything from `--`
/// onward is left exactly where it was, options included. Inside a route
/// ending in a `*` wildcard, only the tokens read before the wildcard's own
/// first captured token are eligible to move; once the wildcard starts
/// capturing, nothing after that point is reordered. An option written
/// before the route word that declares it is still an error: permutation
/// only ever moves an option earlier relative to operands, never across an
/// unresolved route boundary. A negative number (`-1`, `-2.5`) is never
/// option shaped (see [looksLikeOption]), so it is never moved either.
///
/// [strict] is the plain POSIX grammar: route words, then options, then
/// operands, with no rewrite. An option read once an operand has started is
/// `misplacedOption`, exactly as in cli_router 0.2.0.
///
/// [CliRouter.resolve] never reads the environment to choose between the
/// two; it stays pure. [CliRouter.run] is the one that decides, based on
/// whether `POSIXLY_CORRECT` is set in its environment.
enum OptionOrdering {
  /// GNU `getopt` style: options may follow operands and are moved in front
  /// of them before the strict grammar runs.
  permute,

  /// Plain POSIX: an option after an operand has started is
  /// `misplacedOption`.
  strict,
}
