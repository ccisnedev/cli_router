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
  // Grammar G: route words are literals, params are operands, and options
  // go before operands. Once a param (required, optional, or wildcard) has
  // been seen, no further literal route word can follow it: the invocation
  // has already committed to an operand by then, so a later word cannot go
  // back to being route vocabulary.
  var paramSeen = false;
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
      paramSeen = true;
    } else if (w.startsWith('[<') && w.endsWith('>]') && w.length > 4) {
      if (!isLast) {
        throw ArgumentError.value(
          pattern,
          'pattern',
          '[<name>] must be the last segment',
        );
      }
      segs.add(_Seg.optionalParam(w.substring(2, w.length - 2)));
      paramSeen = true;
    } else if (w.startsWith('<') && w.endsWith('>') && w.length > 2) {
      segs.add(_Seg.requiredParam(w.substring(1, w.length - 1)));
      paramSeen = true;
    } else {
      if (looksLikeOption(w)) {
        throw ArgumentError.value(
          pattern,
          'pattern',
          "'$w' looks like an option and cannot be a literal route segment",
        );
      }
      if (paramSeen) {
        throw ArgumentError.value(
          pattern,
          'pattern',
          "'$w' is a literal route word after a parameter; route words "
              'must come before every parameter (grammar G: params are '
              'operands, and operands come last)',
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

/// One position in the routing trie.
///
/// Per issue #6 section 1, a node holds at most one literal child per
/// word, at most one [paramChild] (a required parameter, which continues
/// into a further subtree), and at most one [wildcardRoute] (a final `*`,
/// always terminal). A [paramChild] and a [wildcardRoute] may coexist on
/// the same node: they are not a conflict, only a precedence to resolve at
/// match time (spec 8.1: "a literal child wins ... then the parameter,
/// then the wildcard, else reject").
///
/// That precedence is unconditional and needs no lookahead: while an operand
/// token remains, it always goes to [paramChild], with no exception for the
/// last token and no inspection of the parameter's own subtree. The
/// wildcard is reached only when argv ends exactly at this node and the
/// node has no route of its own (`ownRoute` is `null` other than through
/// [wildcardRoute] itself), where it matches zero operands; see
/// `CliRouter.resolve`'s `finishHere` closure for the implementation. Once a
/// token has been bound to [paramChild], the decision is never revisited: a
/// later token the parameter's subtree cannot accept fails there
/// (`extraArgument` or `missingArgument`) rather than reopening the choice
/// and trying the wildcard instead.
///
/// [optionalParamRoute] (a final `[<name>]`) and [wildcardRoute] can never
/// coexist on the same node, in either registration order: an optional
/// parameter already matches every operand count, zero or one, that a
/// wildcard at the same position could otherwise catch, so the wildcard
/// route could never be reached. Registering both is a build-time
/// [ArgumentError] (see `_unreachableWildcardError`), not a resolution-time
/// precedence, since no invocation could ever resolve to the wildcard.
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

/// The one route [node] has already, unambiguously, resolved to.
///
/// When [committed] is `false` (no operand has started yet: every token so
/// far was a route word), a literal child still pending means more than one
/// route remains possible, so this returns `null`; naming one then would be
/// premature. When [committed] is `true` (an operand has started: spec 8.2
/// rule b says the invocation cannot go back to being route vocabulary from
/// here), any literal children left on [node] are unreachable dead weight
/// (grammar G forbids a literal after a parameter, so they can only belong
/// to a route this invocation can no longer take), so only the routes still
/// reachable through required parameters decide the answer: exactly one
/// candidate names it, more than one (or none) is still `null`.
CliRoute? _resolvedRouteOf(_TrieNode node, {required bool committed}) {
  if (!committed && node.literalChildren.isNotEmpty) return null;
  final reachable = _routesReachableViaParamsOnly(node);
  if (reachable.length != 1) return null;
  return reachable.single.route;
}

/// Copies every literal word reachable from [source], recursively, into
/// [target], creating nodes as needed but never overwriting or removing one
/// already there. Used by [CliRouter.mount] to preserve a mounted router's
/// own reserved words (words with a trie node of their own but no route,
/// typically from that router's own empty mount) even though replaying only
/// its flattened routes would never recreate a routeless node.
///
/// Does not copy routes: [CliRouter.mount] registers those itself, through
/// [CliRouter.cmd], so every build-time check runs again in the mounting
/// router's own context. This only mirrors the shape of [source]'s literal
/// trie, so a word it reserves stays reserved here too.
void _mirrorReservedWords(_TrieNode target, _TrieNode source) {
  source.literalChildren.forEach((word, sourceChild) {
    final targetChild = target.literalChildren.putIfAbsent(
      word,
      () => _TrieNode(),
    );
    _mirrorReservedWords(targetChild, sourceChild);
  });
}

/// An [ArgumentError] for registering an optional parameter and a wildcard
/// at the same trie position, in either order (see the dartdoc on
/// [_TrieNode] for the full rule). The message names [optionalParam] and
/// [wildcard] by role, not by which one was registered first or second, so
/// it reads identically regardless of registration order.
ArgumentError _unreachableWildcardError(
  _RegisteredRoute optionalParam,
  _RegisteredRoute wildcard,
) => ArgumentError(
  "the optional parameter route '${_segsToPatternString(optionalParam.segments)}' "
  "and the wildcard route '${_segsToPatternString(wildcard.segments)}' cannot "
  'both be registered at the same position: the optional parameter already '
  'matches every operand count (zero or one) that the wildcard could '
  'otherwise catch, so the wildcard route would be unreachable',
);

void _insertSegments(_TrieNode root, List<_Seg> segs, _RegisteredRoute reg) {
  var node = root;
  for (var i = 0; i < segs.length; i++) {
    final seg = segs[i];
    switch (seg.kind) {
      case _SegKind.literal:
        node = node.literalChildren.putIfAbsent(seg.text!, () => _TrieNode());
      case _SegKind.requiredParam:
        // A wildcard already registered at this position is not a
        // conflict: per issue #6 section 1, a node may hold both a
        // parameter and a final wildcard at once, with precedence, not
        // exclusivity, deciding between them at resolution time (see
        // `_TrieNode.wildcardRoute`). An optional parameter, though, is
        // itself a route terminal at this exact position, the same as a
        // plain route would be, so it still conflicts with a required
        // parameter continuing past it.
        if (node.optionalParamRoute != null) {
          throw StateError(
            "a required parameter cannot follow an already registered "
            'optional parameter at this position',
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
        if (node.wildcardRoute != null) {
          throw _unreachableWildcardError(reg, node.wildcardRoute!);
        }
        if (node.route != null || node.optionalParamRoute != null) {
          throw StateError('a route is already registered at this position');
        }
        node.optionalParamRoute = reg;
        return;
      case _SegKind.wildcard:
        // A required parameter already registered at this position (a
        // `paramChild`) is not a conflict: see the matching comment in the
        // `requiredParam` case above.
        if (node.optionalParamRoute != null) {
          throw _unreachableWildcardError(node.optionalParamRoute!, reg);
        }
        if (node.route != null || node.wildcardRoute != null) {
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
  // A route option always shadows nothing: colliding with a global by name
  // or abbreviation is an ArgumentError regardless of whether the route
  // itself accepts globals (`globals: false` does not carve out an
  // exception; it only means the route does not accept its own globals, not
  // that it may reuse their names for something else).
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

/// Whether [a] and [b] declare exactly the same options, by shape, as a
/// set (order does not matter). Used by [CliRouter.mount] to enforce "one
/// program, one set of globals": a mounted router's own `globalOptions`
/// must equal the parent's exactly, since `mount()` never carries a
/// subrouter's `globalOptions` along, only each route's own `options` and
/// `globals` flag.
///
/// Comparing length plus one-way containment is equivalent to true set
/// equality here only because [_validateOptionScope] already guarantees
/// neither list holds two options with the same name (nor two with the
/// same abbreviation): duplicates within a single `globalOptions` list are
/// already a build-time error, so this cannot be fooled by a duplicate on
/// one side that the other side is missing.
bool _sameOptionSet(List<OptionSpec> a, List<OptionSpec> b) =>
    a.length == b.length && a.every(b.contains);

/// The node reached by following only the leading literal segments of
/// [segs] from [root], stopping at the first non-literal segment (or the
/// end). `null` when some literal segment along the way has not been
/// registered yet, since then no other route can already share this
/// position. Never mutates the trie: used only to look up existing sibling
/// routes before a new one is inserted (spec 8.2's sibling option-scope
/// check, items 4+5), so a build-time error can be raised before the trie
/// is touched.
_TrieNode? _existingLiteralPrefixNode(_TrieNode root, List<_Seg> segs) {
  var node = root;
  for (final seg in segs) {
    if (seg.kind != _SegKind.literal) break;
    final next = node.literalChildren[seg.text];
    if (next == null) return null;
    node = next;
  }
  return node;
}

/// Throws an [ArgumentError] when [newRoute] declares an option that shares
/// a name or abbreviation, but not the full shape, with an option already
/// declared by some other route reachable from [boundaryNode] through
/// required parameters only (spec 8.2, items 4+5): these routes can be
/// resolved to through the very same option-reading position (`_scopeAt`),
/// so an ambiguous, differently shaped option there would make which
/// declaration governs a given invocation depend on which route it
/// eventually resolves to, decided only after the option has already been
/// read. Two routes declaring the identical shape are fine: per
/// `OptionSpec.==`, that is the same option, not a conflict.
void _validateSiblingOptionScope(_TrieNode boundaryNode, CliRoute newRoute) {
  for (final sibling in _routesReachableViaParamsOnly(boundaryNode)) {
    if (identical(sibling.route, newRoute)) continue;
    for (final a in newRoute.options) {
      for (final b in sibling.route.options) {
        final sameName = a.name == b.name;
        final sameAbbr = a.abbr != null && a.abbr == b.abbr;
        if ((sameName || sameAbbr) && a != b) {
          throw ArgumentError(
            "option ${_describeOption(a)} on '${newRoute.pattern}' and "
            '${_describeOption(b)} on '
            "'${sibling.route.pattern}' share a name or abbreviation but "
            'have different shapes; declare them identically to treat '
            'them as the same option, or give one a different name and '
            'abbreviation',
          );
        }
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
///
/// Returns `null` the moment [remaining] is interrupted by an option-shaped
/// token: that token is never a literal route word or a required
/// parameter's value, so simulating either transition for it would walk to
/// the wrong node (spec 8.2 rule a). This is deliberately `null`, not
/// [node]'s own preexisting route: [node] may already own a route from
/// before this option was ever read (for example the root's own `''`
/// route), and returning it here would wrongly present that unrelated,
/// already-resolved route as the conclusive destination of a walk that
/// never actually got to look at the tokens after the interruption. The
/// caller falls back to `_routesInSubtreeDeclaring` whenever this returns
/// an inconclusive `null`.
CliRoute? _lookAheadRoute(_TrieNode node, List<String> remaining) {
  var n = node;
  for (final tok in remaining) {
    if (looksLikeOption(tok)) return null;
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

bool _peekIsLiteralChild(_TrieNode node, List<String> argv, int idx) =>
    idx < argv.length && node.literalChildren.containsKey(argv[idx]);

/// Every route in the subtree rooted at [node] (its own route if any, then
/// recursively through its param child and every literal child) that
/// declares an option matching [identity] as a long ([isLong]) or short
/// name, among that route's own options.
///
/// Used to decide misplacement for an option token that lookahead could not
/// resolve to one conclusive route (spec 8.2 rule a): lookahead
/// (`_lookAheadRoute`) gives up the moment it hits a token that is not a
/// literal or required-parameter match, including another option token, so
/// an option interrupted by a second option before its own route is reached
/// must instead be judged by whether *some* route still reachable from here
/// declares it at all, not by where an uninterrupted walk would have ended.
List<CliRoute> _routesInSubtreeDeclaring(
  _TrieNode node,
  String identity,
  bool isLong,
) {
  final found = <CliRoute>[];
  void visit(_TrieNode n) {
    final own = n.ownRoute;
    if (own != null &&
        _findInScope(own.route.options, identity, isLong) != null) {
      found.add(own.route);
    }
    if (n.paramChild != null) visit(n.paramChild!);
    for (final child in n.literalChildren.values) {
      visit(child);
    }
  }

  visit(node);
  return found;
}

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
        route: _resolvedRouteOf(node, committed: operandStarted),
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
      route: _resolvedRouteOf(node, committed: operandStarted),
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
        route: _resolvedRouteOf(node, committed: operandStarted),
        message: "unknown option '$label'",
      );
    }
    // Whether this is misplacedOption (some route still reachable from
    // here declares it) or unknownOption (no route reachable from here
    // does) is decided from the whole subtree rooted at this node (spec
    // 8.2 rule a), not from a single lookahead guess: an uninterrupted
    // lookahead can land on a route that does not itself declare the
    // option (this node's own preexisting route, reached only because
    // there happen to be no more tokens to walk) while a route still
    // further down the same subtree does, and the subtree declaration is
    // the correct answer in that case, whatever route the current node
    // itself already owns.
    final candidates = _routesInSubtreeDeclaring(node, identity, isLong);
    if (candidates.isEmpty) {
      return _OptionFailed(
        CliRejectionKind.unknownOption,
        route: _resolvedRouteOf(node, committed: operandStarted),
        message: "unknown option '$label'",
      );
    }
    // The shape that actually governs how many tokens this option reads
    // (flag vs. value, and so the lookahead's skip width) must come from
    // what is reachable in this subtree, never from `declared`: spec 8.2
    // lets an unrelated branch declare the same name or abbreviation with
    // a different shape, and using that unrelated declaration's shape here
    // would consume the wrong number of tokens, walk lookahead to the
    // wrong node, and even make the outcome depend on the registration
    // order `_findAnyDeclaration` happened to search in. Only when every
    // candidate agrees on the shape is it safe to use for a skip width at
    // all; when they disagree, guessing one of them is exactly the kind of
    // guess this must not make.
    OptionSpec? subtreeShape;
    var shapesDiffer = false;
    for (final route in candidates) {
      final s = _findInScope(route.options, identity, isLong)!;
      if (subtreeShape == null) {
        subtreeShape = s;
      } else if (subtreeShape != s) {
        shapesDiffer = true;
        break;
      }
    }

    CliRoute? single;
    if (!shapesDiffer) {
      final skip = _skipWidthFor(subtreeShape!, isLong, hasEquals, argv, i);
      final remaining = argv.sublist((i + skip).clamp(0, argv.length));
      final reached = _lookAheadRoute(node, remaining);
      // Prefer the route an uninterrupted lookahead actually reached, but
      // only when it is itself one of the candidates: naming a route from
      // outside the subtree declaration set would be just as wrong as the
      // root's-own-route failure this is fixing. Otherwise, exactly one
      // candidate can still be named with certainty; more than one means
      // the option is misplaced, just not to a single identifiable route,
      // since which of them this invocation would have reached cannot be
      // known without the tokens an interruption consumed.
      single = reached != null && candidates.contains(reached)
          ? reached
          : (candidates.length == 1 ? candidates.single : null);
    }
    // shapesDiffer implies at least two candidates disagree, so `single`
    // is left null: still misplacedOption, with every candidate listed.
    //
    // The label in the message must come from the reachable declaration
    // (`subtreeShape`), never from `declared`: `declared` is only used
    // above to tell unknownOption from misplacedOption, and
    // `_findAnyDeclaration`'s router-wide search can land on an unrelated
    // route that happens to declare the same name or abbreviation with a
    // different shape (spec 8.2 permits that on unrelated branches). Using
    // it here would describe the option by a declaration this invocation
    // can never reach. When the reachable declarations disagree
    // (`shapesDiffer`), there is no single reachable shape to describe it
    // by either, so the label falls back to the spelling the user typed.
    final optionLabel = !shapesDiffer ? _describeOption(subtreeShape!) : label;
    return _OptionFailed(
      CliRejectionKind.misplacedOption,
      route: single,
      message: single != null
          ? 'options go before the program: $optionLabel '
                "belongs to '${single.pattern}'"
          : 'options go before the program: $optionLabel '
                'belongs to one of: '
                '${candidates.map((r) => "'${r.pattern}'").join(', ')}',
    );
  }

  if (!spec.takesValue) {
    if (hasEquals) {
      return _OptionFailed(
        CliRejectionKind.unexpectedValue,
        route: _resolvedRouteOf(node, committed: operandStarted),
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
      route: _resolvedRouteOf(node, committed: operandStarted),
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
