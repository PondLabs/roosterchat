import Cocoa
import FlutterMacOS
import OpenGL.GL
import OpenGL.GL3
import CoreVideo

class MainFlutterWindow: NSWindow {
  private var videoRenderingChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // ROOSTER: the call controls in the Dock menu (issue #146).
    VoiceDockMenu.shared.attach(to: flutterViewController.engine.binaryMessenger)

    let videoChannel = FlutterMethodChannel(
      name: "com.pondlabs.rooster/video",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    videoChannel.setMethodCallHandler { call, result in
      guard call.method == "supportsHardwareRendering" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(MainFlutterWindow.supportsHardwareVideoRendering())
    }
    videoRenderingChannel = videoChannel

    super.awakeFromNib()
  }

  // Match media_kit_video 2.0.1's OpenGL requirements, checking its otherwise
  // forced native unwraps before constructing the renderer. Keep acceleration
  // on capable machines and use its software backend when unavailable.
  private static func supportsHardwareVideoRendering() -> Bool {
    let attributes: [CGLPixelFormatAttribute] = [
      kCGLPFAOpenGLProfile,
      CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
      kCGLPFAAccelerated,
      kCGLPFADoubleBuffer,
      kCGLPFAColorSize, _CGLPixelFormatAttribute(rawValue: 64),
      kCGLPFAColorFloat,
      kCGLPFABackingStore,
      kCGLPFAAllowOfflineRenderers,
      kCGLPFASupportsAutomaticGraphicsSwitching,
      _CGLPixelFormatAttribute(rawValue: 0),
    ]
    var pixelFormat: CGLPixelFormatObj?
    var count: GLint = 0
    let formatStatus = CGLChoosePixelFormat(attributes, &pixelFormat, &count)
    defer { if let pixelFormat = pixelFormat { CGLDestroyPixelFormat(pixelFormat) } }
    guard formatStatus == kCGLNoError, count > 0, let pixelFormat = pixelFormat else {
      return false
    }

    var context: CGLContextObj?
    let contextStatus = CGLCreateContext(pixelFormat, nil, &context)
    defer { if let context = context { CGLDestroyContext(context) } }
    guard contextStatus == kCGLNoError, let context = context else { return false }

    var textureCache: CVOpenGLTextureCache?
    let cacheStatus = CVOpenGLTextureCacheCreate(
      kCFAllocatorDefault, nil, context, pixelFormat, nil, &textureCache)
    return cacheStatus == kCVReturnSuccess && textureCache != nil
  }
}
