// The renderer's uniform setters: each skips a value equal to the last one
// it uploaded and uploads any other, the same as before their caches moved
// off `Map<int, dynamic>` and their dispatch off `dynamic` (the 3D view's
// heaviest CPU cost per frame).
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_angle/flutter_angle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js_angle_renderer/angle/index.dart';
import 'package:three_js_math/three_js_math.dart';

/// A GL context that records the uniform uploads made on it.
class _RecordingGl extends RenderingContext {
  _RecordingGl() : super.create(LibOpenGLES(DynamicLibrary.process()), 1, 1);

  final calls = <String>[];

  @override
  void uniformMatrix4fv(
    UniformLocation location,
    bool transpose,
    Float32List values,
  ) =>
      calls.add('m4 ${values.first}');

  @override
  void uniformMatrix3fv(
    UniformLocation location,
    bool transpose,
    Float32List values,
  ) =>
      calls.add('m3 ${values.first}');

  @override
  void uniform3f(UniformLocation location, double x, double y, double z) =>
      calls.add('3f $x $y $z');

  @override
  void uniform1f(UniformLocation location, double x) => calls.add('1f $x');

  @override
  void uniform1i(UniformLocation location, int x) => calls.add('1i $x');
}

SingleUniform _uniform(int type, [String name = 'u']) =>
    SingleUniform(name, ActiveInfo(type, name, 1), UniformLocation(1));

const _float = 0x1406, _vec3 = 0x8b51, _mat3 = 0x8b5b, _mat4 = 0x8b5c;
const _bool = 0x8b56;

void main() {
  test('a mat4 uploads when any element changes, and only then', () {
    final gl = _RecordingGl();
    final u = _uniform(_mat4);
    final m = Matrix4.identity();
    u.setValue(gl, m);
    u.setValue(gl, m);
    u.setValue(gl, Matrix4.identity());
    expect(gl.calls, ['m4 1.0'], reason: 'the same matrix twice, then equal');

    // The last element alone: the comparison runs to the end.
    m.storage[15] = 2;
    u.setValue(gl, m);
    u.setValue(gl, m);
    m.storage[0] = 3;
    u.setValue(gl, m);
    expect(gl.calls, ['m4 1.0', 'm4 1.0', 'm4 3.0']);

    // Its cache is a copy, not the matrix: an edit in place is seen.
    m.storage[0] = 1;
    u.setValue(gl, m);
    expect(gl.calls.last, 'm4 1.0');
    expect(gl.calls, hasLength(4));
  });

  test('a mat3 likewise', () {
    final gl = _RecordingGl();
    final u = _uniform(_mat3);
    final m = Matrix3.identity();
    u.setValue(gl, m);
    u.setValue(gl, m);
    m.storage[4] = 5;
    u.setValue(gl, m);
    expect(gl.calls, ['m3 1.0', 'm3 1.0']);
  });

  test('scalars, vectors and colours keep their per-element caches', () {
    final gl = _RecordingGl();
    final f = _uniform(_float);
    f.setValue(gl, 0.5);
    f.setValue(gl, 0.5);
    f.setValue(gl, 0.75);
    final v = _uniform(_vec3);
    v.setValue(gl, Vector3(1, 2, 3));
    v.setValue(gl, Vector3(1, 2, 3));
    v.setValue(gl, Vector3(1, 2, 4));
    final c = _uniform(_vec3, 'c');
    c.setValue(gl, Color(0.5, 0.25, 0.75));
    c.setValue(gl, Color(0.5, 0.25, 0.75));
    c.setValue(gl, Color(0.5, 0.25, 0.125));
    final b = _uniform(_bool);
    b.setValue(gl, true);
    b.setValue(gl, true);
    b.setValue(gl, false);
    expect(gl.calls, [
      '1f 0.5',
      '1f 0.75',
      '3f 1.0 2.0 3.0',
      '3f 1.0 2.0 4.0',
      '3f 0.5 0.25 0.75',
      '3f 0.5 0.25 0.125',
      '1i 1',
      '1i 0',
    ]);
  });

  test('a uniform cache reads a missing element as null, as the map did', () {
    final cache = UniformCache();
    expect(cache.length, 0);
    expect(cache[0], isNull);
    cache[0] = 1.0;
    cache[1] = 2.0;
    expect([cache.length, cache[0], cache[1], cache[2]], [2, 1.0, 2.0, null]);
    cache.clear();
    expect([cache.length, cache[0]], [0, null]);
  });

  test('a structure sets each of its members from its value', () {
    final gl = _RecordingGl();
    final light = StructuredUniform('light');
    addUniform(light, _uniform(_float, 'intensity'));
    addUniform(light, _uniform(_vec3, 'color'));
    light.setValue(gl, {'intensity': 2.0, 'color': Color(1, 1, 1)});
    light.setValue(gl, {'intensity': 2.0, 'color': Color(1, 1, 1)});
    expect(gl.calls, ['1f 2.0', '3f 1.0 1.0 1.0']);
  });
}
