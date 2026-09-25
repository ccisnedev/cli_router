import 'package:cli_router/cli_router.dart';

final dryRunOption = OptionSpec.flag('dry-run', repeatable: false);
final threadsOption = OptionSpec.value(
  'threads',
  required: false,
  repeatable: false,
);
final carrierOption = OptionSpec.value(
  'carrier',
  required: false,
  repeatable: false,
);

CliRouter buildOrdersModule() {
  final r = CliRouter();

  r.cmd(
    'process <orderId>',
    handler((req) {
      final id = req.param('orderId');
      final dryRun = req.option('dry-run') != null;
      final threads = int.tryParse(req.option('threads')?.value ?? '') ?? 1;
      req.stdout.writeln(
        'Orders.process(id=$id, dryRun=$dryRun, threads=$threads)',
      );
    }),
    options: [dryRunOption, threadsOption],
    globals: true,
    description:
        'Processes an order (options: --dry-run, --threads N, before the id)',
  );

  r.cmd(
    'ship <orderId>',
    handler((req) {
      final id = req.param('orderId');
      final carrier = req.option('carrier')?.value ?? 'default';
      req.stdout.writeln('Orders.ship(id=$id, carrier=$carrier)');
    }),
    options: [carrierOption],
    globals: true,
    description: 'Ships an order (option: --carrier name, before the id)',
  );

  // Nested mount: `order report daily`, `order report monthly <yyyy-mm>`.
  final report = CliRouter()
    ..cmd(
      'daily',
      handler((req) {
        req.stdout.writeln('Orders.report.daily()');
      }),
      options: const [],
      globals: true,
      description: 'Daily report',
    )
    ..cmd(
      'monthly <yyyy-mm>',
      handler((req) {
        req.stdout.writeln(
          'Orders.report.monthly(month=${req.param('yyyy-mm')})',
        );
      }),
      options: const [],
      globals: true,
      description: 'Monthly report',
    );

  r.mount('report', report);

  return r;
}
