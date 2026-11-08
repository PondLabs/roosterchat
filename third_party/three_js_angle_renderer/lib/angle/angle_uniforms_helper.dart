part of three_webgl;

final emptyTexture = Texture();
final emptyArrayTexture = DataArrayTexture();
final empty3dTexture = Data3DTexture();
final emptyCubeTexture = CubeTexture();

// --- Utilities ---

// Array Caches (provide typed arrays for temporary by size)

Map<int, Float32List> arrayCacheF32 = {};
Map arrayCacheI32 = {};

// Float32List caches used for uploading Matrix uniforms

final mat4array = Float32List(16);
final mat3array = Float32List(9);
final mat2array = Float32List(4);

// --- Uniform Classes ---

/// ROOSTER: what every node of a program's uniform tree answers to, so the
/// renderer calls a uniform's setter statically. Each node used to be
/// reached through `dynamic` (and a single uniform's setter was a
/// `Function` field), which made every one of the thousands of uniform
/// sets a frame a dynamic invocation.
abstract class AngleUniformNode {
  dynamic get id;
  void setValue(RenderingContext gl, dynamic value, [AngleTextures? textures]);
}

class SingleUniform with AngleUniformsHelper implements AngleUniformNode {
  late int type;
  late ActiveInfo activeInfo;
  late final int _setter;

  SingleUniform(id, this.activeInfo, UniformLocation addr) {
    this.id = id;
    this.addr = addr;
    type = activeInfo.type;
    _setter = singularSetterOf(activeInfo.type);
  }

  @override
  void setValue(RenderingContext gl, dynamic v, [AngleTextures? textures]) {
    switch (_setter) {
      case _v1f: setValueV1f(gl, v, textures);
      case _v2f: setValueV2f(gl, v, textures);
      case _v3f: setValueV3f(gl, v, textures);
      case _v4f: setValueV4f(gl, v, textures);
      case _m2: setValueM2(gl, v, textures);
      case _m3: setValueM3(gl, v, textures);
      case _m4: setValueM4(gl, v, textures);
      case _v1i: setValueV1i(gl, v, textures);
      case _v2i: setValueV2i(gl, v, textures);
      case _v3i: setValueV3i(gl, v, textures);
      case _v4i: setValueV4i(gl, v, textures);
      case _v1ui: setValueV1ui(gl, v, textures);
      case _v2ui: setValueV2ui(gl, v, textures);
      case _v3ui: setValueV3ui(gl, v, textures);
      case _v4ui: setValueV4ui(gl, v, textures);
      case _t1: setValueT1(gl, v, textures!);
      case _t3d: setValueT3D1(gl, v, textures);
      case _t6: setValueT6(gl, v, textures);
      case _t2dArray: setValueT2DArray1(gl, v, textures!);
    }
  }
}

class PureArrayUniform with AngleUniformsHelper implements AngleUniformNode {
  late int type;
  late ActiveInfo activeInfo;
  late final int _setter;

  PureArrayUniform(id, this.activeInfo, addr) {
    this.id = id;
    this.addr = addr;
    size = activeInfo.size;
    type = activeInfo.type;
    _setter = pureArraySetterOf(activeInfo.type);
  }

  void updateCache(data) {
    final cache = this.cache;
    copyArray(cache, data);
  }

  @override
  void setValue(RenderingContext gl, dynamic v, [AngleTextures? textures]) {
    switch (_setter) {
      case _v1f: setValueV1fArray(gl, v, textures);
      case _v2f: setValueV2fArray(gl, v, textures);
      case _v3f: setValueV3fArray(gl, v, textures);
      case _v4f: setValueV4fArray(gl, v, textures);
      case _m2: setValueM2Array(gl, v, textures);
      case _m3: setValueM3Array(gl, v, textures);
      case _m4: setValueM4Array(gl, v, textures);
      case _v1i: setValueV1iArray(gl, v, textures);
      case _v2i: setValueV2iArray(gl, v, textures);
      case _v3i: setValueV3iArray(gl, v, textures);
      case _v4i: setValueV4iArray(gl, v, textures);
      case _v1ui: setValueV1uiArray(gl, v, textures);
      case _v2ui: setValueV2uiArray(gl, v, textures);
      case _v3ui: setValueV3uiArray(gl, v, textures);
      case _v4ui: setValueV4uiArray(gl, v, textures);
      case _t1: setValueT1Array(gl, v, textures);
      case _t3d: setValueT3DArray(gl, v, textures);
      case _t6: setValueT6Array(gl, v, textures);
      case _t2dArray: setValueT2DArrayArray(gl, v, textures);
    }
  }
}

