import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../renderers/index.dart';
import 'package:three_js_core/others/index.dart';
import 'package:three_js_core/renderers/index.dart';
import 'package:three_js_core/three_js_core.dart' as core;
import 'package:three_js_math/three_js_math.dart';
import 'package:flutter_angle/flutter_angle.dart';

class Settings{
  Settings({
    this.useSourceTexture = false,
    this.enableShadowMap = true,
    this.autoClear = true,
    Map<String,dynamic>? renderOptions,
    this.animate = true,
    this.alpha = false,
    this.autoClearDepth = true,
    this.autoClearStencil = true,
    this.clearAlpha = 1.0,
    this.clearColor = 0x000000,
    this.localClippingEnabled = false,
    this.clippingPlanes = const [],
    this.colorSpace = ColorSpace.srgb,
    this.outputEncoding = sRGBEncoding,
    this.toneMapping = NoToneMapping,
    this.shadowMapType = PCFShadowMap,
    this.toneMappingExposure = 1.0,
    this.logarithmicDepthBuffer = false,
    this.stencil = true,
    this.xr,
    this.antialias = false,

    this.depth = true,
    this.premultipliedAlpha = true,
    this.preserveDrawingBuffer = false,
    this.powerPreference = core.PowerPreference.defaultp,
    this.failIfMajorPerformanceCaveat = false,
    this.reverseDepthBuffer = false,
    this.precision = core.Precision.highp,
    this.screenResolution,
    this.useSurfaceProducer = true
  }){
    this.renderOptions = renderOptions ?? {
      "format": RGBAFormat,
      "samples": 4
    };
  }
  
  bool premultipliedAlpha;
  bool preserveDrawingBuffer;
  PowerPreference powerPreference;
  bool reverseDepthBuffer;
  bool failIfMajorPerformanceCaveat;
  bool depth = true;
  bool useSurfaceProducer;
  Precision precision;
  bool alpha;
  bool stencil;
  bool logarithmicDepthBuffer;
  int clearColor;
  double clearAlpha;
  bool antialias;
  XRManager Function(AngleRenderer renderer, dynamic gl)? xr;
  double? screenResolution;
  
  bool animate;
  bool useSourceTexture;
  bool enableShadowMap;
  bool autoClear;
  bool autoClearDepth;
  bool autoClearStencil;
  bool localClippingEnabled;
  late Map<String,dynamic> renderOptions;
  List<Plane> clippingPlanes;
  int outputEncoding;
  ColorSpace colorSpace;
  int toneMapping;
  int shadowMapType;
  double toneMappingExposure;
}

/// ROOSTER: whether a frame must be finished on the GPU before Flutter is
/// told it is there.
///
/// Only a surface that really swaps buffers orders the draw against
/// Flutter's read of it. The shared-FBO path (Linux, and Windows without a
/// surface producer) has one buffer and no swap at all. Windows' and
/// macOS' surface producers make an EGL *pbuffer* from a client buffer
/// (`eglCreatePbufferFromClientBuffer`, with
/// `EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE` and `EGL_IOSURFACE_ANGLE`), and
/// a pbuffer is single-buffered: EGL says `eglSwapBuffers` has no effect on
/// one, so nothing orders the draw against Flutter's read there either -
/// the engine copies the shared texture on its raster thread while ANGLE
/// may still be drawing into it. Android's window surface really swaps,
/// and the source-texture path already finished.
///
/// Where this holds, the viewer does not draw into that texture: it draws
/// into a [DeferredScreen] of its own and copies the finished frame over
/// on the next tick (see [ThreeJS.render]).
bool needsFinishBeforePresent({
  required bool web,
  required bool hasSourceTexture,
  required bool hasEglSurface,
  required TargetPlatform platform,
}) {
  if (web || hasSourceTexture) return false;
  if (!hasEglSurface) return true;
  return platform == TargetPlatform.windows ||
      platform == TargetPlatform.macOS;
}

/// ROOSTER: the framebuffer the scene is drawn into where the texture
/// Flutter shows is single-buffered ([needsFinishBeforePresent]), and the
/// frame drawn into it last that Flutter has not been given yet.
///
/// Waiting for the GPU (`glFinish`) between the draw and
/// textureFrameAvailable kept Flutter from showing a frame still being
/// drawn, but it held the UI thread for the whole of the GPU's frame every
/// tick, so the CPU's next frame never overlapped the GPU's: the frame
/// rate fell wherever the two added up to more than a vsync. Here a tick
/// first copies the frame drawn on the previous tick into Flutter's
/// texture (one blit; that frame's draw ran on the GPU while the UI thread
/// was busy elsewhere, so the wait for it is short), tells Flutter, and
/// only then draws the new frame, into this framebuffer, with a flush and
/// no wait. Flutter's texture is written by that blit alone, never by a
/// draw that starts with a clear, so no tick can show a frame half drawn.
/// The price is one frame of latency.
class DeferredScreen {
  DeferredScreen(this.gl);

