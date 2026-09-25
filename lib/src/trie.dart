part of 'cli_router.dart';

// ---------------------------------------------------------------------------
// Pattern parsing: a route pattern is a space separated sequence of literal
// words, required `<name>` parameters, and, only as the very last segment,
// either one optional `[<name>]` parameter or one `*` wildcard.
// ---------------------------------------------------------------------------

enum _SegKind { literal, requiredParam, optionalParam, wildcard }

class _Seg {
  const _Seg._(this.kind, this.text, this.name);
  factory _Seg.literal(String text) => _Seg._(_SegKind.literal, text, null);
  factory _Seg.requiredParam(String name) =>
      _Seg._(_SegKind.requiredParam, null, name);
  factory _Seg.optionalParam(String name) =>
      _Seg._(_SegKind.optionalParam, null, name);
  factory _Seg.wildcard() => const _Seg._(_SegKind.wildcard, null, null);

  final _SegKind kind;
  final String? text;
  final String? name;
}

List<_Seg> _parseSegments(String pattern) {
  final words = pattern
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final segs = <_Seg>[];
  for (var idx = 0; idx < words.length; idx++) {
    final w = words[idx];
    final isLast = idx == words.length - 1;
    if (w == '*') {
      if (!isLast) {
        throw ArgumentError.value(
          pattern,
          'pattern',
          "'*' must be the last segment",
        );
      }
      segs.add(_Seg.wildcard());
    } else if (w.startsWith('[<') && w.endsWith('>]') && w.length > 4) {
      if (!isLast) {
        throw ArgumentError.value(
          pattern,
          'pattern',
          '[<name>] must be the last segment',
        );
      }
      segs.add(_Seg.optionalParam(w.substring(2, w.length - 2)));
    } else if (w.startsWith('<') && w.endsWith('>') && w.length > 2) {
      segs.add(_Seg.requiredParam(w.substring(1, w.length - 1)));
    } else {
      if (looksLikeOption(w)) {
        throw ArgumentError.value(
          pattern,
          'pattern',
          "'$w' looks like an option and cannot be a literal route segment",
        );
      }
      segs.add(_Seg.literal(w));
    }
  }
  return segs;
}

String _segsToPatternString(List<_Seg> segs) => segs
    .map((s) {
      switch (s.kind) {
        case _SegKind.literal:
          return s.text!;
        case _SegKind.requiredParam:
          return '<${s.name}>';
        case _SegKind.optionalParam:
          return '[<${s.name}>]';
        case _SegKind.wildcard:
          return '*';
      }
    })
    .join(' ');

// ---------------------------------------------------------------------------
// The trie itself.
// ---------------------------------------------------------------------------

class _RegisteredRoute {
  _RegisteredRoute({
    required this.route,
    required this.handler,
    required this.segments,
  });
  final CliRoute route;
  final CliHandler handler;
  final List<_Seg> segments;
}

class _TrieNode {
  final Map<String, _TrieNode> literalChildren = {};
  _TrieNode? paramChild;
  String? paramName;
  _RegisteredRoute? route;
  _RegisteredRoute? optionalParamRoute;
  _RegisteredRoute? wildcardRoute;

  _RegisteredRoute? get ownRoute =>
      route ?? optionalParamRoute ?? wildcardRoute;
}

/// Every route reachable from [start] by consuming zero or more required
/// parameters only, never a literal word: [start] itself, then its param
/// child, then that node's param child, and so on (a node has at most one
/// param child, so this walk never branches). A single node along the way
/// can contribute a route of its own, so more than one route can come back,
/// e.g. a root that has both its own `''` route and, through its param
/// child, a `<program>` route.
///
/// Used to compute the exploratory option scope at a node that has not
/// finished resolving yet (spec 8.2): every literal child is a route not
/// yet chosen, so its options are not offered here, but every route
/// reachable through required parameters alone might still be the one this
/// invocation resolves to, so its options are offered.
List<_RegisteredRoute> _routesReachableViaParamsOnly(_TrieNode start) {
  final routes = <_RegisteredRoute>[];
  var n = start;
  while (true) {
    final own = n.ownRoute;
    if (own != null) routes.add(own);
    if (n.paramChild == null) break;
    n = n.paramChild!;
  }
  return routes;
}