mixin AngleUniform {
  late List<AngleUniformNode> seq;
  late Map<dynamic, AngleUniformNode> map;
}

class StructuredUniform with AngleUniformsHelper, AngleUniform
    implements AngleUniformNode {
  StructuredUniform(id) {
    this.id = id;
    seq = [];
    map = {};
  }

  @override
  void setValue(RenderingContext gl, dynamic value, [AngleTextures? textures]) {
    final seq = this.seq;

    for (int i = 0, n = seq.length; i != n; ++i) {
      final u = seq[i];
      u.setValue(gl, value[u.id], textures);
    }
  }
}

/// ROOSTER: a uniform's last uploaded value, element by element: what the
/// `Map<int, dynamic>` it replaces held (a missing element reads null), in
/// a list, with no hashing on the hot path. Elements are always written
/// from 0 up, so the list has no holes.
class UniformCache {
  final List<dynamic> _values = [];

  int get length => _values.length;

  dynamic operator [](int i) => i < _values.length ? _values[i] : null;

  void operator []=(int i, dynamic value) {
    final values = _values;
    if (i < values.length) {
      values[i] = value;
      return;
    }
    while (values.length < i) {
      values.add(null);
    }
    values.add(value);
  }

  void clear() => _values.clear();
}

// Setter kinds (ROOSTER: a switch on these replaces the setters' tear-offs).
const _v1f = 0, _v2f = 1, _v3f = 2, _v4f = 3;
const _m2 = 4, _m3 = 5, _m4 = 6;
const _v1i = 7, _v2i = 8, _v3i = 9, _v4i = 10;
const _v1ui = 11, _v2ui = 12, _v3ui = 13, _v4ui = 14;
const _t1 = 15, _t3d = 16, _t6 = 17, _t2dArray = 18;

/// The setter kind for a uniform of GL [type], or -1 when there is none.
int _setterKind(int type) {
  switch (type) {
    case 0x1406: return _v1f; // FLOAT
    case 0x8b50: return _v2f; // _VEC2
    case 0x8b51: return _v3f; // _VEC3
    case 0x8b52: return _v4f; // _VEC4

    case 0x8b5a: return _m2; // _MAT2
    case 0x8b5b: return _m3; // _MAT3
    case 0x8b5c: return _m4; // _MAT4

    case 0x1404: case 0x8b56: return _v1i; // INT, BOOL
    case 0x8b53: case 0x8b57: return _v2i; // _VEC2
    case 0x8b54: case 0x8b58: return _v3i; // _VEC3
    case 0x8b55: case 0x8b59: return _v4i; // _VEC4

    case 0x1405: return _v1ui; // UINT
    case 0x8dc6: return _v2ui; // _VEC2
    case 0x8dc7: return _v3ui; // _VEC3
    case 0x8dc8: return _v4ui; // _VEC4

    case 0x8b5e: // SAMPLER_2D
    case 0x8d66: // SAMPLER_EXTERNAL_OES
    case 0x8dca: // INT_SAMPLER_2D
    case 0x8dd2: // UNSIGNED_INT_SAMPLER_2D
    case 0x8b62: // SAMPLER_2D_SHADOW
      return _t1;

    case 0x8b5f: // SAMPLER_3D
    case 0x8dcb: // INT_SAMPLER_3D
    case 0x8dd3: // UNSIGNED_INT_SAMPLER_3D
      return _t3d;

    case 0x8b60: // SAMPLER_CUBE
    case 0x8dcc: // INT_SAMPLER_CUBE
    case 0x8dd4: // UNSIGNED_INT_SAMPLER_CUBE
    case 0x8dc5: // SAMPLER_CUBE_SHADOW
      return _t6;

    case 0x8dc1: // SAMPLER_2D_ARRAY
    case 0x8dcf: // INT_SAMPLER_2D_ARRAY
    case 0x8dd7: // UNSIGNED_INT_SAMPLER_2D_ARRAY
    case 0x8dc4: // SAMPLER_2D_ARRAY_SHADOW
      return _t2dArray;
    default:
      return -1;
  }
}

// --- Top-level ---

// Parser - builds up the property tree from the path strings

final rePathPart = RegExp(r"(\w+)(\])?(\[|\.)?"); //g;

