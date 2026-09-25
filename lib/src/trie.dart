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

/// The single route reachable from [start] without reading any more of the
/// invocation, when that is unambiguous: a chain of nodes that each have no
/// possible continuation other than a required parameter, ending at a node
/// with its own route. `null` when [start] is itself branching (more than
/// one possible continuation), since which route eventually applies then
/// depends on a token not read yet.
///
/// Used only to widen the option scope at a pre-route node so an option
/// declared by the one route ahead can be read before its required
/// parameters, e.g. `greet --loud <name>`.
_RegisteredRoute? _deterministicRoute(_TrieNode start) {
  var n = start;
  while (true) {
    final own = n.ownRoute;
    if (own != null) return own;
    final onlyPath =
        n.paramChild != null &&
        n.literalChildren.isEmpty &&
        n.optionalParamRoute == null &&
        n.wildcardRoute == null;
    if (!onlyPath) return null;
    n = n.paramChild!;
  }
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
  _OptionFailed(this.kind, [this.route]);
  final CliRejectionKind kind;
  final CliRoute? route;
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
) {
  final scope = route.globals
      ? [...route.options, ...globalOptions]
      : route.options;
  return _findInScope(scope, identity, isLong) != null;
}

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
      return _OptionFailed(CliRejectionKind.invalidShortOption);
    }
    identity = rest;
  }

  // Rule (b), spec 8.2: an option read after an operand has started is
  // always misplaced, regardless of whether it is declared or known here.
  if (operandStarted) {
    return _OptionFailed(CliRejectionKind.misplacedOption);
  }

  final spec = _findInScope(scope, identity, isLong);

  if (spec == null) {
    final declared = _findAnyDeclaration(
      allRoutes,
      globalOptions,
      identity,
      isLong,
    );
    if (declared == null) {
      return _OptionFailed(CliRejectionKind.unknownOption);
    }
    final skip = _skipWidthFor(declared, isLong, hasEquals, argv, i);
    final remaining = argv.sublist((i + skip).clamp(0, argv.length));
    final reached = _lookAheadRoute(node, remaining);
    if (reached != null &&
        _declaresInScope(reached, identity, isLong, globalOptions)) {
      return _OptionFailed(CliRejectionKind.misplacedOption, reached);
    }
    return _OptionFailed(CliRejectionKind.unknownOption);
  }

  if (!spec.takesValue) {
    if (hasEquals) {
      return _OptionFailed(CliRejectionKind.unexpectedValue);
    }
    if (_peekIsLiteralChild(node, argv, i + 1)) {
      return _OptionFailed(CliRejectionKind.misplacedOption);
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
      return _OptionFailed(CliRejectionKind.misplacedOption);
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
    return _OptionFailed(CliRejectionKind.missingValue);
  }
  if (_peekIsLiteralChild(node, argv, i + 2)) {
    return _OptionFailed(CliRejectionKind.misplacedOption);
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