/// The exact option scope of one already known [route]: its own options,
/// plus [globalOptions] only when this specific route accepts globals.
/// Unlike [_scopeAt], this is never widened for ambiguity, since the route
/// is fixed; it is what actually governs whether a given option is accepted
/// once resolution reaches this route.
List<OptionSpec> _routeScope(CliRoute route, List<OptionSpec> globalOptions) =>
    route.globals ? [...route.options, ...globalOptions] : route.options;

/// The option scope at [node] while still resolving: the globals (always,
/// since which route this invocation lands on, and whether it accepts
/// globals, is not decided yet) plus the options of every route reachable
/// from [node] through required parameters only (spec 8.2). This decides
/// only whether a token is readable as an option at all at this position;
/// it does not mean every route reachable from here actually accepts it.
/// [_routeScope] is what a resolved route is checked against once
/// resolution is done.
List<OptionSpec> _scopeAt(_TrieNode node, List<OptionSpec> globalOptions) => [
  ...globalOptions,
  for (final r in _routesReachableViaParamsOnly(node)) ...r.route.options,
];

/// `spec.name` for an option, prefixed with its abbreviation when it has
/// one, for human readable rejection messages: `-f (--file)` or `--stdin`.
String _describeOption(OptionSpec spec) =>
    spec.abbr != null ? '-${spec.abbr} (--${spec.name})' : '--${spec.name}';

/// The one route [node] has already, unambiguously, resolved to: every
/// literal segment leading here has been consumed and no continuation
/// remains beyond this node's own terminal route (no literal child, no
/// param child). `null` while [node] could still lead to more than one
/// route, since naming a route then would be premature.
CliRoute? _deadEndRouteOf(_TrieNode node) {
  final own = node.ownRoute;
  if (own == null) return null;
  if (node.literalChildren.isNotEmpty) return null;
  if (node.paramChild != null) return null;
  return own.route;
}

void _insertSegments(_TrieNode root, List<_Seg> segs, _RegisteredRoute reg) {
  var node = root;
  for (var i = 0; i < segs.length; i++) {
    final seg = segs[i];
    switch (seg.kind) {
      case _SegKind.literal:
        node = node.literalChildren.putIfAbsent(seg.text!, () => _TrieNode());
      case _SegKind.requiredParam:
        if (node.optionalParamRoute != null || node.wildcardRoute != null) {
          throw StateError(
            "a required parameter cannot follow an already registered "
            'optional parameter or wildcard at this position',
          );
        }
        if (node.paramChild == null) {
          node.paramChild = _TrieNode();
          node.paramName = seg.name;
        } else if (node.paramName != seg.name) {
          throw StateError(
            'conflicting parameter names at the same position: '
            "'${node.paramName}' vs '${seg.name}'",
          );
        }
        node = node.paramChild!;
      case _SegKind.optionalParam:
        if (node.paramChild != null) {
          throw StateError(
            'an optional parameter cannot coexist with a required '
            'parameter at the same position',
          );
        }
        if (node.route != null ||
            node.optionalParamRoute != null ||
            node.wildcardRoute != null) {
          throw StateError('a route is already registered at this position');
        }
        node.optionalParamRoute = reg;
        return;
      case _SegKind.wildcard:
        if (node.paramChild != null) {
          throw StateError(
            'a wildcard cannot coexist with a required parameter at the '
            'same position',
          );
        }
        if (node.route != null ||
            node.optionalParamRoute != null ||
            node.wildcardRoute != null) {
          throw StateError('a route is already registered at this position');
        }
        node.wildcardRoute = reg;
        return;
    }
  }
  // Plain end: no trailing optional parameter or wildcard.
  if (node.route != null ||
      node.optionalParamRoute != null ||
      node.wildcardRoute != null) {
    throw StateError('a route is already registered at this position');
  }
  node.route = reg;
}

// ---------------------------------------------------------------------------
// Option-scope build-time validation (spec 8.2).
// ---------------------------------------------------------------------------

