import 'package:rooster/config/browser_device.dart';
import 'package:rooster/config/platform_utils.dart';
import 'package:rooster/main.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';

class Layout {
  static WebBrowserInfo? browserInfo;
  static bool? _isWebDesktopCache;

  static bool _isWebDesktop() {
    if (_isWebDesktopCache != null) {
      return _isWebDesktopCache!;
    }

    if (browserInfo == null) {
      return true;
    }

    // A tablet or a foldable whose browser asks for the desktop site names
    // itself a computer (an iPad always does): what it is pointed at with
    // tells them apart.
    if (primaryPointerIsTouch) {
      return false;
    }

    var userAgent = browserInfo!.userAgent ?? "";
    userAgent = userAgent.toLowerCase();

    if (userAgent.contains("android")) {
      return false;
    }

    if (userAgent.contains("iphone")) {
      return false;
    }

    if (userAgent.contains("mobile")) {
      return false;
    }

    if (userAgent.contains("macintosh")) {
      return true;
    }

    if (userAgent.contains("windows")) {
      return true;
    }

    if (userAgent.contains("linux")) {
      return true;
    }

    // assume desktop otherwise
    return true;
  }

  /// Whether a window [width] wide gets the mobile layout: a narrow one,
  /// and in a browser also a wide one on a phone-sized screen. A phone on
  /// its side is some 800 by 360, still a phone, and the desktop layout's
  /// three columns were what it got. Asked of the screen
  /// ([screenShortestSide], null outside a browser), not of the window's
  /// height: that shrinks when the keyboard comes up, which must not turn
  /// an unfolded foldable's layout into the phone's mid sentence.
  static bool isPhoneSized(
      {required double width,
      required double? screenShortestSide,
      required double scale}) {
    if (width * scale < phoneWidth) return true;
    return screenShortestSide != null &&
        screenShortestSide * scale < phoneWidth;
  }

  /// Below this, in logical pixels, a window is a phone's: Android's own
  /// line between phones and tablets, which an unfolded foldable is past.
  static const double phoneWidth = 600;

  /// The layout for a window [width] wide (see [LayoutQuerySize]).
  static LayoutType forWidth(double width) {
    if (preferences.layoutOverride.value == "mobile") {
      return LayoutType.mobile;
    }

    if (preferences.layoutOverride.value == "desktop") {
      return LayoutType.desktop;
    }

    if (PlatformUtils.isWeb && _isWebDesktop()) {
      return LayoutType.desktop;
    }

    if (PlatformUtils.isAndroid || PlatformUtils.isWeb) {
      if (isPhoneSized(
          width: width,
          screenShortestSide: screenShortestSide,
          scale: preferences.appScale.value)) {
        return LayoutType.mobile;
      }
    }

    return LayoutType.desktop;
  }

  /// Whether the app runs in the browser of a phone, a tablet or a foldable.
  static bool get isMobileBrowser => PlatformUtils.isWeb && !_isWebDesktop();

  /// Whether this device is used with fingers rather than a mouse: the
  /// Android or iOS app, or the browser of a phone, a tablet or a foldable.
  /// Nothing hovers there, whatever the layout: an unfolded foldable is wide
  /// enough for the desktop one, and what that reveals on hover (the call's
  /// buttons, a stream's volume) could not be reached on it at all.
  static bool get isTouchDevice =>
      PlatformUtils.isAndroid || PlatformUtils.isIOS || isMobileBrowser;
}

enum LayoutType {
  mobile,
  desktop;
}

/// The layout for a window of this size: what the widgets ask through
/// MediaQuery.sizeOf. The layout only depends on the width, and
/// MediaQuery.of made every widget that asked rebuild whenever anything
/// in the media query changed: every frame of the keyboard animating
/// in or out on a phone, every frame of a window resize on the desktop.
extension LayoutQuerySize on Size {
  LayoutType get layout => Layout.forWidth(width);

  bool get mobile => layout == LayoutType.mobile;

  bool get desktop => layout == LayoutType.desktop;

  /// See [LayoutQueryData.touchControls].
  bool get touchControls => mobile || Layout.isTouchDevice;
}

extension LayoutQueryData on MediaQueryData {
  LayoutType get layout => size.layout;

  bool get mobile {
    return layout == LayoutType.mobile;
  }

  /// Whether what a mouse reveals by hovering has to be there already: in
  /// the mobile layout, and on any device used with fingers, whichever
  /// layout it got (see [Layout.isTouchDevice]).
  bool get touchControls {
    return mobile || Layout.isTouchDevice;
  }

  bool get desktop {
    return layout == LayoutType.desktop;
  }
}
