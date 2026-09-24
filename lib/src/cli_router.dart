// ignore_for_file: avoid_print
//
// cli_router: Router for CLIs inspired by shelf_router,
// using space as the segment separator.
//
// Requirements: Dart >= 3.0.0

import 'dart:async';
import 'dart:io' as io;

part 'cli_types.dart';
part 'cli_request.dart';
part 'flags_parser.dart';
part 'path_pattern.dart';
part 'route_entry.dart';

/// Main router.
class CliRouter {
  /// [onNotFound] takes over reporting of unmatched invocations, for this
  /// router and every subrouter mounted under it. Without it, the router falls
  /// back to printing its own listing to stderr and returning 64.
  CliRouter({CliNotFoundHandler? onNotFound}) : _onNotFound = onNotFound;

  final CliNotFoundHandler? _onNotFound;
  final List<_RouteEntry> _routes = [];
  final List<_Mount> _mounts = [];
  final List<CliMiddleware> _middlewares = [];

  /// Registers a handler for a route (segments separated by spaces).
  /// If `target` is another [CliRouter], mounts that subrouter (syntactic sugar for [mount]).
  void cmd(String pattern, dynamic target, {String? description}) {
    if (target is CliRouter) {
      mount(pattern, target);
      return;
    }
    if (target is! CliHandler) {
      throw ArgumentError(
        'cmd(pattern, target): target must be a CliHandler or CliRouter',
      );
    }
    _routes.add(_RouteEntry(_PathPattern.parse(pattern), target, description));
  }

  /// Mounts a subrouter under a literal prefix (no dynamic segments allowed).
  void mount(String prefix, CliRouter router) {
    final segs = _PathPattern.parse(prefix, allowParams: false).segments;
    _mounts.add(_Mount(segs, router));
  }

  /// Adds shelf-like middleware (applied in registration order).
  void use(CliMiddleware middleware) => _middlewares.add(middleware);

  /// Runs the router with `args` (as passed to `main`).
  Future<int> run(
    List<String> args, {
    io.IOSink? stdout,
    io.IOSink? stderr,
  }) async {
    return _dispatch(
      args,
      upstream: const [],
      stdout: stdout ?? io.stdout,
      stderr: stderr ?? io.stderr,
      original: args,
    );
  }

  /// Lists all routes (includes subrouters) with their description, positional
  /// parameters, and the mount they belong to.
  List<ListedCommand> listCommands({String prefix = '', String? module}) {
    final out = <ListedCommand>[];
    for (final r in _routes) {
      out.add(
        ListedCommand(
          '$prefix${r.pattern}',
          r.description,
          positionals: r.pattern.positionalNames,
          module: module,
        ),
      );
    }
    for (final m in _mounts) {
      final mountName = _segmentsToString(m.prefix);
      out.addAll(
        m.router.listCommands(
          prefix: '$prefix$mountName ',
          module: module == null ? mountName : '$module $mountName',
        ),
      );
    }
    return out;
  }

  /// Prints a simple help message.
  void printHelp(io.IOSink sink, {String? title}) {
    final cmds = listCommands();
    if (title != null && title.isNotEmpty) {
      sink.writeln(title);
    }
    if (cmds.isEmpty) {
      sink.writeln('No commands registered.');
      return;
    }
    final maxLen = cmds
        .map((c) => c.command.length)
        .fold<int>(0, (a, b) => a > b ? a : b);
    sink.writeln('Available commands:');
    for (final c in cmds) {
      final pad = ' ' * (maxLen - c.command.length);
      final desc = c.description == null ? '' : '  - ${c.description}';
      sink.writeln('  ${c.command}$pad$desc');
    }
  }

  // ---------------- Internals ---------------- //

  Future<int> _dispatch(
    List<String> args, {
    required List<CliMiddleware> upstream,
    required io.IOSink stdout,
    required io.IOSink stderr,
    required List<String> original,
    CliNotFoundHandler? inheritedNotFound,
  }) async {
    // A subrouter reports not-found the way the router it was mounted under
    // does, unless it was given a hook of its own.
    final onNotFound = _onNotFound ?? inheritedNotFound;

    // 1) Determine how far the "route tokens" go before the flags.
    final flagStart = _indexOfFirstFlag(args);
    final maxRouteTokens = flagStart < 0 ? args.length : flagStart;

    // 2) Try the longest match against registered routes.
    for (int j = maxRouteTokens; j >= 0; j--) {
      // Guard: empty route '' must only match genuinely empty args.
      if (j == 0 && args.isNotEmpty) continue;
      final candidate = args.take(j).toList();
      final match = _matchRoute(candidate);
      if (match != null) {
        // Everything between the matched route and the first flag is a
        // positional, including when the invocation carries no flags at all.
        final immediatePositionals = args.sublist(
          j,
          flagStart < 0 ? args.length : flagStart,
        );
        final parsed = _parseFlags(
          flagStart < 0 ? const [] : args.sublist(flagStart),
        );
        final req = CliRequest(
          originalArgs: original,
          matchedCommand: candidate,
          params: match.params,
          flags: parsed.flags,
          positionals: [...immediatePositionals, ...parsed.trailingPositionals],
          stdout: stdout,
          stderr: stderr,
        );

        // Compose middlewares (upstream + local)
        final allMW = [...upstream, ..._middlewares];
        var h = match.handler;
        for (final mw in allMW.reversed) {
          h = mw(h);
        }
        return await h(req);
      }
    }

    // 3) If there's no direct route, try mounts by longest prefix.
    _Mount? best;
    int bestLen = -1;
    for (final m in _mounts) {
      if (m.prefix.length <= maxRouteTokens && _prefixEquals(args, m.prefix)) {
        if (m.prefix.length > bestLen) {
          best = m;
          bestLen = m.prefix.length;
        }
      }
    }
    if (best != null) {
      final remainder = args.sublist(bestLen);
      return best.router._dispatch(
        remainder,
        upstream: [...upstream, ..._middlewares],
        stdout: stdout,
        stderr: stderr,
        original: original,
        inheritedNotFound: onNotFound,
      );
    }

    // 4) Nothing matched
    if (onNotFound != null) {
      return await onNotFound(
        CliNotFound(args: original, stdout: stdout, stderr: stderr),
      );
    }
    stderr.writeln('Command not found or invalid usage.');
    stderr.writeln();
    printHelp(stderr, title: 'Help:');
    return 64; // EX_USAGE
  }

  _MatchedRoute? _matchRoute(List<String> tokens) {
    for (final r in _routes) {
      final params = <String, String>{};
      if (r.pattern.matches(tokens, outParams: params)) {
        return _MatchedRoute(r.handler, params);
      }
    }
    return null;
  }

  static int _indexOfFirstFlag(List<String> args) {
    if (args.isEmpty) return -1;
    for (int i = 0; i < args.length; i++) {
      if (_isOptionToken(args[i])) return i;
    }
    return -1;
  }

  static bool _prefixEquals(List<String> args, List<_Segment> prefix) {
    if (prefix.length > args.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      final seg = prefix[i];
      if (seg.isParam || seg.isWildcard) return false;
      if (args[i] != seg.literal) return false;
    }
    return true;
  }

  static String _segmentsToString(List<_Segment> segs) =>
      segs.map((s) => s.isParam ? '<${s.name}>' : s.literal).join(' ');
}

/// Helper para envolver una función que no devuelve código
/// y convertirla en [CliHandler] que retorna 0 al terminar.
CliHandler handler(FutureOr<void> Function(CliRequest req) fn) {
  return (req) async {
    await fn(req);
    return 0;
  };
}
