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
