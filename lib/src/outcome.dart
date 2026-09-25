part of 'cli_router.dart';

/// Every way a router can fail to resolve an invocation, per spec 8.5. The
/// router only classifies; it never maps a kind to an exit code, that is an
/// application (SDK) concern.
enum CliRejectionKind {
  /// The very first token does not match any literal route and the router
  /// has no parameter route to absorb it.
  unknownCommand,

  /// A resolved route was reached, but a leftover token does not fit
  /// anywhere in it.
  extraArgument,

  /// The invocation ends, or a token fits nothing, at a node that is not
  /// itself a route and has no pending required parameter.
  incomplete,

  /// The invocation ends at a node that still needs a required parameter.
  missingArgument,

  /// The token is option shaped but declared nowhere reachable.
  unknownOption,

  /// The option is declared, but not here: it belongs to route words or an
  /// operand that have not been consumed yet.
  misplacedOption,

  /// A value option has no value: it is the last token, or the next token is
  /// option shaped.
  missingValue,

  /// A flag was given a value (`--flag=x`); flags never take one.
  unexpectedValue,

  /// A single-dash token is not exactly one letter (`-qh`, `-f=v`, `-fv`).
  invalidShortOption,

  /// A non-repeatable option occurred more than once, under any spelling.
  repeatedOption,

  /// A required option was never read, decided only after every option on
  /// the invocation was read.
  missingRequiredOption,
}

/// A registered route, as exposed to the outside: its command words, its
/// positional parameters, and the option schema that applies to it.
class CliRoute {
  const CliRoute({
    required this.pattern,
    required this.positionals,
    required this.options,
    required this.globals,
    this.optionalParam,
    this.hasWildcard = false,
    this.description,
  });

  /// The route's command words and required `<name>` placeholders, space
  /// separated, mount prefixes included (e.g. `commands show <name>`,
  /// `eval rpn`). Never includes a trailing `[<name>]` or `*`; see
  /// [optionalParam] and [hasWildcard] for that.
  final String pattern;

  /// Names of every positional parameter this route binds, in declaration
  /// order, required ones and the trailing optional one (if any) alike.
  final List<String> positionals;

  /// This route's own option schema (not including globals).
  final List<OptionSpec> options;

  /// Whether the router's global options also apply to this route.
  final bool globals;

  /// The name of the trailing `[<name>]` segment, if the route ends in one.
  final String? optionalParam;

  /// Whether the route ends in a `*` wildcard.
  final bool hasWildcard;

  final String? description;

  @override
  String toString() => 'CliRoute($pattern)';
}

/// The result of [CliRouter.resolve]: either a [CliResolution] or a
/// [CliRejection]. A pure, sealed value; resolving performs no I/O.
sealed class CliOutcome {
  const CliOutcome();
}

/// An invocation that matched a route.
class CliResolution extends CliOutcome {
  const CliResolution({
    required this.route,
    required this.params,
    required this.rest,
    required this.options,
    required this.handler,
  });

  /// The route that matched.
  final CliRoute route;

  /// Bound values for every positional parameter the route declares that was
  /// actually present on the invocation (the trailing optional one may be
  /// absent).
  final Map<String, String> params;

  /// Operands collected by a trailing `*` wildcard, in order; empty for a
  /// route with no wildcard.
  final List<String> rest;

  /// Every option read on the invocation, in argv order, exactly as written.
  final List<ParsedOption> options;

  /// The handler registered for [route].
  final CliHandler handler;
}

/// An invocation that did not resolve.
class CliRejection extends CliOutcome {
  const CliRejection({
    required this.kind,
    required this.consumed,
    required this.options,
    this.route,
    this.message,
  });

  /// Which of the eleven ways resolution failed.
  final CliRejectionKind kind;

  /// The literal route words successfully consumed before the rejection
  /// (mount prefixes included), in order.
  final List<String> consumed;

  /// Every option successfully read before the rejection, including globals
  /// like `--help`, in argv order. For [CliRejectionKind.incomplete],
  /// [CliRejectionKind.missingArgument] and
  /// [CliRejectionKind.missingRequiredOption] this always reflects every
  /// option read up to that point (see the amendment to issue #6), even at a
  /// node that has not resolved to a route of its own yet.
  final List<ParsedOption> options;

  /// The specific route implicated by this rejection, when the router was
  /// able to identify one: the route an option belongs to
  /// ([CliRejectionKind.misplacedOption], [CliRejectionKind.unknownOption]),
  /// the route with the missing required option
  /// ([CliRejectionKind.missingRequiredOption]), or the route that already
  /// resolved when an extra token showed up
  /// ([CliRejectionKind.extraArgument]). `null` when no specific route
  /// applies or could be identified.
  final CliRoute? route;

  /// A human readable description of the rejection, for logging; the SDK
  /// decides what to actually show the user.
  final String? message;

  @override
  String toString() => 'CliRejection($kind, consumed: $consumed)';
}
