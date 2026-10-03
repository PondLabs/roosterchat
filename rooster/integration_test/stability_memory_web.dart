import 'dart:js_interop';

@JS('performance.memory')
external JSObject? get _memory;

extension type _HeapStats(JSObject _) implements JSObject {
  external double get usedJSHeapSize;
}

int? sampleMemoryBytes() {
  final memory = _memory;
  return memory == null ? null : _HeapStats(memory).usedJSHeapSize.toInt();
}

const memoryMetric = 'chromium_js_heap_bytes';

@JS('navigator.userAgent')
external String get _userAgent;
@JS('navigator.hardwareConcurrency')
external int get _processors;
@JS('document.createElement')
external JSObject _createElement(String name);

extension type _Canvas(JSObject _) implements JSObject {
  external JSObject? getContext(String type);
}

extension type _GL(JSObject _) implements JSObject {
  external JSObject? getExtension(String name);
  external String getParameter(int parameter);
}

extension type _LoseContext(JSObject _) implements JSObject {
  external void loseContext();
}

Map<String, Object?> sampleRenderEnvironment() {
  final result = <String, Object?>{
    'user_agent': _userAgent,
    'logical_processors': _processors,
  };
  // Query a separate context after the workload; do not change Flutter's.
  try {
    final canvas = _Canvas(_createElement('canvas'));
    final context = canvas.getContext('webgl2') ?? canvas.getContext('webgl');
    if (context != null) {
      final gl = _GL(context);
      final debugInfo = gl.getExtension('WEBGL_debug_renderer_info');
      result['webgl_renderer'] =
          gl.getParameter(debugInfo == null ? 0x1F01 : 0x9246);
      final loseContext = gl.getExtension('WEBGL_lose_context');
      if (loseContext != null) _LoseContext(loseContext).loseContext();
    } else {
      result['webgl_renderer'] = 'unavailable';
    }
  } catch (error) {
    result['webgl_renderer_error'] = error.toString();
  }
  return result;
}