// extracts
// 	- the identifier (member name or array index)
//  - followed by an optional right bracket (found when array index)
//  - followed by an optional left bracket or dot (type of subscript)
//
// Note: These portions can be read in a non-overlapping fashion and
// allow straightforward parsing of the hierarchy that WebGL encodes
// in the uniform names.

void addUniform(AngleUniform container, AngleUniformNode uniformObject) {
  container.seq.add(uniformObject);
  container.map[uniformObject.id] = uniformObject;
}

void parseUniform(ActiveInfo activeInfo, UniformLocation addr, AngleUniform container) {
  final path = activeInfo.name;
  final pathLength = path.length;

  //console.info("WebGLUniformsHelper.parseUniform path: $path addr: ${addr.id} ");

  // reset RegExp object, because of the early exit of a previous run
  // RePathPart.lastIndex = 0;

  final matches = rePathPart.allMatches(path);

  for (final match in matches) {
    dynamic id = match.group(1);
    final idIsIndex = match.group(2) == ']';
    final subscript = match.group(3);

    if (idIsIndex) id = int.tryParse(id) ?? 0; // convert to integer

    final matchEnd = match.end;

    if (subscript == null || subscript == '[' && matchEnd + 2 == pathLength) {
      // bare name or "pure" bottom-level array "[0]" suffix
      addUniform(container, subscript == null ? SingleUniform(id, activeInfo, addr) : PureArrayUniform(id, activeInfo, addr));
      break;
    } 
    else {
      // step into inner node / create it in case it doesn't exist

      final map = container.map;
      StructuredUniform? next = map[id] as StructuredUniform?;

      if (next == null) {
        next = StructuredUniform(id);
        addUniform(container, next);
      }

      container = next;
    }
  }
}

