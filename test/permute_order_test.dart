// OptionOrdering.permute (issue #8): GNU getopt style permutation of an
// option written after an operand, run before the strict grammar in
// posix_order_test.dart. resolve()'s default is OptionOrdering.permute, so
// most calls here pass no `ordering` argument at all.
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

import 'support.dart';

CliResolution _ok(CliOutcome outcome, {List<String>? reason}) {
  expect(outcome, isA<CliResolution>(), reason: 'for $reason, got $outcome');
  return outcome as CliResolution;
}

CliRejection _rejected(CliOutcome outcome, {List<String>? reason}) {
  expect(outcome, isA<CliRejection>(), reason: 'for $reason, got $outcome');
  return outcome as CliRejection;
}

void main() {
  group('rule: an option after an operand is accepted and moved in front', () {
    test('build app --verbose : the flag binds to the resolved route', () {
      final router = buildPermuteDemoRouter();
      final args = ['build', 'app', '--verbose'];
      final result = _ok(router.resolve(args), reason: args);
      expect(result.route.pattern, equals('build <target>'));
      expect(result.params['target'], equals('app'));
      expect(result.options.single.spec.name, equals('verbose'));
    });

    test(
      'the same invocation is misplacedOption under OptionOrdering.strict',
      () {
        final router = buildPermuteDemoRouter();
        final rejection = _rejected(
          router.resolve([
            'build',
            'app',
            '--verbose',
          ], ordering: OptionOrdering.strict),
        );
        expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      },
    );
  });

  group('rule: relative order is preserved within each group', () {
    test('build app -t v1 --verbose : both options keep their own order', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(
        router.resolve(['build', 'app', '-t', 'v1', '--verbose']),
      );
      expect(result.params['target'], equals('app'));
      expect(
        result.options.map((o) => o.spec.name).toList(),
        equals(['tag', 'verbose']),
      );
      expect(result.options.first.value, equals('v1'));
    });

    test('copy a b --force : both operands keep their own order', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(router.resolve(['copy', 'a', 'b', '--force']));
      expect(result.params['src'], equals('a'));
      expect(result.params['dst'], equals('b'));
    });

    test('copy a --force b : an option between two operands does not '
        'swap them', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(router.resolve(['copy', 'a', '--force', 'b']));
      expect(result.params['src'], equals('a'));
      expect(result.params['dst'], equals('b'));
      expect(result.options.single.spec.name, equals('force'));
    });
  });

  group('rule: a value option moves together with its value', () {
    test('build app -t v1 : the value stays attached to -t', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(router.resolve(['build', 'app', '-t', 'v1']));
      expect(result.params['target'], equals('app'));
      final tag = result.options.single;
      expect(tag.spec.name, equals('tag'));
      expect(tag.value, equals('v1'));
    });

    test('build app --tag=v1 : an attached value also moves as one unit', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(router.resolve(['build', 'app', '--tag=v1']));
      expect(result.options.single.value, equals('v1'));
      expect(result.options.single.attached, isTrue);
    });
  });

  group("rule: '--' stops the rewrite", () {
    test('run -- --verbose : the token after -- is never treated as an '
        'option, permuted or not', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(router.resolve(['run', '--', '--verbose']));
      expect(result.route.pattern, equals('run'));
      expect(result.route.hasWildcard, isTrue);
      expect(result.rest, equals(['--verbose']));
      expect(result.options, isEmpty);
    });

    test('run a --verbose -- --literal : the wildcard\'s first captured '
        'token already starts the frozen region below, so this later, '
        'explicit -- is just more data inside it, not a second boundary', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(
        router.resolve(['run', 'a', '--verbose', '--', '--literal']),
      );
      expect(result.rest, equals(['a', '--verbose', '--', '--literal']));
      expect(result.options, isEmpty);
    });

    test(
      'the same invocation is misplacedOption under OptionOrdering.strict',
      () {
        final router = buildPermuteDemoRouter();
        final rejection = _rejected(
          router.resolve([
            'run',
            'a',
            '--verbose',
            '--',
            '--literal',
          ], ordering: OptionOrdering.strict),
        );
        expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      },
    );
  });

  group('rule: inside a * wildcard route, nothing from the first captured '
      'token on is ever an option again', () {
    test('run a -v : the docker run IMAGE CMD -flags case; once the first '
        'wildcard token appears, it and everything after it are operands, '
        'even when they look like an option', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(router.resolve(['run', 'a', '-v']));
      expect(result.route.pattern, equals('run'));
      expect(result.route.hasWildcard, isTrue);
      expect(result.rest, equals(['a', '-v']));
      expect(result.options, isEmpty);
    });

    test('the same invocation is misplacedOption under OptionOrdering.strict, '
        'confirming permute changed the outcome, not just the argv', () {
      final router = buildPermuteDemoRouter();
      final rejection = _rejected(
        router.resolve(['run', 'a', '-v'], ordering: OptionOrdering.strict),
      );
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
    });

    test('run -v a : an option written before the wildcard\'s first token '
        'is unaffected and still applies', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(router.resolve(['run', '-v', 'a']));
      expect(result.rest, equals(['a']));
      expect(result.options.single.spec.name, equals('verbose'));
    });

    test('sync push --force a b : an option between the required parameter '
        'and the wildcard\'s first token is still permuted', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(router.resolve(['sync', 'push', '--force', 'a', 'b']));
      expect(result.route.pattern, equals('sync <mode>'));
      expect(result.route.hasWildcard, isTrue);
      expect(result.params['mode'], equals('push'));
      expect(result.rest, equals(['a', 'b']));
      expect(result.options.single.spec.name, equals('force'));
    });

    test('the same invocation is misplacedOption under OptionOrdering.strict, '
        'confirming permute changed the outcome, not just the argv', () {
      final router = buildPermuteDemoRouter();
      final rejection = _rejected(
        router.resolve([
          'sync',
          'push',
          '--force',
          'a',
          'b',
        ], ordering: OptionOrdering.strict),
      );
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
    });

    test('sync push a --force b : once the wildcard has already captured '
        'its first token, a later option is data too, not misplaced', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(router.resolve(['sync', 'push', 'a', '--force', 'b']));
      expect(result.params['mode'], equals('push'));
      expect(result.rest, equals(['a', '--force', 'b']));
      expect(result.options, isEmpty);
    });

    test(
      'the same invocation is misplacedOption under OptionOrdering.strict',
      () {
        final router = buildPermuteDemoRouter();
        final rejection = _rejected(
          router.resolve([
            'sync',
            'push',
            'a',
            '--force',
            'b',
          ], ordering: OptionOrdering.strict),
        );
        expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      },
    );
  });

  group("rule 4: '--' ends option parsing anywhere, not only before the "
      'first operand', () {
    test('copy a -- b : an operand before -- and an operand after it are '
        'both bound, in their original relative order', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(router.resolve(['copy', 'a', '--', 'b']));
      expect(result.params['src'], equals('a'));
      expect(result.params['dst'], equals('b'));
    });

    test('the same invocation is misplacedOption under OptionOrdering.strict, '
        'confirming permute changed the outcome, not just the argv', () {
      final router = buildPermuteDemoRouter();
      final rejection = _rejected(
        router.resolve([
          'copy',
          'a',
          '--',
          'b',
        ], ordering: OptionOrdering.strict),
      );
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
    });

    test('copy --force a -- b : an option written before the first operand '
        'is hoisted exactly as usual, and the split operand is still '
        'rescued', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(router.resolve(['copy', '--force', 'a', '--', 'b']));
      expect(result.params['src'], equals('a'));
      expect(result.params['dst'], equals('b'));
      expect(result.options.single.spec.name, equals('force'));
    });

    test('copy a --force -- b : an option written after the first operand '
        'but before -- is hoisted too, and the split operand is still '
        'rescued', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(router.resolve(['copy', 'a', '--force', '--', 'b']));
      expect(result.params['src'], equals('a'));
      expect(result.params['dst'], equals('b'));
      expect(result.options.single.spec.name, equals('force'));
    });

    test('copy a -- -b : everything after -- is data, never reclassified '
        'as an option, however it looks', () {
      final router = buildPermuteDemoRouter();
      final result = _ok(router.resolve(['copy', 'a', '--', '-b']));
      expect(result.params['src'], equals('a'));
      expect(result.params['dst'], equals('-b'));
      expect(result.options, isEmpty);
    });
  });

  group('rule 4 does not silently drop a dangling --', () {
    test('copy a b -- : nothing follows the marker, so it is left exactly '
        'where it was and the unchanged strict grammar rejects it', () {
      final router = buildPermuteDemoRouter();
      final rejection = _rejected(router.resolve(['copy', 'a', 'b', '--']));
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
    });
  });

  group('a value option hoisted without a value of its own must never '
      'absorb an unrelated, relocated operand as its value (regression)', () {
    test('eval rpn demo --file : a trailing value option with nothing '
        'after it must not swallow the operand that preceded it once both '
        'are moved next to each other', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(
        router.resolve(['eval', 'rpn', 'demo', '--file']),
      );
      expect(rejection.kind, equals(CliRejectionKind.missingValue));
    });

    test('eval rpn demo -f : the same bug, through the short spelling', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(
        router.resolve(['eval', 'rpn', 'demo', '-f']),
      );
      expect(rejection.kind, equals(CliRejectionKind.missingValue));
    });

    test('eval rpn demo --file -- : a value option immediately followed '
        'only by -- has no value either, ; is never allowed to reach '
        'across -- for one', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(
        router.resolve(['eval', 'rpn', 'demo', '--file', '--']),
      );
      expect(rejection.kind, equals(CliRejectionKind.missingValue));
    });
  });

  group('rule: an option before the route word that declares it stays an '
      'error', () {
    test('-f prog.rpn eval rpn : permutation never crosses an unresolved '
        'route boundary, so this is still misplacedOption, exactly as in '
        'strict mode', () {
      final router = buildCalculatrixRouter();
      final rejection = _rejected(
        router.resolve(['-f', 'prog.rpn', 'eval', 'rpn']),
      );
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route?.pattern, equals('eval rpn'));
    });
  });

  group('rule: a negative number stays an operand and is never moved as if '
      'it were an option', () {
    test('eval rpn -1 --json : --json moves in front of -1, which stays '
        'the program', () {
      final router = buildCalculatrixRouter();
      final result = _ok(router.resolve(['eval', 'rpn', '-1', '--json']));
      expect(result.params['program'], equals('-1'));
      expect(result.options.single.spec.name, equals('json'));
    });

    test(
      'the same invocation is misplacedOption under OptionOrdering.strict',
      () {
        final router = buildCalculatrixRouter();
        final rejection = _rejected(
          router.resolve([
            'eval',
            'rpn',
            '-1',
            '--json',
          ], ordering: OptionOrdering.strict),
        );
        expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      },
    );
  });

  group('run() picks OptionOrdering from POSIXLY_CORRECT', () {
    test('without POSIXLY_CORRECT, run() permutes', () async {
      final router = buildPermuteDemoRouter();
      final code = await router.run(
        ['build', 'app', '--verbose'],
        onReject: (r) async => 64,
        environment: const {},
      );
      expect(code, equals(0));
    });

    test('with POSIXLY_CORRECT set, run() is strict', () async {
      final router = buildPermuteDemoRouter();
      CliRejection? captured;
      final code = await router.run(
        ['build', 'app', '--verbose'],
        onReject: (r) async {
          captured = r;
          return 64;
        },
        environment: const {'POSIXLY_CORRECT': '1'},
      );
      expect(code, equals(64));
      expect(captured?.kind, equals(CliRejectionKind.misplacedOption));
    });

    test('POSIXLY_CORRECT set to an empty string still counts, matching '
        'getopt\'s own convention of checking presence, not value', () async {
      final router = buildPermuteDemoRouter();
      final code = await router.run(
        ['build', 'app', '--verbose'],
        onReject: (r) async => 64,
        environment: const {'POSIXLY_CORRECT': ''},
      );
      expect(code, equals(64));
    });

    test('with no environment argument at all, run() falls back to the '
        'real process environment (exercised only for coverage: this '
        'process is not expected to have POSIXLY_CORRECT set)', () async {
      final router = buildPermuteDemoRouter();
      final code = await router.run([
        'build',
        'app',
        '--verbose',
      ], onReject: (r) async => 64);
      expect(code, equals(0));
    });
  });
}
