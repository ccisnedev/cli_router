part of 'cli_router.dart';

/// A concrete, resolved invocation, handed to a route's [CliHandler].
class CliRequest {
  CliRequest({
    required this.originalArgs,
    required this.route,
    required this.params,
    required this.rest,
    required this.options,
    io.IOSink? stdout,
    io.IOSink? stderr,
  }) : stdout = stdout ?? io.stdout,
       stderr = stderr ?? io.stderr;

  /// The exact args passed to [CliRouter.run].
  final List<String> originalArgs;

  /// The route that matched.
  final CliRoute route;

  /// Bound values for the route's positional parameters that were present.
  final Map<String, String> params;

  /// Operands collected by a trailing `*` wildcard; empty otherwise.
  final List<String> rest;

  /// Every option read on the invocation, in argv order, exactly as written.
  final List<ParsedOption> options;

  final io.IOSink stdout;
  final io.IOSink stderr;

  /// The bound value for positional parameter `name`, or `null` if it was
  /// not declared by the route or not present (an unconsumed optional one).
  String? param(String name) => params[name];

  /// The first occurrence of option `name`, or `null` if it was not read on
  /// this invocation. For a repeatable option that occurred more than once,
  /// see [options] for every occurrence.
  ParsedOption? option(String name) {
    for (final o in options) {
      if (o.spec.name == name) return o;
    }
    return null;
  }
}
