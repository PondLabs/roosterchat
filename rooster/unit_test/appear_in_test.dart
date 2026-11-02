// Who plays the arrival animation: someone joining a call while it is on
// screen pops in; who was there when the view opened does not.
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster/ui/atoms/appear_in.dart';

void main() {
  test('only what arrives after the first build is new, again after leaving',
      () {
    final arrivals = Arrivals();
    arrivals.update(['maya', 'theo']);
    expect(arrivals.isNew('maya'), isFalse, reason: 'there when it opened');

    arrivals.update(['maya', 'theo', 'priya']);
    expect(arrivals.isNew('priya'), isTrue);
    expect(arrivals.isNew('maya'), isFalse);

    // Built again with nobody new: Priya is not new any more.
    arrivals.update(['maya', 'theo', 'priya']);
    expect(arrivals.isNew('priya'), isFalse);

    // Theo leaves and comes back: he arrives again.
    arrivals.update(['maya', 'priya']);
    arrivals.update(['maya', 'priya', 'theo']);
    expect(arrivals.isNew('theo'), isTrue);
  });
}