  final RenderingContext gl;
  Framebuffer? _framebuffer;
  Renderbuffer? _color;
  Renderbuffer? _depth;
  int width = 0;
  int height = 0;

  /// A frame was drawn here that Flutter has not been given yet.
  bool pending = false;

  /// Makes (or, at a new size, reallocates) the framebuffer; true when it
  /// was, and so holds nothing yet.
  bool ensure(int width, int height) {
    if (_framebuffer != null && width == this.width && height == this.height) {
      return false;
    }
    this.width = width;
    this.height = height;
    pending = false;
    final framebuffer = _framebuffer ??= gl.createFramebuffer();
    final color = _color ??= gl.createRenderbuffer();
    final depth = _depth ??= gl.createRenderbuffer();
    gl.bindRenderbuffer(WebGL.RENDERBUFFER, color);
    gl.renderbufferStorage(WebGL.RENDERBUFFER, WebGL.RGBA8, width, height);
    gl.bindRenderbuffer(WebGL.RENDERBUFFER, depth);
    gl.renderbufferStorage(
        WebGL.RENDERBUFFER, WebGL.DEPTH24_STENCIL8, width, height);
    gl.bindRenderbuffer(WebGL.RENDERBUFFER, null);
    gl.bindFramebuffer(WebGL.FRAMEBUFFER, framebuffer);
    gl.framebufferRenderbuffer(
        WebGL.FRAMEBUFFER, WebGL.COLOR_ATTACHMENT0, WebGL.RENDERBUFFER, color);
    gl.framebufferRenderbuffer(WebGL.FRAMEBUFFER,
        WebGL.DEPTH_STENCIL_ATTACHMENT, WebGL.RENDERBUFFER, depth);
    return true;
  }

  /// Draws go here from now on (a null bind is a no-op on native, so the
  /// renderer's "screen" is whatever was bound last).
  void bind() {
    final framebuffer = _framebuffer;
    if (framebuffer != null) gl.bindFramebuffer(WebGL.FRAMEBUFFER, framebuffer);
  }

  /// Copies the frame here into [target] (Flutter's texture: the default
  /// framebuffer of a surface, or the shared FBO) and waits for the copy:
  /// what follows tells Flutter the texture holds a whole frame.
  void copyTo(int target) {
    gl.bindFramebuffer(WebGL.READ_FRAMEBUFFER, _framebuffer);
    gl.bindFramebuffer(WebGL.DRAW_FRAMEBUFFER, Framebuffer(target));
    gl.blitFramebuffer(0, 0, width, height, 0, 0, width, height,
        WebGL.COLOR_BUFFER_BIT, WebGL.NEAREST);
    gl.finish();
    pending = false;
  }
}

/// threeJs utility class. If you want to learn how to connect cannon.js with js, please look at the examples/threejs_* instead.
class ThreeJS with WidgetsBindingObserver{
  void Function() onSetupComplete;
  ThreeJS({
    Settings? settings,
    required this.onSetupComplete, 
    required this.setup,
    this.rendererUpdate,
    this.postProcessor,
    this.windowResizeUpdate,
    Size? size,
    AngleRenderer? renderer,
    this.renderNumber = 0,
    this.loadingWidget,
    this.onStartFailed,
  }){
    this.settings = settings ?? Settings();
    _resolution = this.settings.screenResolution;
    _fixedSize = size;
  }

  int renderNumber;

  /// ROOSTER: called when the GL context could not start (ANGLE's init or
  /// its texture threw, a machine without the GL it needs); the error is
  /// passed on instead of thrown into nobody's zone. Unset, it throws.
  void Function(Object error)? onStartFailed;

  BuildContext? _context;
  Timer? _debounceTimer;

  Widget? loadingWidget;
  Size? _fixedSize;
  late final Settings settings;
  final GlobalKey<core.PeripheralsState> globalKey = GlobalKey<core.PeripheralsState>();
  core.PeripheralsState get domElement => globalKey.currentState!;

  bool visible = true;

  FlutterAngleTexture? texture;
  RenderingContext? gl;

  RenderTarget? renderTarget;
  AngleRenderer? renderer;
  final core.Clock clock = core.Clock();

