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
