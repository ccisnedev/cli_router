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
  CliRouter({required List<OptionSpec> globalOptions})
    : _globalOptions = List.unmodifiable(globalOptions) {
    _validateOptionScope(globalOptions, const []);
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
    final ownOptions = List<OptionSpec>.unmodifiable(options);
    final segs = _parseSegments(pattern);
    _validateOptionScope(ownOptions, _globalOptions);

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
      options: ownOptions,
      globals: globals,
      optionalParam: optionalParamName,
      hasWildcard: hasWildcard,
      description: description,
    );

    // Checked against the trie as it stands before this route is inserted,
    // so the check never sees itself and the trie is never mutated ahead of
    // a build-time error (spec 8.2, items 4+5).
    final existingBoundary = _existingLiteralPrefixNode(_root, segs);
    if (existingBoundary != null) {
      _validateSiblingOptionScope(existingBoundary, route);
    }

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

    // One program, one set of globals: a mounted router's own global
    // options must be exactly the parent's, by shape, as a set. Otherwise
    // the child's globals would either be silently lost (mount() only ever
    // copies each route's own `options` and `globals` flag, never the
    // child's `_globalOptions`) or, the other way round, the parent's
    // globals would silently start applying to routes that never declared
    // them. Checked before any trie mutation, so a rejected mount leaves
    // this router untouched.
    if (!_sameOptionSet(router._globalOptions, _globalOptions)) {
      throw ArgumentError.value(
        router,
        'router',
        "the mounted router's globalOptions must equal this router's "
            'globalOptions, by shape, as a set: a program has exactly one '
            'set of global options, shared by every mounted subrouter',
      );
    }

    // Reserve the word even when the subrouter has no routes of its own yet.
    final mountNode = _root.literalChildren.putIfAbsent(
      word,
      () => _TrieNode(),
    );

    // Mirror the subrouter's own literal trie structure (not just its
    // flattened routes) so that a word it reserves without a route of its
    // own, e.g. through one of its own empty mounts, stays reserved here
    // too, rather than being left free for a param route under [word] to
    // swallow.
    _mirrorReservedWords(mountNode, router._root);

    for (final r in router._flatRoutes) {
      final childPattern = _segsToPatternString(r.segments);
      cmd(
        '$word $childPattern',
        _composeMiddlewares(router._middlewares, r.handler),
        options: r.route.options,
        globals: r.route.globals,
        description: r.route.description,
      );
    }
  }

  /// Adds middleware, applied in registration order around the resolved
  /// route's handler.
  void use(CliMiddleware middleware) => _middlewares.add(middleware);

  /// Wraps [handler] with [middlewares], first-registered outermost: the
  /// same order [run] applies this router's own [_middlewares] in. Used by
  /// [run] directly, and by [mount] to bake a mounted router's own
  /// middleware into the handler it copies, so it still runs (inside
  /// whatever middleware the mounting router adds of its own) however many
  /// levels of mounting the route ends up under.
  static CliHandler _composeMiddlewares(
    List<CliMiddleware> middlewares,
    CliHandler handler,
  ) {
    var h = handler;
    for (final mw in middlewares.reversed) {
      h = mw(h);
    }
    return h;
  }

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

    // Once a specific route is known, every option read so far (readable,
    // until now, only through the wider exploratory scope of `_scopeAt`)
    // must actually be accepted by that route's own exact scope: its own
    // options, plus globals only when it accepts them (spec 8.2: "option in
    // scope but not accepted by the resolved route: unknownOption, naming
    // the route"). Reports the first violation, in read order.
    CliRejection? optionsMismatch(CliRoute route) {
      final finalScope = _routeScope(route, _globalOptions);
      for (final parsed in parsedOptions) {
        if (!finalScope.contains(parsed.spec)) {
          return reject(
            CliRejectionKind.unknownOption,
            route: route,
            message:
                '${_describeOption(parsed.spec)} is not accepted by '
                "'${route.pattern}'",
          );
        }
      }
      return null;
    }

    CliOutcome finishHere() {
      final r = node.ownRoute;
      if (r == null) {
        if (node.paramChild != null) {
          // Before reporting the missing parameter, check whether the one
          // route this invocation can still reach (if resolvable
          // unambiguously) actually accepts every option already read: an
          // option the eventual route rejects is a more specific, more
          // useful error than "missing a value" (spec 8.6: help, and any
          // other option, loses to an option error once the route is
          // known). '--' rules out a leftover literal child exactly as an
          // operand does (once seen, the loop above never takes a literal
          // transition again, spec 8.2), so it counts as commitment here
          // too: without it, a literal sibling '--' has already made
          // unreachable would still be treated as a live possibility,
          // keeping this null and masking the option mismatch below it.
          final resolved = _resolvedRouteOf(
            node,
            committed: operandStarted || afterDoubleDash,
          );
          if (resolved != null) {
            final mismatch = optionsMismatch(resolved);
            if (mismatch != null) return mismatch;
          }
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
      final mismatch = optionsMismatch(r.route);
      if (mismatch != null) return mismatch;
      final finalScope = _routeScope(r.route, _globalOptions);
      for (final spec in finalScope) {
        if (spec.required && !consumedSpecs.contains(spec)) {
          return reject(
            CliRejectionKind.missingRequiredOption,
            route: r.route,
            message: 'missing required option ${_describeOption(spec)}',
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
        // '--' only ever ends option parsing before the program starts;
        // POSIX option ordering (spec 8.2) puts every option, '--' among
        // them, before the operand. Once an operand has started, '--' is
        // not an operand-forwarding marker any more, it is a misplaced
        // option: silently absorbing it here would make it vanish (an
        // operand of literally '--' would be indistinguishable from no
        // '--' at all) or fold what follows into `rest` unexpectedly.
        if (operandStarted) {
          return reject(
            CliRejectionKind.misplacedOption,
            route: _resolvedRouteOf(node, committed: operandStarted),
            message: "'--' goes before the program",
          );
        }
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
          scope: _scopeAt(node, _globalOptions),
          allRoutes: _flatRoutes,
          globalOptions: _globalOptions,
        );
        if (outcome is _OptionRead) {
          final parsed = outcome.parsed;
          if (!parsed.spec.repeatable && consumedSpecs.contains(parsed.spec)) {
            return reject(
              CliRejectionKind.repeatedOption,
              route: _resolvedRouteOf(node, committed: operandStarted),
              message: '${_describeOption(parsed.spec)} was already given',
            );
          }
          parsedOptions.add(parsed);
          consumedSpecs.add(parsed.spec);
          i = outcome.nextIndex;
          continue;
        }
        final failed = outcome as _OptionFailed;
        return reject(
          failed.kind,
          route: failed.route,
          message: failed.message,
        );
      }

      // Once an operand has started (spec 8.2 rule b), the resolver is
      // committed: no more literal route-word transitions, even if this
      // exact node still has literal children left over from some other
      // route's dead branch (grammar G already forbids a literal after a
      // parameter within a single route, so any left here can only belong
      // to a route this invocation can no longer take).
      if (!afterDoubleDash && !operandStarted) {
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
        // Grammar G forbids a literal after a parameter, so a node reached
        // through a required parameter can never have a literal child of
        // its own left to offer: consuming one always starts the operand.
        operandStarted = true;
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
        final mismatch = optionsMismatch(node.ownRoute!.route);
        if (mismatch != null) return mismatch;
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
  ///
  /// [stdout] and [stderr] are I/O wiring, not behavior: when `null` (the
  /// default), they fall back to the real process streams, [io.stdout] and
  /// [io.stderr]. This is the router's one deliberate default, made only to
  /// avoid forcing every caller to thread the process streams through by
  /// hand; pass a fake [io.IOSink] explicitly (e.g. in a test) to capture
  /// what a handler writes instead.
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
    final h = _composeMiddlewares(_middlewares, resolution.handler);
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
