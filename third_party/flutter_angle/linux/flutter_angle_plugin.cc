#include "include/flutter_angle/flutter_angle_plugin.h"
#include "include/fl_angle_texture_gl.h"
#include "flutter_angle_plugin_private.h"
#include  "include/opengl_renderer.h"
#include "include/current_context.h"

#include <flutter_linux/flutter_linux.h>
#include <flutter_linux/fl_view.h>
#include <sys/utsname.h>
#include <glib.h>

#include <map>
#include <memory>
#include <sstream>
#include <thread>
#include <iostream>
#include <cstring>

#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <gdk/gdk.h>
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

G_DEFINE_TYPE(FlutterAnglePlugin, flutter_angle_plugin, g_object_get_type())

// ROOSTER: the EGLDisplay Flutter renders with (fl_opengl_manager.cc asks
// for the GDK display's platform display the same way, and EGL hands back
// the same display for the same arguments), so an EGLImage made here can be
// bound in Flutter's context.
static EGLDisplay flutter_egl_display() {
  GdkDisplay *display = gdk_display_get_default();
  auto get_platform_display = reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(
    eglGetProcAddress("eglGetPlatformDisplayEXT"));
  if (display != nullptr && get_platform_display != nullptr) {
#ifdef GDK_WINDOWING_WAYLAND
    if (GDK_IS_WAYLAND_DISPLAY(display)) {
      return get_platform_display(EGL_PLATFORM_WAYLAND_EXT, gdk_wayland_display_get_wl_display(display), nullptr);
    }
#endif
#ifdef GDK_WINDOWING_X11
    if (GDK_IS_X11_DISPLAY(display)) {
      return get_platform_display(EGL_PLATFORM_X11_EXT, gdk_x11_display_get_xdisplay(display), nullptr);
    }
#endif
  }
  return eglGetDisplay(EGL_DEFAULT_DISPLAY);
}

// ROOSTER: the Dart side borrows GTK's thread for its context around
// every stretch of GL it does (see include/current_context.h), through these
// two, looked up over FFI.
static flutter_angle::SavedCurrent dart_saved;
static EGLDisplay dart_display = EGL_NO_DISPLAY;
static bool dart_held = false;

extern "C" __attribute__((visibility("default"))) int flutter_angle_acquire(void *display, void *context) {
  if (dart_held) return 1;
  if (!flutter_angle::make_current(display, context, &dart_saved)) {
    std::cerr << "[AnglePlugin] eglMakeCurrent failed: 0x" << std::hex << eglGetError() << std::dec << std::endl;
    return 0;
  }
  dart_display = display;
  dart_held = true;
  return 1;
}

extern "C" __attribute__((visibility("default"))) void flutter_angle_release() {
  if (!dart_held) return;
  dart_held = false;
  flutter_angle::restore_current(dart_display, dart_saved);
}

