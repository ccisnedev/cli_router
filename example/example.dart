import 'dart:io';
import 'package:cli_router/cli_router.dart';

import 'middlewares/logging.dart';
import 'modules/order/order.dart';
import 'modules/system/system.dart';
import 'modules/user/user.dart';

final helpOption = OptionSpec.flag('help', abbr: 'h', repeatable: false);

/// Maps a rejection to a message and an exit code. Deciding this mapping is
/// an application (or SDK) concern; cli_router itself never picks an exit
/// code.
Future<int> onReject(CliRejection rejection) async {
  stderr.writeln('error: ${rejection.message ?? rejection.kind}');
  return 64; // EX_USAGE
}

/// Entrypoint:
///   dart run example/example.dart command [args...]
/// Examples (options always precede the operand, POSIX style):
///   dart run example/example.dart user list --limit 5
///   dart run example/example.dart user show 42
///   dart run example/example.dart order process --dry-run --threads 4 900
///   dart run example/example.dart system version
Future<void> main(List<String> args) async {
  final root = CliRouter(globalOptions: [helpOption]);

  // Logging middleware.
  root.use(loggingMiddleware);

  // ---- Modules (each contributes its own subrouter) ----
  root.mount('user', buildUsersModule());
  root.mount('order', buildOrdersModule());
  root.mount('system', buildSystemModule());

  // Root help command (distinct from the global --help flag).
  root.cmd(
    'help',
    handler((req) {
      req.stdout.writeln('Example CLI with modular architecture\n');
      req.stdout.writeln('Available commands:');
      for (final c in root.listCommands()) {
        final desc = c.description == null ? '' : '  - ${c.description}';
        req.stdout.writeln('  ${c.command}$desc');
      }
    }),
    options: const [],
    globals: false,
    description: 'Shows general help',
  );

  final code = await root.run(args, onReject: onReject);
  exit(code);
}
