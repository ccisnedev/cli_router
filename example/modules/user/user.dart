import 'package:cli_router/cli_router.dart';

final limitOption = OptionSpec.value(
  'limit',
  abbr: 'l',
  required: false,
  repeatable: false,
);
final activeOption = OptionSpec.flag('active', repeatable: false);
final adminOption = OptionSpec.flag('admin', abbr: 'a', repeatable: false);

CliRouter buildUsersModule() {
  final r = CliRouter();

  r.cmd(
    'list',
    handler((req) {
      final limit = int.tryParse(req.option('limit')?.value ?? '') ?? 10;
      final activeOnly = req.option('active') != null;
      req.stdout.writeln('Users.list(limit=$limit, activeOnly=$activeOnly)');
      req.stdout.writeln('- u#1  Alice');
      req.stdout.writeln('- u#2  Bob');
    }),
    options: [limitOption, activeOption],
    globals: true,
    description: 'Lists users (options: --limit/-l N, --active)',
  );

  r.cmd(
    'show <id>',
    handler((req) {
      final id = req.param('id');
      req.stdout.writeln('Users.show(id=$id)');
    }),
    options: const [],
    globals: true,
    description: 'Shows a user by id',
  );

  r.cmd(
    'create <name>',
    handler((req) {
      final name = req.param('name');
      final admin = req.option('admin') != null;
      req.stdout.writeln('Users.create(name=$name, admin=$admin)');
    }),
    options: [adminOption],
    globals: true,
    description: 'Creates a user (option: --admin/-a, before the name)',
  );

  return r;
}