// Called when a method call is received from Flutter.
static void flutter_angle_plugin_handle_method_call(FlutterAnglePlugin *self, FlMethodCall *method_call){
  g_autoptr(FlMethodResponse) response = nullptr;

	const gchar *method = fl_method_call_get_name(method_call);
	FlValue *args = fl_method_call_get_args(method_call);

	if (strcmp(method, "getPlatformVersion") == 0) {
		response = get_platform_version();
	} 
  else if (strcmp(method, "initOpenGL") == 0){
    // ROOSTER: the context lives on Flutter's own EGL display and shares
    // with nothing; Flutter sees its textures through EGLImages (see
    // fl_angle_texture_gl.cc). The upstream code shared with whatever EGL
    // context was current on this thread, but Flutter 3.41's is current
    // only on the raster thread: here there was none (an unshared context
    // on another display, whose texture Flutter could not see) or some
    // other plugin's. One context serves every start.
    if (self->eglContext == nullptr || self->eglContext == EGL_NO_CONTEXT) {
      self->eglDisplay = flutter_egl_display();
      if (self->eglDisplay == EGL_NO_DISPLAY || !eglInitialize(self->eglDisplay, nullptr, nullptr)) {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new("EGL InitError", "No EGL display.", nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }

      const EGLint attribute_list[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_STENCIL_SIZE, 8,
        EGL_NONE
      };
      EGLint num_config = 0;
      if (!eglChooseConfig(self->eglDisplay, attribute_list, &self->config, 1, &num_config) || num_config < 1) {
        const EGLint fallback_list[] = {
          EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
          EGL_DEPTH_SIZE, 16,
          EGL_NONE
        };
        eglChooseConfig(self->eglDisplay, fallback_list, &self->config, 1, &num_config);
      }
      if (num_config < 1) {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new("EGL InitError", "No OpenGL ES 3 config.", nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }

      eglBindAPI(EGL_OPENGL_ES_API);
      const EGLint contextAttributes[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
      };
      self->eglContext = eglCreateContext(self->eglDisplay, self->config, EGL_NO_CONTEXT, contextAttributes);
      if (self->eglContext == EGL_NO_CONTEXT) {
        g_autofree gchar *message = g_strdup_printf("eglCreateContext failed: 0x%x", eglGetError());
        response = FL_METHOD_RESPONSE(fl_method_error_response_new("EGL InitError", message, nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
    }

    EGLint actualConfigId = 0;
    eglGetConfigAttrib(self->eglDisplay, self->config, EGL_CONFIG_ID, &actualConfigId);
    std::cerr << "[AnglePlugin] Context on Flutter's EGL display, config ID: " << actualConfigId << std::endl;

    g_autoptr(FlValue) value = fl_value_new_map();
    fl_value_set_string_take(value, "context", fl_value_new_int((int64_t)self->eglContext));
    fl_value_set_string_take(value, "display", fl_value_new_int((int64_t)self->eglDisplay));
    fl_value_set_string_take(value, "eglConfigId", fl_value_new_int((int64_t)actualConfigId));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
    if (self->map == nullptr) self->map = new Map();
  }
	else if (strcmp(method, "createTexture") == 0){
    std::cerr << "EGL createTexture" << std::endl;
    int width = 0;
    int height = 0;
    if(args){
      width = fl_value_get_int(fl_value_lookup_string(args, "width"));
      height = fl_value_get_int(fl_value_lookup_string(args, "height"));
      if(!width || !height){
        response = FL_METHOD_RESPONSE(fl_method_error_response_new("EGL DeleteError", "Missing with or height.",nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
    }
    std::cerr << "Window Size:" << width << "," << height << std::endl;

    auto currentTexture = std::make_unique<OpenglRenderer>(
      self->textureRegistrar,
      self->eglDisplay,
      self->eglContext,
      width,
      height
    );

    auto textureId = currentTexture->textureId;
    self->map->renderers[textureId] = std::move(currentTexture);
    g_autoptr(FlValue) value = self->map->renderers.at(textureId)->createTexture();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  }
	else if (strcmp(method, "textureFrameAvailable") == 0){
    int64_t textureId = 0;
    if(args){
      textureId = fl_value_get_int(fl_value_lookup_string(args, "textureId"));
      if(!textureId){
        response = FL_METHOD_RESPONSE(fl_method_error_response_new("EGL DeleteError", "Missing textureId.",nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
    }
    
    if (self->map->renderers.find(textureId) == self->map->renderers.end()){
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("EGL DeleteError", "Invalid texture ID.",nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    self->map->renderers[textureId]->updateTexture();

    g_autoptr(FlValue) result = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
	}
	else if (strcmp(method, "resizeTexture") == 0){
    std::cerr << "EGL resizeTexture" << std::endl;
    int width = 0;
    int height = 0;
    int64_t textureId = 0;
    if(args){
      width = fl_value_get_int(fl_value_lookup_string(args, "width"));
      height = fl_value_get_int(fl_value_lookup_string(args, "height"));
      textureId = fl_value_get_int(fl_value_lookup_string(args, "textureId"));
      if(!width || !height){
        response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("EGL ResizeError", "Missing with, height, or textureID.",nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
      else if(!textureId){
        response = FL_METHOD_RESPONSE(fl_method_error_response_new("EGL ResizeError", "Missing textureId.",nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
    }
    std::cerr << "Window Size:" << width << "," << height << std::endl;

    if (self->map->renderers.find(textureId) == self->map->renderers.end()){
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("EGL DeleteError", "Invalid texture ID.",nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    self->map->renderers[textureId]->changeSize(width,height);
    
    g_autoptr(FlValue) result = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
	}
	else if (strcmp(method, "deleteTexture") == 0){
    std::cerr << "EGL deleteTexture" << std::endl;
    int64_t textureId = 0;
    if(args){
      textureId = fl_value_get_int(fl_value_lookup_string(args, "textureId"));
      if(!textureId){
        response = FL_METHOD_RESPONSE(fl_method_error_response_new("EGL DeleteError", "Missing textureId.", nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
    }

    // Check if the received ID is registered
    if (self->map->renderers.find(textureId) == self->map->renderers.end()){
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("EGL DeleteError", "Invalid texture ID.",nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    self->map->renderers[textureId]->dispose(true);
    self->map->renderers.erase(textureId);

    g_autoptr(FlValue) result = fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
	}
	else{
		response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
	}

	fl_method_call_respond(method_call, response, nullptr);
}

FlMethodResponse* get_platform_version() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar *version = g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void flutter_angle_plugin_dispose(GObject *object){
	G_OBJECT_CLASS(flutter_angle_plugin_parent_class)->dispose(object);
}

static void flutter_angle_plugin_class_init(FlutterAnglePluginClass *klass){
	G_OBJECT_CLASS(klass)->dispose = flutter_angle_plugin_dispose;
}

static void flutter_angle_plugin_init(FlutterAnglePlugin *self) {}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call, gpointer user_data){
	FlutterAnglePlugin *plugin = FLUTTER_ANGLE_PLUGIN(user_data);
	flutter_angle_plugin_handle_method_call(plugin, method_call);
}

void flutter_angle_plugin_register_with_registrar(FlPluginRegistrar *registrar){
	FlutterAnglePlugin *plugin = FLUTTER_ANGLE_PLUGIN(g_object_new(flutter_angle_plugin_get_type(), nullptr));

	FlView *fl_view = fl_plugin_registrar_get_view(registrar);
	plugin->fl_view = fl_view;
	plugin->textureRegistrar = fl_plugin_registrar_get_texture_registrar(registrar);

	g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
	g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
    fl_plugin_registrar_get_messenger(registrar),
    "flutter_angle",
    FL_METHOD_CODEC(codec)
  );

	fl_method_channel_set_method_call_handler(
		channel,
		method_call_cb,
		g_object_ref(plugin),
		g_object_unref
  );

	g_object_unref(plugin);
}
