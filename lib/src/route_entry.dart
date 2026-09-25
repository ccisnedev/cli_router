part of 'cli_router.dart';

/// A registered route, as seen from outside the router.
///
/// Carries the structural facts the router already knows about a route, its
/// full command words, its positional parameters, and the mount it belongs
/// to, so a caller can describe a command without re-parsing the pattern.
class ListedCommand {
  ListedCommand(
    this.command,
    this.description, {
    this.positionals = const [],
    this.module,
  });

  /// Full route, mount prefix included: `commands show <name>`, `eval rpn`.
  final String command;

  final String? description;

  /// Names of the route's positional parameters, in declaration order.
  final List<String> positionals;

  /// Mount prefix this command was registered under; `null` at the root.
  final String? module;
}
