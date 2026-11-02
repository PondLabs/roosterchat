// What the browser says about the device it runs on, for choosing a layout.
import 'browser_device_native.dart'
    if (dart.library.js_interop) 'browser_device_web.dart' as impl;

/// Whether the browser says its main pointer is a finger that cannot hover:
/// a phone, a tablet or a foldable, also one whose browser asks for the
/// desktop site and so names itself a computer. False for a laptop with a
/// touchscreen, whose main pointer is its trackpad, and outside a browser.
bool get primaryPointerIsTouch => impl.primaryPointerIsTouch;

/// The shorter side of the screen the browser is on, in logical pixels; null
/// outside a browser. Unlike the page's own size it stays put when the
/// keyboard comes up or the address bar hides, and it is the screen in use:
/// a foldable's cover screen while folded, its inner one once opened.
double? get screenShortestSide => impl.screenShortestSide;
