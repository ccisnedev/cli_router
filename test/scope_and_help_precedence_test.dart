// Amendment to issue #6: the SDK decides help precedence from the
// rejection, so every rejection of kind `incomplete`, `missingArgument` and
// `missingRequiredOption` must carry every option read before `--` up to
// that point, including globals like -h/--help, even when the node that
// rejects has no route of its own yet (globals are always in scope; a
// route's own options are in scope only once its literal segments are all
// consumed).
import 'package:cli_router/cli_router.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('global options are in scope before a route is resolved', () {
    test('eval --help: incomplete, carries [help], consumed [eval]', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['eval', '--help']);

      expect(outcome, isA<CliRejection>());
      final rejection = outcome as CliRejection;
      expect(rejection.kind, equals(CliRejectionKind.incomplete));
      expect(rejection.consumed, equals(['eval']));
      expect(rejection.options, hasLength(1));
      expect(rejection.options.single.spec.name, equals('help'));
      expect(rejection.options.single.written, equals('--help'));
    });

    test('commands show --help: missingArgument, carries [help], consumed '
        '[commands, show]', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['commands', 'show', '--help']);

      expect(outcome, isA<CliRejection>());
      final rejection = outcome as CliRejection;
      expect(rejection.kind, equals(CliRejectionKind.missingArgument));
      expect(rejection.consumed, equals(['commands', 'show']));
      expect(rejection.options, hasLength(1));
      expect(rejection.options.single.spec.name, equals('help'));
    });

    test('a global read at a branching node does not need that node to '
        'declare its own route', () {
      final router = buildCalculatrixRouter();
      // 'eval' itself is not a route (only 'eval rpn' and 'eval infix'
      // are), yet -q (global) is readable there.
      final outcome = router.resolve(['eval', '-q']);

      expect(outcome, isA<CliRejection>());
      final rejection = outcome as CliRejection;
      expect(rejection.kind, equals(CliRejectionKind.incomplete));
      expect(rejection.options.single.spec.name, equals('quiet'));
    });

    test('a route-specific option is still misplaced at an ancestor node, '
        'even though globals are in scope there', () {
      final router = buildCalculatrixRouter();
      // -f belongs to 'eval rpn' / 'eval infix', not to 'eval' itself.
      final outcome = router.resolve(['eval', '-f', 'p.rpn', 'rpn']);

      expect(outcome, isA<CliRejection>());
      final rejection = outcome as CliRejection;
      expect(rejection.kind, equals(CliRejectionKind.misplacedOption));
      expect(rejection.route?.pattern, equals('eval rpn'));
    });

    test('a genuinely unknown option at a branching node is unknownOption, '
        'not incomplete', () {
      final router = buildCalculatrixRouter();
      final outcome = router.resolve(['eval', '--bogus']);

      expect(outcome, isA<CliRejection>());
      expect(
        (outcome as CliRejection).kind,
        equals(CliRejectionKind.unknownOption),
      );
    });
  });

  group('missingRequiredOption is decided only after every option is read', () {
    test('a missing required option is reported with every prior option '
        'kept in the rejection', () {
      final router = CliRouter(
        globalOptions: [OptionSpec.flag('json', abbr: null, repeatable: false)],
      );
      router.cmd(
        'push',
        (req) async => 0,
        options: [
          OptionSpec.value(
            'target',
            abbr: 't',
            required: true,
            repeatable: false,
          ),
          OptionSpec.flag('force', abbr: null, repeatable: false),
        ],
        globals: true,
      );

      final outcome = router.resolve(['push', '--json', '--force']);

      expect(outcome, isA<CliRejection>());
      final rejection = outcome as CliRejection;
      expect(rejection.kind, equals(CliRejectionKind.missingRequiredOption));
      expect(
        rejection.options.map((o) => o.spec.name),
        equals(['json', 'force']),
      );
    });

    test('present required option succeeds instead of rejecting', () {
      final router = CliRouter();
      router.cmd(
        'push',
        (req) async => 0,
        options: [
          OptionSpec.value(
            'target',
            abbr: 't',
            required: true,
            repeatable: false,
          ),
        ],
        globals: false,
      );

      final outcome = router.resolve(['push', '--target', 'origin']);

      expect(outcome, isA<CliResolution>());
    });
  });
}
