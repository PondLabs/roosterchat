import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:rooster/ui/pages/loading/loading_page.dart';
import 'package:rooster/utils/updater/self_updater.dart';
import 'package:rooster/utils/updater/update_release.dart';

void main() {
  testWidgets("the loading page animates and changes its caption",
      (tester) async {
    await tester.pumpWidget(const LoadingPage());
    expect(find.text(LoadingPage.captions[0]), findsOneWidget);

    // Through a few loops of the nod, the waves and the dots.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.text(LoadingPage.captions[1]), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("an update on its way in replaces the captions", (tester) async {
    var update = ValueNotifier(const UpdateProgress(UpdateStage.checking));
    await tester.pumpWidget(LoadingPage(update: update));
    expect(find.text(LoadingPage.captions[0]), findsOneWidget);

    update.value = const UpdateProgress(UpdateStage.downloading,
        release: UpdateRelease(tag: "v9.0.0", assets: []), fraction: 0.42);
    // One frame for the new caption, then its fade over the old one.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Fetching v9.0.0… 42%"), findsOneWidget);
    expect(find.text(LoadingPage.captions[0]), findsNothing);
  });
}
