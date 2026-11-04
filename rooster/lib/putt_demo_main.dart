// LOCAL ONLY (not committed): a slim entry for the Sunny Side Putt demo, so
// the capture builds compile the game alone instead of the whole app.
//   flutter build web -t lib/putt_demo_main.dart --dart-define PLATFORM=web
import 'package:rooster/ui/organisms/sunny_side_putt/putt_demo.dart';

Future<void> main() => runPuttDemo();
