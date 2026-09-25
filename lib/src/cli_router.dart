// cli_router: a trie based router for CLIs, POSIX option ordering, and a
// declarative, typed option schema.
//
// Requirements: Dart >= 3.0.0

import 'dart:async';
import 'dart:io' as io;

part 'cli_types.dart';
part 'option_spec.dart';
part 'outcome.dart';
part 'cli_request.dart';
part 'route_entry.dart';
part 'trie.dart';

/// A trie based CLI router. Routes are registered with [cmd], resolved
/// (purely, no I/O) with [resolve], and dispatched with [run].
///
/// Every behavior-changing registration detail is a required named
/// parameter: the router applies no defaults and guesses nothing.
class CliRouter {
  CliRouter({List<OptionSpec> globalOptions = const []})
    : _globalOptions = globalOptions {
    _validateOptionScope(globalOptions, false, const []);
  }

  final List<OptionSpec> _globalOptions;
  final _TrieNode _root = _TrieNode();
  final List<_RegisteredRoute> _flatRoutes = [];
  final List<CliMiddleware> _middlewares = [];

  /// Registers a route.
  ///
  /// [pattern] is a space separated sequence of literal words, required
  /// `<name>` parameters, and, only as the very last segment, either one
  /// optional `[<name>]` parameter or one `*` wildcard.
  ///
  /// [options] is this route's own option schema. [globals] says whether the
  /// router's global options also apply to this route. Both are required:
  /// there is no default scope.
  void cmd(
    String pattern,
    CliHandler handler, {
    required List<OptionSpec> options,
    required bool globals,
    String? description,
  }) {
    final segs = _parseSegments(pattern);
    _validateOptionScope(options, globals, _globalOptions);

    final lastSeg = segs.isEmpty ? null : segs.last;
    final optionalParamName = lastSeg?.kind == _SegKind.optionalParam
        ? lastSeg!.name
        : null;
    final hasWildcard = lastSeg?.kind == _SegKind.wildcard;

    final positionals = <String>[
      for (final s in segs)
        if (s.kind == _SegKind.requiredParam ||
            s.kind == _SegKind.optionalParam)
          s.name!,
    ];

    final publicSegs = (hasWildcard || optionalParamName != null)
        ? segs.sublist(0, segs.length - 1)
        : segs;

    final route = CliRoute(
      pattern: _segsToPatternString(publicSegs),
      positionals: positionals,
      options: options,
      globals: globals,
      optionalParam: optionalParamName,
      hasWildcard: hasWildcard,
      description: description,
    );

    final reg = _RegisteredRoute(
      route: route,
      handler: handler,
      segments: segs,
    );
    _insertSegments(_root, segs, reg);
    _flatRoutes.add(reg);
  }

  /// Grafts every route of [router] under a single literal [prefix] word.
  ///
  /// This flattens: each of [router]'s routes is re-registered here as
  /// `'$prefix ${originalPattern}'`, through [cmd], so every build-time
  /// check (duplicate patterns, option-scope collisions against this
  /// router's own globals, conflicting parameter names, and so on) fires
  /// again in this router's context. Nested mounts flatten transitively.
  ///
  /// [prefix] must be exactly one literal word: not a parameter, not `*`,
  /// not option shaped, not multiple words.
  void mount(String prefix, CliRouter router) {
    final words = prefix
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length != 1) {
      throw ArgumentError.value(
        prefix,
        'prefix',
        'a mount prefix must be exactly one literal word',
      );
    }
    final word = words.single;
    if (word.startsWith('<') ||
        word.startsWith('[') ||
        word == '*' ||
        looksLikeOption(word)) {
      throw ArgumentError.value(
        prefix,
        'prefix',
        'a mount prefix must be a plain literal word',
      );
    }

    // Reserve the word even when the subrouter has no routes of its own yet.
    _root.literalChildren.putIfAbsent(word, () => _TrieNode());