void _validateOptionScope(
  List<OptionSpec> options,
  bool globals,
  List<OptionSpec> globalOptions,
) {
  final names = <String>{};
  final abbrs = <String>{};
  for (final o in options) {
    if (!names.add(o.name)) {
      throw ArgumentError.value(
        o.name,
        'options',
        "duplicate option name '${o.name}' in the same route",
      );
    }
    final a = o.abbr;
    if (a != null && !abbrs.add(a)) {
      throw ArgumentError.value(
        a,
        'options',
        "duplicate option abbreviation '-$a' in the same route",
      );
    }
  }
  if (globals) {
    for (final g in globalOptions) {
      if (names.contains(g.name)) {
        throw ArgumentError.value(
          g.name,
          'options',
          "option '${g.name}' collides with a global option of the same "
              'name',
        );
      }
      final ga = g.abbr;
      if (ga != null && abbrs.contains(ga)) {
        throw ArgumentError.value(
          ga,
          'options',
          "option abbreviation '-$ga' collides with a global option",
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Option reading, for a single option-shaped token during resolve().
// ---------------------------------------------------------------------------

sealed class _OptionOutcome {}

class _OptionRead extends _OptionOutcome {
  _OptionRead(this.parsed, this.nextIndex);
  final ParsedOption parsed;
  final int nextIndex;
}

class _OptionFailed extends _OptionOutcome {
  _OptionFailed(this.kind, {this.route, this.message});
  final CliRejectionKind kind;
  final CliRoute? route;
  final String? message;
}

OptionSpec? _findInScope(List<OptionSpec> scope, String identity, bool isLong) {
  for (final s in scope) {
    if (isLong ? s.name == identity : s.abbr == identity) return s;
  }
  return null;
}

OptionSpec? _findAnyDeclaration(
  List<_RegisteredRoute> allRoutes,
  List<OptionSpec> globalOptions,
  String identity,
  bool isLong,
) {
  final inGlobals = _findInScope(globalOptions, identity, isLong);
  if (inGlobals != null) return inGlobals;
  for (final r in allRoutes) {
    final f = _findInScope(r.route.options, identity, isLong);
    if (f != null) return f;
  }
  return null;
}

int _skipWidthFor(
  OptionSpec spec,
  bool isLong,
  bool hasEquals,
  List<String> argv,
  int i,
) {
  if (!spec.takesValue) return 1;
  if (isLong && hasEquals) return 1;
  final hasNext = i + 1 < argv.length;
  final nextIsOptionLike =
      hasNext && (argv[i + 1] == '--' || looksLikeOption(argv[i + 1]));
  if (hasNext && !nextIsOptionLike) return 2;
  return 1;
}

/// Walks only literal and required-parameter transitions from [node] through
/// [remaining], to find which route the invocation would eventually reach if
/// this option token (and its value) were not there. Used only to name the
/// route in a [CliRejectionKind.misplacedOption] rejection (spec 8.2, rule
/// c); it never consumes options itself.
CliRoute? _lookAheadRoute(_TrieNode node, List<String> remaining) {
  var n = node;
  for (final tok in remaining) {
    final lit = n.literalChildren[tok];
    if (lit != null) {
      n = lit;
      continue;
    }
    if (n.paramChild != null) {
      n = n.paramChild!;
      continue;
    }
    break;
  }
  return n.ownRoute?.route;
}

bool _declaresInScope(
  CliRoute route,
  String identity,
  bool isLong,
  List<OptionSpec> globalOptions,
) =>
    _findInScope(_routeScope(route, globalOptions), identity, isLong) != null;

bool _peekIsLiteralChild(_TrieNode node, List<String> argv, int idx) =>
    idx < argv.length && node.literalChildren.containsKey(argv[idx]);

_OptionOutcome _readOption({
  required List<String> argv,
  required int i,
  required String token,
  required _TrieNode node,
  required bool operandStarted,
  required List<OptionSpec> scope,
  required List<_RegisteredRoute> allRoutes,
  required List<OptionSpec> globalOptions,
}) {
  final isLong = token.length >= 2 && token[0] == '-' && token[1] == '-';
  late final String identity;
  String? attachedValueRaw;
  var hasEquals = false;

  if (isLong) {
    final rest = token.substring(2);
    final eq = rest.indexOf('=');
    if (eq >= 0) {
      identity = rest.substring(0, eq);
      attachedValueRaw = rest.substring(eq + 1);
      hasEquals = true;
    } else {
      identity = rest;
    }
  } else {
    final rest = token.substring(1);
    if (rest.length != 1 || !_letter.hasMatch(rest)) {
      final isCluster =
          rest.isNotEmpty && RegExp(r'^[A-Za-z]+$').hasMatch(rest);
      final message = isCluster
          ? 'short options stand alone: '
                '${rest.split('').map((c) => '-$c').join(' ')}'
          : 'the value goes apart: -${rest[0]} '
                '${rest.substring(1).replaceFirst(RegExp('^='), '')}';
      return _OptionFailed(
        CliRejectionKind.invalidShortOption,
        route: _deadEndRouteOf(node),
        message: message,
      );
    }
    identity = rest;
  }

  // Rule (b), spec 8.2: an option read after an operand has started is
  // always misplaced, regardless of whether it is declared or known here.
  if (operandStarted) {
    return _OptionFailed(
      CliRejectionKind.misplacedOption,
      route: _deadEndRouteOf(node),
      message:
          'options go before the program: an option cannot follow an '
          'operand',
    );
  }

  final spec = _findInScope(scope, identity, isLong);
  final label = isLong ? '--$identity' : '-$identity';

  if (spec == null) {
    final declared = _findAnyDeclaration(
      allRoutes,
      globalOptions,
      identity,
      isLong,
    );
    if (declared == null) {
      return _OptionFailed(
        CliRejectionKind.unknownOption,
        route: _deadEndRouteOf(node),
        message: "unknown option '$label'",
      );
    }
    final skip = _skipWidthFor(declared, isLong, hasEquals, argv, i);
    final remaining = argv.sublist((i + skip).clamp(0, argv.length));
    final reached = _lookAheadRoute(node, remaining);
    if (reached != null) {
      if (_declaresInScope(reached, identity, isLong, globalOptions)) {
        return _OptionFailed(
          CliRejectionKind.misplacedOption,
          route: reached,
          message:
              'options go before the program: ${_describeOption(declared)} '
              "belongs to '${reached.pattern}'",
        );
      }
      return _OptionFailed(
        CliRejectionKind.unknownOption,
        route: reached,
        message:
            '${_describeOption(declared)} is not accepted by '
            "'${reached.pattern}'",
      );
    }
    return _OptionFailed(
      CliRejectionKind.unknownOption,
      route: _deadEndRouteOf(node),
      message: "unknown option '$label'",
    );
  }

  if (!spec.takesValue) {
    if (hasEquals) {
      return _OptionFailed(
        CliRejectionKind.unexpectedValue,
        route: _deadEndRouteOf(node),
        message: '${_describeOption(spec)} takes no value',
      );
    }
    if (_peekIsLiteralChild(node, argv, i + 1)) {
      final reached = _lookAheadRoute(node, argv.sublist(i + 1));
      return _OptionFailed(
        CliRejectionKind.misplacedOption,
        route: reached,
        message: _misplacedAheadMessage(spec, reached),
      );
    }
    return _OptionRead(
      ParsedOption(
        spec: spec,
        written: token,
        argvIndex: i,
        value: null,
        attached: false,
      ),
      i + 1,
    );
  }

  if (isLong && hasEquals) {
    if (_peekIsLiteralChild(node, argv, i + 1)) {
      final reached = _lookAheadRoute(node, argv.sublist(i + 1));
      return _OptionFailed(
        CliRejectionKind.misplacedOption,
        route: reached,
        message: _misplacedAheadMessage(spec, reached),
      );
    }
    return _OptionRead(
      ParsedOption(
        spec: spec,
        written: token,
        argvIndex: i,
        value: attachedValueRaw ?? '',
        attached: true,
      ),
      i + 1,
    );
  }

  final hasNext = i + 1 < argv.length;
  final nextIsOptionLike =
      hasNext && (argv[i + 1] == '--' || looksLikeOption(argv[i + 1]));
  if (!hasNext || nextIsOptionLike) {
    return _OptionFailed(
      CliRejectionKind.missingValue,
      route: _deadEndRouteOf(node),
      message: 'missing value for ${_describeOption(spec)}',
    );
  }
  if (_peekIsLiteralChild(node, argv, i + 2)) {
    final reached = _lookAheadRoute(node, argv.sublist(i + 2));
    return _OptionFailed(
      CliRejectionKind.misplacedOption,
      route: reached,
      message: _misplacedAheadMessage(spec, reached),
    );
  }
  return _OptionRead(
    ParsedOption(
      spec: spec,
      written: token,
      argvIndex: i,
      value: argv[i + 1],
      attached: false,
    ),
    i + 2,
  );
}

/// Message for a `misplacedOption` rejection where a route was found by
/// looking ahead past the option (spec 8.2 rule a): names it when the
/// lookahead is conclusive, otherwise states the general rule.
String _misplacedAheadMessage(OptionSpec spec, CliRoute? reached) =>
    reached != null
    ? 'options go before the program: ${_describeOption(spec)} belongs '
          "after '${reached.pattern}'"
    : 'options go before the program: ${_describeOption(spec)} was read '
          'before the route';