  late final core.Scene scene;
  late final core.Camera camera;
  Ticker? ticker;

  double get width => screenSize!.width;
  double get height => screenSize!.height;

  Size? screenSize;
  double? _resolution;
  double get dpr => _resolution ?? 1.0;
  void setResolution(double newResolution){
    _resolution = newResolution;
  }

  WebGLTexture? sourceTexture;

  bool pause = false;
  bool _disposed = false;
  bool isVisibleOnScreen = true;
  bool _mounted = false;
  bool get mounted => _mounted;
  bool _updating = false;
  bool get updating => _updating;

  void Function()? rendererUpdate;
  void Function(Size newSize)? windowResizeUpdate;
  void Function([double? dt])? postProcessor;
  Future<void> Function(core.Scene,core.Camera,FlutterAngleTexture,[double? dt])? customRenderer;
  Future<void> Function(BuildContext) onWindowResize = (context) async{};
  FutureOr<void> Function()? setup;
  List<Function(double dt)> events = [];
  List<Function()> disposeEvents = [];

  FlutterAngle? angle = FlutterAngle();

  void addAnimationEvent(Function(double dt) event){
    events.add(event);
  }
  void toDispose(Function() event){
    disposeEvents.add(event);
  }

  @override
  void didChangeMetrics() {
    if (_disposed) return;
    _debounceTimer?.cancel(); // Clear existing timer
    _debounceTimer = Timer(Duration(milliseconds: 300+renderNumber*100), () { // Set a new timer
      if (_context != null && _context!.mounted) {
        _onWindowResize(_context!);
      }
    });
  }

