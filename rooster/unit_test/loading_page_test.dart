import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/ui/pages/loading/loading_page.dart';

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
}
