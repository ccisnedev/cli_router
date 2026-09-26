part of 'cli_router.dart';

/// Every way a router can fail to resolve an invocation, per spec 8.5. The
/// router only classifies; it never maps a kind to an exit code, that is an
/// application (SDK) concern.
enum CliRejectionKind {
  /// The very first token does not match any literal route and the router
  /// has no parameter route to absorb it.
  ///
  /// [CliRejection.token] is always the unmatched word. [CliRejection.argument]
  /// is always null: no positional is implicated, the invocation never
  /// reached one.
  unknownCommand,

  /// A resolved route was reached, but a leftover token does not fit
  /// anywhere in it.
  ///
  /// [CliRejection.token] is always the leftover token. [CliRejection.argument]
  /// is always null: the token is unexpected, not bound to a declared
  /// positional name.
  extraArgument,

  /// The invocation ends, or a token fits nothing, at a node that is not
  /// itself a route and has no pending required parameter.
  ///
  /// [CliRejection.token] is the token that did not continue the command
  /// when one caused the rejection, but null when argv simply ran out at a
  /// node that has no route of its own and no pending parameter (there is
  /// no offending token to name). [CliRejection.argument] is always null.
  incomplete,

  /// The invocation ends at a node that still needs a required parameter.
  ///
  /// [CliRejection.argument] is always the missing positional's name.
  /// [CliRejection.token] is always null: this only happens when argv has
  /// run out, so there is no offending token.
  missingArgument,

  /// The token is option shaped but declared nowhere reachable.
  ///
  /// [CliRejection.token] is always the option exactly as written on argv.
  /// [CliRejection.argument] is always null.
  unknownOption,

  /// The option is declared, but not here: it belongs to route words or an
  /// operand that have not been consumed yet.
  ///
  /// [CliRejection.token] is always the misplaced option exactly as written
  /// on argv (or `'--'` itself, for a `--` that follows an operand).
  /// [CliRejection.argument] is always null.
  misplacedOption,

  /// A value option has no value: it is the last token, or the next token is
  /// option shaped.
  ///
  /// [CliRejection.token] is always the option missing its value, exactly as
  /// written on argv. [CliRejection.argument] is always null.
  missingValue,

  /// A flag was given a value (`--flag=x`); flags never take one.
  ///
  /// [CliRejection.token] is always the flag with its attached value,
  /// exactly as written on argv. [CliRejection.argument] is always null.
  unexpectedValue,

  /// A single-dash token is not exactly one letter (`-qh`, `-f=v`, `-fv`).
  ///
  /// [CliRejection.token] is always the malformed token exactly as written
  /// on argv. [CliRejection.argument] is always null.
  invalidShortOption,

  /// A non-repeatable option occurred more than once, under any spelling.
  ///
  /// [CliRejection.token] is always the repeated occurrence exactly as
  /// written on argv (not the first one). [CliRejection.argument] is
  /// always null.
  repeatedOption,

  /// A required option was never read, decided only after every option on
  /// the invocation was read.
  ///
  /// Neither [CliRejection.argument] nor [CliRejection.token] applies: the
  /// rejection is structural (an option that never showed up at all), not
  /// tied to one specific argv token or positional. Both are always null.
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
    this.argument,
    this.token,
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
  /// decides what to actually show the user. Never parse this: it is prose,
  /// not a contract, and its wording can change; use [argument] and [token]
  /// for anything typed.
  final String? message;

  /// The positional parameter's name this rejection implicates, typed
  /// instead of parsed out of [message]. Guaranteed non-null only for
  /// [CliRejectionKind.missingArgument]; null for every other kind. See the
  /// per-kind doc comments on [CliRejectionKind] for the exact guarantee.
  final String? argument;

  /// The offending argv token this rejection implicates, exactly as
  /// written, typed instead of parsed out of [message]. Guaranteed
  /// non-null for every kind except [CliRejectionKind.missingArgument] and
  /// [CliRejectionKind.missingRequiredOption] (always null for both), and
  /// [CliRejectionKind.incomplete] (non-null only when a specific token
  /// caused the rejection, null when argv simply ran out). See the
  /// per-kind doc comments on [CliRejectionKind] for the exact guarantee.
  final String? token;

  @override
  String toString() => 'CliRejection($kind, consumed: $consumed)';
}