  void dispose(){
    if(_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel(); // Cancel timer if active
    _debounceTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    ticker?.dispose();
    ticker = null;
    renderer?.dispose();
    renderer = null;
    renderTarget?.dispose();
    renderTarget = null;
    // ROOSTER: a start that failed (or was cut short) before its setup ran
    // has no scene nor camera to dispose: reading them threw a late-init
    // error out of the widget tree's teardown.
    if (_mounted) scene.dispose();
    for(final event in disposeEvents){
      event.call();
    }
    
    if (_mounted) camera.dispose();
    events.clear();
    disposeEvents.clear();

    //allNativeData.dispose();

    // ROOSTER: ANGLE torn down while it is starting (its init awaits the
    // plugin, then makes its context current) failed that makeCurrent with
    // EGL_BAD_ACCESS, an error nobody caught. A start under way finishes
    // first; then ANGLE goes.
    // ROOSTER: and only an ANGLE that came up is torn down (a failed init
    // leaves nothing to free, and its dispose dereferences what it never
    // made).
    final starting = _starting;
    if (starting != null) {
      final owned = angle;
      starting
          .catchError((Object _) {})
          .whenComplete(() {
            if (_angleUp) owned?.dispose([texture]);
          });
    } else if (_angleUp) {
      angle?.dispose([texture]);
    }
    loadingWidget = null;
    _fixedSize = null;
    screenSize = null;

    rendererUpdate = null;
    windowResizeUpdate = null;
    postProcessor = null;
    setup = null;
  }

  void initSize(BuildContext context){
    if (screenSize != null) {
      return;
    }
    _context = context;
    WidgetsBinding.instance.addObserver(this);
    final mqd = MediaQuery.of(context);

    screenSize = _fixedSize ?? mqd.size;
    _resolution ??= mqd.devicePixelRatio;

    Future.delayed(Duration(milliseconds: renderNumber*100), () async{
      // ROOSTER: a viewer disposed in the meantime (its page gone within a
      // tenth of a second, as in a test's teardown) never starts a context:
      // ANGLE's makeCurrent then failed with EGL_BAD_ACCESS.
      if (_disposed) return;
      final starting = _starting = _startAngle();
      try {
        await starting;
      } finally {
        if (identical(_starting, starting)) _starting = null;
      }
    });
  }

  /// ROOSTER: ANGLE's start, while it runs (dispose waits for it).
  Future<void>? _starting;

  /// ROOSTER: ANGLE's init came through (there is something to tear down).
  bool _angleUp = false;

  /// ROOSTER: the start, its failure swallowed once the viewer is gone (the
  /// page it would draw on is gone too).
  Future<void> _startAngle() async {
    try {
      await initPlatformState();
    } catch (error) {
      if (_disposed) return;
      final failed = onStartFailed;
      if (failed == null) rethrow;
      failed(error);
    }
  }
  
  Future<void> animate(Duration duration) async {
    if (!mounted || _disposed || updating || !isVisibleOnScreen || !visible) {
      return;
    }
    _updating = true;
    double dt = clock.getDelta();
    
    if(settings.animate){
      await (customRenderer?.call(scene,camera,texture!,dt) ?? render(scene,camera,texture!,dt));
      if(!pause){
        for(int i = 0; i < events.length;i++){
          events[i].call(dt);
        }
      }
    }
    _updating = false;
  }

  /// ROOSTER: where frames are drawn when Flutter's texture is
  /// single-buffered (null elsewhere, and until the first such frame).
  DeferredScreen? deferredScreen;

  Future<void> render([core.Scene? scene, core.Camera? camera, FlutterAngleTexture? texture, double? dt]) async{
    scene ??= this.scene;
    camera ??= this.camera;
    texture ??= this.texture!;

    // ROOSTER: a texture that does not swap buffers gets each frame a tick
    // late, copied whole, instead of a glFinish here (see DeferredScreen).
    if (needsFinishBeforePresent(
      web: kIsWeb,
      hasSourceTexture: sourceTexture != null,
      hasEglSurface: texture.surfaceId != null,
      platform: defaultTargetPlatform,
    )) {
      return _renderDeferred(scene, camera, texture, dt);
    }

    if(sourceTexture == null){
      angle?.activateTexture(texture);
    }
    rendererUpdate?.call(); 
    if(postProcessor == null){
      renderer!.clear();
      renderer!.setViewport(0,0,width,height);
      renderer!.render(scene, camera);
    }
    else{
      postProcessor?.call(dt);
    }
    
    if(sourceTexture != null){
      angle?.activateTexture(texture);
    }
    await angle?.updateTexture(texture,sourceTexture);
  }

  /// ROOSTER: one tick on a single-buffered texture: the last tick's frame
  /// goes to Flutter, then this tick's is drawn and left to the GPU.
  Future<void> _renderDeferred(core.Scene scene, core.Camera camera, FlutterAngleTexture texture, double? dt) async {
    final gl = this.gl;
    if (gl == null) return;
    angle?.activateTexture(texture);
    final screen = deferredScreen ??= DeferredScreen(gl);
    final options = texture.options;
    // The same pixel size the texture was made and activated with.
    final fresh = screen.ensure(
      (options.width * options.dpr).toInt(),
      (options.height * options.dpr).toInt(),
    );
    if (screen.pending) await _present(screen, texture);
    screen.bind();
    rendererUpdate?.call();
    if(postProcessor == null){
      renderer!.clear();
      renderer!.setViewport(0,0,width,height);
      renderer!.render(scene, camera);
    }
    else{
      postProcessor?.call(dt);
    }
    // The GPU starts on it now; nobody waits for it until the next tick.
    gl.flush();
    screen.pending = true;
    // A new framebuffer (the first frame, a resize) has no older frame to
    // show meanwhile: this one goes now, not an empty texture for a tick.
    if (fresh) await _present(screen, texture);
  }

  Future<void> _present(DeferredScreen screen, FlutterAngleTexture texture) async {
    // A blit obeys the scissor test; the renderer's own is put back after.
    final scissor = renderer?.getScissorTest() ?? false;
    if (scissor) renderer!.setScissorTest(false);
    screen.copyTo(texture.fboId);
    if (scissor) renderer!.setScissorTest(true);
    await angle?.updateTexture(texture);
  }
  
  void initRenderer() {
    AngleRendererParameters options = AngleRendererParameters(
      width: width,
      height: height,
      gl: gl!,
      stencil: settings.stencil,
      antialias: settings.antialias,
      alpha: settings.alpha,
      clearColor: settings.clearColor,
      clearAlpha: settings.clearAlpha,
      logarithmicDepthBuffer: settings.logarithmicDepthBuffer,
      xr: settings.xr,
      depth: settings.depth,
      premultipliedAlpha: settings.premultipliedAlpha,
      preserveDrawingBuffer: settings.preserveDrawingBuffer,
      powerPreference: settings.powerPreference,
      failIfMajorPerformanceCaveat: settings.failIfMajorPerformanceCaveat,
      reverseDepthBuffer: settings.reverseDepthBuffer,
      precision: settings.precision,
    );
    
    renderer = AngleRenderer(options);
    renderer!.setPixelRatio(_resolution!);
    renderer!.setSize(width, height, false);
    renderer!.alpha = settings.alpha;
    renderer!.shadowMap.enabled = settings.enableShadowMap;
    renderer!.shadowMap.type = settings.shadowMapType;
    renderer!.autoClear = settings.autoClear;
    renderer!.setClearColor(
      Color.fromHex32(settings.clearColor), 
      settings.clearAlpha
    );
    renderer!.autoClearDepth = settings.autoClearDepth;
    renderer!.autoClearStencil = settings.autoClearStencil;
    renderer!.outputEncoding = settings.outputEncoding;
    renderer!.outputColorSpace = settings.colorSpace.toString();
    renderer!.localClippingEnabled = settings.localClippingEnabled;
    renderer!.clippingPlanes = settings.clippingPlanes;
    renderer!.toneMapping = settings.toneMapping;
    renderer!.toneMappingExposure = settings.toneMappingExposure;

    // ROOSTER: the shadow pass binds the texture back (see the renderer's
    // restoreScreenFramebuffer), so the shadows draw before the scene.
    if (!kIsWeb && !settings.useSourceTexture) {
      renderer!.restoreScreenFramebuffer = () {
        // ROOSTER: the deferred screen when frames are drawn there (the
        // context is already current: a bind is enough).
        final screen = deferredScreen;
        if (screen != null) return screen.bind();
        final target = texture;
        if (target != null) angle?.activateTexture(target);
      };
    }

    if(settings.useSourceTexture){
      final RenderTargetOptions pars = RenderTargetOptions(settings.renderOptions);
      renderTarget = RenderTarget((width * _resolution!).toInt(), (height * _resolution!).toInt(), pars);
      renderer!.setRenderTarget(renderTarget);
      sourceTexture = renderer!.getRenderTargetGLTexture(renderTarget!);
    }
  }
  
  Future<void> _onWindowResize(BuildContext context) async{
    if (_disposed) return;
    double dt = clock.getDelta();
    final mqd = MediaQuery.maybeOf(context);
    if (mqd == null) return;
    if(_fixedSize == null && screenSize != mqd.size && texture != null){
      screenSize = mqd.size;

      if(settings.screenResolution == null){
        _resolution = mqd.devicePixelRatio;
      }

      final options = AngleOptions(
        width: width.toInt(),
        height: height.toInt(),
        dpr: _resolution!,
      );

      await angle?.resize(texture!, options);

      camera.aspect = width/height;
      camera.updateProjectionMatrix();

      windowResizeUpdate?.call(screenSize!);
      renderer!.setSize(width, height);

      if(postProcessor != null){
        postProcessor?.call(dt);
      }
      render(scene,camera,texture!,dt);
    }
  }

  Future<void> initScene() async{
    if (renderer == null) {
      initRenderer();
    }
    await setup?.call();
    _mounted = true;
    ticker = Ticker(animate);
    ticker?.start();
    onSetupComplete();
  }

  Future<void> initPlatformState() async {
    if(texture == null){
      await angle?.init();
      _angleUp = true;
      // ROOSTER: disposed while ANGLE started: make no texture for nobody.
      if (_disposed) return;
      
      texture = await angle?.createTexture(      
        AngleOptions(
          width: width.toInt(), 
          height: height.toInt(), 
          dpr: _resolution!,
          alpha: settings.alpha,
          antialias: settings.antialias,
          customRenderer: !settings.useSourceTexture,
          useSurfaceProducer: settings.useSurfaceProducer
        )
      );
      // ROOSTER: disposed while the texture was made: it goes with ANGLE
      // (dispose's deferred teardown reads it then), no scene for nobody.
      if (_disposed) return;
    }

    console.info(texture?.toMap());
    if (gl == null) {
      gl = texture!.getContext();
    }
    await initScene();
  }

  Widget build() {
    return  Builder(builder: (BuildContext context) {
      initSize(context);
      return core.Peripherals(
        key: globalKey,
        builder: (BuildContext context) {
          return Container(
            width: !visible?0:width,
            height: !visible?0:height,
            child: SizeChangedLayoutNotifier(
              child: Builder(builder: (BuildContext context) {
                if (kIsWeb) {
                  return texture != null && mounted? HtmlElementView(viewType:texture!.textureId.toString()):loadingWidget ?? Container(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    color: Theme.of(context).canvasColor,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator()
                  );
                } 
                else {
                  return texture != null && mounted?
                    Transform.scale(
                      scaleY: sourceTexture != null || Platform.isAndroid?1:-1,
                      child:Texture(textureId: texture!.textureId)
                    ):loadingWidget ?? Container(
                      width: MediaQuery.of(context).size.width,
                      height: MediaQuery.of(context).size.height,
                      color: Theme.of(context).canvasColor,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator()
                    );
                }
              })
            )
          );
        }
      );
    });
  }
}