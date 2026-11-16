/// Straight RGBA on its way to the fallback's background encode
/// ([PackedRgba]): moved into the isolate on native, kept as it is on the
/// web, where `compute` runs the work on the same thread.
library;

export 'package:rooster/utils/image/metadata/rgba_transfer_native.dart'
    if (dart.library.js_interop) 'package:rooster/utils/image/metadata/rgba_transfer_web.dart';
