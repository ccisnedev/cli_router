import 'package:cli_router/cli_router.dart';

/// Logging middleware for CLI Router.
CliMiddleware loggingMiddleware = (CliHandler next) {
  return (CliRequest req) async {
    final t0 = DateTime.now();
    final code = await next(req);
    final t1 = DateTime.now();
    req.stderr.writeln(
      '[${t1.toIso8601String()}] "${req.route.pattern}" -> $code in '
      '${t1.difference(t0).inMilliseconds}ms',
    );
    return code;
  };
};
