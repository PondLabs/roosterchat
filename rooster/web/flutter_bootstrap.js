{{flutter_js}}
{{flutter_build_config}}

// Flutter's own loader: it starts main.dart.js and CanvasKit at once. The
// page used to wait for the window's load event (every subresource, the
// splash animation included) before asking for main.dart.js, and CanvasKit
// only once that had run. canvasKitBaseUrl keeps CanvasKit the one in
// canvaskit/ beside the app rather than the copy on gstatic.com.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
