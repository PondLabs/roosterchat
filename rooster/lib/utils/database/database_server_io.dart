import 'package:rooster/utils/database/multiple_database_server.dart';

Future<void>? initDatabaseServerImpl() async {
  await DatabaseIsolate.start();
}