mixin AngleUniformsHelper {
  // Flattening for arrays of vectors and matrices
  // id string || int
  late dynamic id;
  // ROOSTER: a list, not a Map<int, dynamic> (see UniformCache).
  final UniformCache cache = UniformCache();

  // ROOSTER: a matrix uniform's last value, compared and copied as floats
  // (as a Map of boxed doubles, each matrix set hashed 16 keys to compare
  // and, when the matrix had changed, cleared and refilled the map).
  Float32List? _matrix;
  UniformLocation addr = UniformLocation(0);
  late int size;

  void dispose(){
    cache.clear();
    _matrix = null;
  }

  Float32List flat = Float32List(0);

  Float32List flatten(List? array, int nBlocks, int blockSize) {
    if(array == null || array.isEmpty) return Float32List(0);
    final firstElem = array[0];

    if (firstElem is num || firstElem is double || firstElem is int) {
      List<double> array2 = [];

      for (final element in array) {
        array2.add(element.toDouble());
      }

      return Float32List.fromList(array2);
    }

    final n = nBlocks * blockSize;
    Float32List? r = arrayCacheF32[n];

    if (r == null) {
      r = Float32List(n);
      arrayCacheF32[n] = r;
    }

    if (nBlocks != 0) {
      for (int i = 0; i < nBlocks; i++) {
        List<num> data = array[i].storage.toList();

        data.asMap().forEach((index, element) {
          int idx = i * blockSize + index;
          r![idx] = element.toDouble();
        });
      }
    }
    return r;
  }

  bool arraysEqual(UniformCache a, b) {
    if (a.length != b.length) return false;

    for (int i = 0, l = a.length; i < l; i++) {
      if (a[i] != b[i]) return false;
    }

    return true;
  }

  void copyArray(UniformCache a, b) {
    final l = b.length;
    a.clear();
    for (int i = 0; i < l; i++) {
      a[i] = b[i];
    }
  }

  // Texture unit allocation

  Int32List allocTexUnits(textures, n) {
    Int32List? r = arrayCacheI32[n];

    if (r == null) {
      r = Int32List(n);
      arrayCacheI32[n] = r;
    }

    for (int i = 0; i != n; ++i) {
      r[i] = textures.allocateTextureUnit();
    }

    return r;
  }

  // --- Setters ---

  // Note: Defining these methods externally, because they come in a bunch
  // and this way their names minify.

  // Single scalar

  void setValueV1f(RenderingContext gl, v, [AngleTextures? textures]) {
    final cache = this.cache;

    if (cache[0] == v) return;
    gl.uniform1f(addr, v.toDouble());

    cache[0] = v;
  }

  // Single float vector (from flat array or three.VectorN)

  void setValueV2f(RenderingContext gl, v, [AngleTextures? textures]) {
    final cache = this.cache;

    if (v.x != null) {
      if (cache[0] != v.x || cache[1] != v.y) {
        gl.uniform2f(addr, v.x, v.y);

        cache[0] = v.x;
        cache[1] = v.y;
      }
    } else {
      if (arraysEqual(cache, v)) return;

      gl.uniform2fv(addr, v);

      copyArray(cache, v);
    }
  }

  void setValueV3f(RenderingContext gl, v, [AngleTextures? textures]) {
    final cache = this.cache;

    if (v is Vector3) {
      if (cache[0] != v.x || cache[1] != v.y || cache[2] != v.z) {
        gl.uniform3f(addr, v.x, v.y, v.z);

        cache[0] = v.x;
        cache[1] = v.y;
        cache[2] = v.z;
      }
    } else if (v is Color) {
      double cacheR = 0;
      double cacheG = 0;
      double cacheB = 0;

      if (cache.length >= 3) {
        cacheR = cache[0];
        cacheG = cache[1];
        cacheB = cache[2];
      }

      if (cacheR != v.red || cacheG != v.green || cacheB != v.blue) {
        gl.uniform3f(addr, v.red, v.green, v.blue);

        cache[0] = v.red;
        cache[1] = v.green;
        cache[2] = v.blue;
      }
    } else {
      if (arraysEqual(cache, v)) return;
      gl.uniform3fv(addr, Float32List.fromList(v));

      copyArray(cache, v);
    }
  }

  void setValueV4f(RenderingContext gl, v, [AngleTextures? textures]) {
    final cache = this.cache;

    if (v is Vector4) {
      if (cache[0] != v.x || cache[1] != v.y || cache[2] != v.z || cache[3] != v.w) {
        gl.uniform4f(addr, v.x, v.y, v.z, v.w);

        cache[0] = v.x;
        cache[1] = v.y;
        cache[2] = v.z;
        cache[3] = v.w;
      }
    } else if (v is Color) {
      if (cache[0] != v.red || cache[1] != v.green || cache[2] != v.blue || cache[3] != 1.0) {
        gl.uniform4f(addr, v.red, v.green, v.blue, 1.0);

        cache[0] = v.red.toDouble();
        cache[1] = v.green.toDouble();
        cache[2] = v.blue.toDouble();
        cache[3] = 1.0;
      }
    } else if (v is List) {
      if (cache[0] != v[0] || cache[1] != v[1] || cache[2] != v[2] || cache[3] != v[3]) {
        gl.uniform4f(addr, v[0], v[1], v[2], v[3]);

        cache[0] = v[0];
        cache[1] = v[1];
        cache[2] = v[2];
        cache[3] = v[3];
      }
    } else {
      if (arraysEqual(cache, v)) return;

      gl.uniform4fv(addr, v);

      copyArray(cache, v);
    }
  }

  // Single matrix (from flat array or three.MatrixN)

  void setValueM2(RenderingContext gl, v, [AngleTextures? textures]) {
    final cache = this.cache;
    final elements = v?.storage;

    if (elements == null) {
      if (arraysEqual(cache, v)) return;

      gl.uniformMatrix2fv(addr, false, v);

      copyArray(cache, v);
    } else {
      if (arraysEqual(cache, elements)) return;

      //mat2array.set(List<double>.from(elements.map((e) => e.toDouble())), 0);

      gl.uniformMatrix2fv(addr, false, mat2array);
      copyArray(cache, elements);
    }
  }

  void setValueM3(RenderingContext gl, Matrix3? v, [AngleTextures? textures]) {
    final elements = v?.storage;
    if (elements == null) return;
    if (_matrixChanged(elements)) gl.uniformMatrix3fv(addr, false, elements);
  }

  void setValueM4(RenderingContext gl, Matrix4 v, [AngleTextures? textures]) {
    final elements = v.storage;
    if (_matrixChanged(elements)) gl.uniformMatrix4fv(addr, false, elements);
  }

  /// ROOSTER: whether [elements] differ from the matrix uploaded last
  /// (which they then become).
  bool _matrixChanged(Float32List elements) {
    final n = elements.length;
    var last = _matrix;
    if (last == null || last.length != n) {
      _matrix = Float32List.fromList(elements);
      return true;
    }
    var i = 0;
    while (i < n && last[i] == elements[i]) {
      i++;
    }
    if (i == n) return false;
    last.setRange(i, n, elements, i);
    return true;
  }

  // Single texture (2D / Cube)

  void setValueT1(RenderingContext gl, Texture? v, AngleTextures textures) {
    final cache = this.cache;
    final unit = textures.allocateTextureUnit();

    if (cache[0] != unit) {
      gl.uniform1i(addr, unit);
      cache[0] = unit;
    }

    textures.setTexture2D(v ?? emptyTexture, unit);
  }

  void setValueT2DArray1(RenderingContext gl,Texture? v, AngleTextures textures) {
    final cache = this.cache;
    final unit = textures.allocateTextureUnit();

    if (cache[0] != unit) {
      gl.uniform1i(addr, unit);
      cache[0] = unit;
    }

    textures.setTexture2DArray(v ?? emptyArrayTexture, unit);
  }

  void setValueT3D1(RenderingContext gl,Texture? v, [AngleTextures? textures]) {
    final cache = this.cache;
    final unit = textures!.allocateTextureUnit();

    if (cache[0] != unit) {
      gl.uniform1i(addr, unit);
      cache[0] = unit;
    }

    textures.setTexture3D(v ?? empty3dTexture, unit);
  }

  void setValueT6(RenderingContext gl,Texture? v, [AngleTextures? textures]) {
    final cache = this.cache;
    final unit = textures!.allocateTextureUnit();

    if (cache[0] != unit) {
      gl.uniform1i(addr, unit);
      cache[0] = unit;
    }

    textures.setTextureCube(v ?? emptyCubeTexture, unit);
  }

  // Integer / Boolean vectors or arrays thereof (always flat arrays)

  void setValueV1i(RenderingContext gl, v, [AngleTextures? textures]) {
    final cache = this.cache;

    if (cache[0] == v) return;

    if (v is bool) {
      if (v) {
        gl.uniform1i(addr, 1);
      } else {
        gl.uniform1i(addr, 0);
      }
    } else {
      gl.uniform1i(addr, v.toInt());
    }

    cache[0] = v;
  }
  Int32List iv = Int32List(2);

  void setValueV2i(RenderingContext gl, Vector v, [AngleTextures? textures]) {
    final cache = this.cache;
    if (arraysEqual(cache, v)) return;
    iv[0] = v.x.toInt();
    iv[1] = v.y.toInt();
    gl.uniform2iv(addr, iv);
    copyArray(cache, v.copyIntoArray());
  }

  void setValueV3i(RenderingContext gl, v, [AngleTextures? textures]) {
    final cache = this.cache;
    if (arraysEqual(cache, v)) return;
    gl.uniform3iv(addr, v);
    copyArray(cache, v);
  }

  void setValueV4i(RenderingContext gl, v, [AngleTextures? textures]) {
    final cache = this.cache;

    if (arraysEqual(cache, v)) return;

    gl.uniform4iv(addr, v);

    copyArray(cache, v);
  }

  // uint

  void setValueV1ui(RenderingContext gl, v, [AngleTextures? textures]) {
    final cache = this.cache;

    if (cache[0] == v) return;
    gl.uniform1ui(addr, v);
    cache[0] = v;
  }

  void setValueV2ui(RenderingContext gl, v, [AngleTextures? textures]) {
    final cache = this.cache;

    if (arraysEqual(cache, v)) return;
    gl.uniform2uiv(addr, v);
    copyArray(cache, v);
  }

  void setValueV3ui(RenderingContext gl, v, [AngleTextures? textures]) {
    final cache = this.cache;

    if (arraysEqual(cache, v)) return;
    gl.uniform3uiv(addr, v);
    copyArray(cache, v);
  }

  void setValueV4ui(RenderingContext gl, v, [AngleTextures? textures]) {
    final cache = this.cache;

    if (arraysEqual(cache, v)) return;
    gl.uniform4uiv(addr, v);
    copyArray(cache, v);
  }

  // Helper to pick the right setter for the singular case

  int singularSetterOf(int type) {
    final kind = _setterKind(type);
    if (kind < 0) throw ("getSingularSetter id: $id type: $type");
    return kind;
  }

  // Array of scalars
  void setValueV1fArray(RenderingContext gl, v, [AngleTextures? textures]) {
    final data = flatten(v, size, 1);
    gl.uniform1fv(addr, data);
  }

  // Integer / Boolean vectors or arrays thereof (always flat arrays)
  void setValueV1iArray(RenderingContext gl, v, [AngleTextures? textures]) {
    gl.uniform1iv(addr, v);
  }

  void setValueV2iArray(RenderingContext gl, v, [AngleTextures? textures]) {
    gl.uniform2iv(addr, v);
  }

  void setValueV3iArray(RenderingContext gl, v, [AngleTextures? textures]) {
    gl.uniform3iv(addr, v);
  }

  void setValueV4iArray(RenderingContext gl, v, [AngleTextures? textures]) {
    gl.uniform4iv(addr, v);
  }

  // Array of vectors (flat or from THREE classes)

  void setValueV2fArray(RenderingContext gl, v, [AngleTextures? textures]) {
    final data = flatten(v, size, 2);
    gl.uniform2fv(addr, data);
  }

  void setValueV3fArray(RenderingContext gl, v, [AngleTextures? textures]) {
    final data = flatten(v, size, 3);
    gl.uniform3fv(addr, data);
  }

  void setValueV4fArray(RenderingContext gl, v, [AngleTextures? textures]) {
    final data = flatten(v, size, 4);
    gl.uniform4fv(addr, data);
  }

  // Array of matrices (flat or from THREE clases)

  void setValueM2Array(RenderingContext gl, v, [AngleTextures? textures]) {
    final data = flatten(v, size, 4);
    gl.uniformMatrix2fv(addr, false, data);
  }

  void setValueM3Array(RenderingContext gl, v, [AngleTextures? textures]) {
    final data = flatten(v, size, 9);
    gl.uniformMatrix3fv(addr, false, data);
  }

  void setValueM4Array(RenderingContext gl, v, [AngleTextures? textures]) {
    final data = flatten(v, size, 16);
    gl.uniformMatrix4fv(addr, false, data);
  }

  // Array of unsigned integer

  void setValueV1uiArray(RenderingContext gl, v, [AngleTextures? textures]) {
    gl.uniform1uiv(addr, v);
  }

  // Array of unsigned integer vectors (from flat array)

  void setValueV2uiArray(RenderingContext gl, v, [AngleTextures? textures]) {
    gl.uniform2uiv(addr, v);
  }

  void setValueV3uiArray(RenderingContext gl, v, [AngleTextures? textures]) {
    gl.uniform3uiv(addr, v);
  }

  void setValueV4uiArray(RenderingContext gl, v, [AngleTextures? textures]) {
    gl.uniform4uiv(addr, v);
  }

  // Array of textures (2D / 3D / Cube / 2DArray)
  void setValueT1Array(RenderingContext gl, v, [AngleTextures? textures]) {
    final n = v.length;

    final units = allocTexUnits(textures, n);

    if (!arraysEqual(cache, units)){
      gl.uniform1iv(addr, units);
      copyArray(cache, units);
    }

    for (int i = 0; i != n; ++i) {
      textures?.setTexture2D(v[i] ?? emptyTexture, units[i]);
    }
  }

  void setValueT3DArray(RenderingContext gl, v, [AngleTextures? textures]) {
    final n = v.length;

    final units = allocTexUnits(textures, n);

    gl.uniform1iv(addr, units);

    for (int i = 0; i != n; ++i) {
      textures?.setTexture3D(v[i] ?? empty3dTexture, units[i]);
    }
  }

  void setValueT6Array(RenderingContext gl, v, [AngleTextures? textures]) {
    final n = v.length;

    final units = allocTexUnits(textures, n);

    if (!arraysEqual(cache, units)){
      gl.uniform1iv(addr, units);
      copyArray(cache, units);
    }

    for (int i = 0; i != n; ++i) {
      textures?.setTextureCube(v[i] ?? emptyCubeTexture, units[i]);
    }
  }

  void setValueT2DArrayArray(RenderingContext gl, v, [AngleTextures? textures]) {
    final n = v.length;

    final units = allocTexUnits(textures, n);

    if (!arraysEqual(cache, units)){
      gl.uniform1iv(addr, units);
      copyArray(cache, units);
    }

    for (int i = 0; i != n; ++i) {
      textures?.setTexture2DArray(v[i] ?? emptyArrayTexture, units[i]);
    }
  }

  // Helper to pick the right setter for a pure (bottom-level) array (the
  // upstream picker returned null for an unknown type: such a uniform is
  // never set).
  int pureArraySetterOf(int type) => _setterKind(type);
}
