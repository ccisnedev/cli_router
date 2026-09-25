import 'package:cli_router/cli_router.dart';

CliRouter buildSystemModule() {
  final r = CliRouter();

  r.cmd(
    'version',
    handler((req) {
      req.stdout.writeln('system.version = 1.0.0');
    }),
    options: const [],
    globals: true,
    description: 'Shows the version',
  );

  r.cmd(
    'ping',
    handler((req) async {
      req.stdout.writeln('pong');
    }),
    options: const [],
    globals: true,
    description: 'Ping/pong',
  );

  return r;
}
