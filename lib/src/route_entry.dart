part of 'cli_router.dart';

/// A registered route, as seen from outside the router.
///
/// Carries the structural facts the router already knows about a route, its
/// full command words and its positional parameters, so a caller can
/// describe a command without re-parsing the pattern.
class ListedCommand {
  ListedCommand(this.command, this.description, {this.positionals = const []});

  /// Full route, mount prefix included: `commands show <name>`, `eval rpn`.
  final String command;

  final String? description;

  /// Names of the route's positional parameters, in declaration order.
  final List<String> positionals;
}
