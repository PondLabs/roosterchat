#ifndef FL_ANGLE_TEXTURE_H
#define FL_ANGLE_TEXTURE_H

#include  "opengl_renderer.h"
#include "flutter_angle/flutter_angle_plugin.h"

#include <gtk/gtk.h>
#include <glib-object.h>
#include <flutter_linux/flutter_linux.h>

#include <GLES3/gl3.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <iostream>
#include <memory>
#include <mutex>

G_DECLARE_FINAL_TYPE(
  FlAngleTextureGL,
  fl_angle_texture_gl,
  FL,
  ANGLE_TEXTURE_GL,
  FlTextureGL
)

struct _FlAngleTextureGL{
  FlTextureGL parent_instance;
  uint32_t target;
  uint32_t name;
  uint32_t width;
  uint32_t height;
  // ROOSTER: the game's texture as an EGLImage, and the texture Flutter's
  // own context sees it through (made on the first populate, which runs on
  // the raster thread with Flutter's context current).
  EGLImageKHR image;
  uint32_t flutter_name;
};

// ROOSTER: the EGL context GTK's paint of the view found current, given
// back after it (see flutter_angle_plugin.cc).
struct DrawSavedContext {
  EGLDisplay display = EGL_NO_DISPLAY;
  EGLContext context = EGL_NO_CONTEXT;
  EGLSurface draw = EGL_NO_SURFACE;
  EGLSurface read = EGL_NO_SURFACE;
};

#define FLUTTER_ANGLE_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_angle_plugin_get_type(), \
                              FlutterAnglePlugin))

struct _FlutterAnglePlugin{
  GObject parent_instance;

  FlTextureRegistrar *textureRegistrar = nullptr;
  FlView *fl_view = nullptr;

  EGLDisplay eglDisplay = EGL_NO_DISPLAY;
  EGLContext eglContext = nullptr;
  EGLConfig config;
  Map *map = nullptr;
  DrawSavedContext saved;
};

// ROOSTER: `image` may be EGL_NO_IMAGE_KHR; Flutter then gets `name` as is
// (it only shows if Flutter's context happens to share with ours).
FlAngleTextureGL *fl_angle_texture_gl_new(
  uint32_t target,
  uint32_t name,
  uint32_t width,
  uint32_t height,
  EGLImageKHR image
);

#endif // FL_ANGLE_TEXTURE_H