    for (final r in router._flatRoutes) {
      final childPattern = _segsToPatternString(r.segments);
      cmd(
        '$word $childPattern',
        r.handler,
        options: r.route.options,
        globals: r.route.globals,
        description: r.route.description,
      );
    }
  }

  /// Adds middleware, applied in registration order around the resolved
  /// route's handler.
  void use(CliMiddleware middleware) => _middlewares.add(middleware);

  /// Every literal word reachable as the first token of some route, mount
  /// prefixes included. Useful to check a word is not already taken before
  /// adding a new command or mount.
  List<String> get reservedWords => _root.literalChildren.keys.toList();

  /// Every registered route, mounts flattened in.
  List<ListedCommand> listCommands() => [
    for (final r in _flatRoutes)
      ListedCommand(
        r.route.pattern,
        r.route.description,
        positionals: r.route.positionals,
      ),
  ];

  /// Resolves [argv] against the registered routes. Pure: performs no I/O
  /// and never throws for a malformed invocation, only for a bug in the
  /// router itself.
  CliOutcome resolve(List<String> argv) {
    var node = _root;
    final consumed = <String>[];
    final params = <String, String>{};
    final rest = <String>[];
    final parsedOptions = <ParsedOption>[];
    final consumedSpecs = <OptionSpec>{};
    var operandStarted = false;
    var optionalParamConsumed = false;
    var afterDoubleDash = false;
    var i = 0;

    List<OptionSpec> scopeAt(_TrieNode n) {
      final r = n.ownRoute ?? _deterministicRoute(n);
      if (r == null) return _globalOptions;
      return r.route.globals
          ? [...r.route.options, ..._globalOptions]
          : r.route.options;
    }

    CliRejection reject(
      CliRejectionKind kind, {
      CliRoute? route,
      String? message,
    }) {
      return CliRejection(
        kind: kind,
        consumed: List.unmodifiable(consumed),
        options: List.unmodifiable(parsedOptions),
        route: route,
        message: message,
      );
    }

    CliOutcome finishHere() {
      final r = node.ownRoute;
      if (r == null) {
        if (node.paramChild != null) {
          return reject(
            CliRejectionKind.missingArgument,
            message: 'missing a value for <${node.paramName}>',
          );
        }
        return reject(
          CliRejectionKind.incomplete,
          message: 'incomplete command',
        );
      }
      final scope = scopeAt(node);
      for (final spec in scope) {
        if (spec.required && !consumedSpecs.contains(spec)) {
          return reject(
            CliRejectionKind.missingRequiredOption,
            route: r.route,
            message: "missing required option '--${spec.name}'",
          );
        }
      }
      return CliResolution(
        route: r.route,
        params: Map.unmodifiable(params),
        rest: List.unmodifiable(rest),
        options: List.unmodifiable(parsedOptions),
        handler: r.handler,
      );
    }

    while (true) {
      if (i >= argv.length) {
        return finishHere();
      }
      final token = argv[i];

      if (!afterDoubleDash && token == '--') {
        afterDoubleDash = true;
        i++;
        continue;
      }

      if (!afterDoubleDash && looksLikeOption(token)) {
        final outcome = _readOption(
          argv: argv,
          i: i,
          token: token,
          node: node,
          operandStarted: operandStarted,
          scope: scopeAt(node),
          allRoutes: _flatRoutes,
          globalOptions: _globalOptions,
        );
        if (outcome is _OptionRead) {
          final parsed = outcome.parsed;
          if (!parsed.spec.repeatable && consumedSpecs.contains(parsed.spec)) {
            return reject(
              CliRejectionKind.repeatedOption,
              message: "option '--${parsed.spec.name}' cannot be repeated",
            );
          }
          parsedOptions.add(parsed);
          consumedSpecs.add(parsed.spec);
          i = outcome.nextIndex;
          continue;
        }
        final failed = outcome as _OptionFailed;
        return reject(failed.kind, route: failed.route);
      }

      if (!afterDoubleDash) {
        final lit = node.literalChildren[token];
        if (lit != null) {
          node = lit;
          consumed.add(token);
          i++;
          continue;
        }
      }

      if (node.paramChild != null) {
        params[node.paramName!] = token;
        final next = node.paramChild!;
        i++;
        node = next;
        if (node.literalChildren.isEmpty &&
            node.paramChild == null &&
            node.optionalParamRoute == null &&
            node.wildcardRoute == null) {
          operandStarted = true;
        }
        continue;
      }

      if (node.optionalParamRoute != null && !optionalParamConsumed) {
        params[node.optionalParamRoute!.route.optionalParam!] = token;
        optionalParamConsumed = true;
        operandStarted = true;
        i++;
        continue;
      }

      if (node.wildcardRoute != null) {
        rest.add(token);
        operandStarted = true;
        i++;
        continue;
      }

      if (node.ownRoute != null) {
        return reject(
          CliRejectionKind.extraArgument,
          route: node.ownRoute!.route,
          message: "unexpected argument '$token'",
        );
      }
      if (identical(node, _root)) {
        return reject(
          CliRejectionKind.unknownCommand,
          message: "unknown command '$token'",
        );
      }
      return reject(
        CliRejectionKind.incomplete,
        message: "'$token' does not continue this command",
      );
    }
  }

  /// Resolves and dispatches [args]. [onReject] is required: it takes over
  /// for every invocation that does not resolve to a route, and decides the
  /// process exit code; the router itself never maps a rejection to one.
  Future<int> run(
    List<String> args, {
    required CliRejectionHandler onReject,
    io.IOSink? stdout,
    io.IOSink? stderr,
  }) async {
    final out = stdout ?? io.stdout;
    final err = stderr ?? io.stderr;
    final outcome = resolve(args);
    if (outcome is CliRejection) {
      return await onReject(outcome);
    }
    final resolution = outcome as CliResolution;
    var h = resolution.handler;
    for (final mw in _middlewares.reversed) {
      h = mw(h);
    }
    final req = CliRequest(
      originalArgs: args,
      route: resolution.route,
      params: resolution.params,
      rest: resolution.rest,
      options: resolution.options,
      stdout: out,
      stderr: err,
    );
    return await h(req);
  }
}

/// Wraps a function that reports nothing into a [CliHandler] that returns 0
/// once it completes.
CliHandler handler(FutureOr<void> Function(CliRequest req) fn) {
  return (req) async {
    await fn(req);
    return 0;
  };
}
