#ifndef FLUTTER_ANGLE_CURRENT_CONTEXT_H
#define FLUTTER_ANGLE_CURRENT_CONTEXT_H

// ROOSTER: borrowing GTK's thread for a GL context.
//
// Dart runs on GTK's thread (Flutter 3.41 merges the UI and platform
// threads), and so does every GL call the game makes. That thread is not
// ours: GTK 3 composites the window with GL once any GL context exists for
// it (Flutter's view makes one) and leaves its context current after each
// paint; on X11 that context is GLX, and glvnd refuses to make an EGL
// context current while a GLX one is (EGL_BAD_ACCESS), so the game's GL
// surface never started there. Flutter can also run Dart tasks in the middle
// of its paint (fl_task_runner_wait in the view's draw), with GTK's context
// current and expected to stay so.
//
// So the game's context is current only while Dart is using it: what was
// current (an EGL or a GLX context) is saved and put down, the game's
// context made current, and the saved one given back before control returns
// to GTK (see FlutterAngle in lib/desktop/angle.dart).

#include <EGL/egl.h>
#include <dlfcn.h>

namespace flutter_angle {

struct GlxApi {
  void *(*get_current_context)() = nullptr;
  void *(*get_current_display)() = nullptr;
  unsigned long (*get_current_drawable)() = nullptr;
  unsigned long (*get_current_read_drawable)() = nullptr;
  int (*make_context_current)(void *display, unsigned long draw, unsigned long read, void *context) = nullptr;
};

// GLX as GTK loaded it, if it did: a GLX context can only be current if
// its library is already in the process, so nothing is loaded here.
inline const GlxApi &glx_api() {
  static const GlxApi api = [] {
    GlxApi api;
    void *library = dlopen("libGLX.so.0", RTLD_LAZY | RTLD_NOLOAD);
    if (library == nullptr) library = dlopen("libGL.so.1", RTLD_LAZY | RTLD_NOLOAD);
    if (library == nullptr) return api;
    api.get_current_context = reinterpret_cast<void *(*)()>(dlsym(library, "glXGetCurrentContext"));
    api.get_current_display = reinterpret_cast<void *(*)()>(dlsym(library, "glXGetCurrentDisplay"));
    api.get_current_drawable = reinterpret_cast<unsigned long (*)()>(dlsym(library, "glXGetCurrentDrawable"));
    api.get_current_read_drawable = reinterpret_cast<unsigned long (*)()>(dlsym(library, "glXGetCurrentReadDrawable"));
    api.make_context_current = reinterpret_cast<int (*)(void *, unsigned long, unsigned long, void *)>(
      dlsym(library, "glXMakeContextCurrent"));
    if (!api.get_current_context || !api.get_current_display || !api.get_current_drawable ||
        !api.get_current_read_drawable || !api.make_context_current) {
      return GlxApi();
    }
    return api;
  }();
  return api;
}

// What was current on this thread before a context was borrowed.
struct SavedCurrent {
  EGLDisplay egl_display = EGL_NO_DISPLAY;
  EGLContext egl_context = EGL_NO_CONTEXT;
  EGLSurface egl_draw = EGL_NO_SURFACE;
  EGLSurface egl_read = EGL_NO_SURFACE;
  void *glx_display = nullptr;
  void *glx_context = nullptr;
  unsigned long glx_draw = 0;
  unsigned long glx_read = 0;
};

// Gives back what `make_current` saved, putting `display`'s context down.
inline void restore_current(EGLDisplay display, const SavedCurrent &saved) {
  if (saved.egl_context != EGL_NO_CONTEXT) {
    eglMakeCurrent(saved.egl_display, saved.egl_draw, saved.egl_read, saved.egl_context);
    return;
  }
  eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  if (saved.glx_context != nullptr) {
    glx_api().make_context_current(saved.glx_display, saved.glx_draw, saved.glx_read, saved.glx_context);
  }
}

// Saves what is current, puts a GLX context down, makes `context` current
// (surfaceless). On failure everything is as it was.
inline bool make_current(EGLDisplay display, EGLContext context, SavedCurrent *saved) {
  *saved = SavedCurrent();
  saved->egl_context = eglGetCurrentContext();
  if (saved->egl_context != EGL_NO_CONTEXT) {
    saved->egl_display = eglGetCurrentDisplay();
    saved->egl_draw = eglGetCurrentSurface(EGL_DRAW);
    saved->egl_read = eglGetCurrentSurface(EGL_READ);
  } else {
    const GlxApi &glx = glx_api();
    if (glx.get_current_context != nullptr && (saved->glx_context = glx.get_current_context()) != nullptr) {
      saved->glx_display = glx.get_current_display();
      saved->glx_draw = glx.get_current_drawable();
      saved->glx_read = glx.get_current_read_drawable();
      glx.make_context_current(saved->glx_display, 0, 0, nullptr);
    }
  }
  if (eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context)) return true;
  restore_current(display, *saved);
  return false;
}

}  // namespace flutter_angle

#endif  // FLUTTER_ANGLE_CURRENT_CONTEXT_H
