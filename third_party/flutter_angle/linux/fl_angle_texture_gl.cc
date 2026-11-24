#include "include/fl_angle_texture_gl.h"

// https://github.com/lattice0/external_texture_flutter_linux/tree/master/external_texture/linux

#include <iostream>
#include <vector>
G_DEFINE_TYPE(
  FlAngleTextureGL,
  fl_angle_texture_gl,
  fl_texture_gl_get_type()
)

// ROOSTER: Flutter-side textures of textures already let go. They belong to
// Flutter's context, which is only current on the raster thread, and a
// texture is let go on the platform thread: the next populate deletes them.
// ponytail: one game's texture stays until the next game opens.
static std::mutex released_mutex;
static std::vector<GLuint> released_names;

typedef void (*ImageTargetTexture2D)(GLenum target, void *image);

static gboolean fl_angle_texture_gl_populate(
  FlTextureGL *texture,
  uint32_t *target,
  uint32_t *name,
  uint32_t *width,
  uint32_t *height,
  GError **error
){
  FlAngleTextureGL* f = (FlAngleTextureGL*) texture;
  {
    std::lock_guard<std::mutex> lock(released_mutex);
    if (!released_names.empty()) {
      glDeleteTextures(released_names.size(), released_names.data());
      released_names.clear();
    }
  }
  // ROOSTER: the game draws in a context Flutter's does not share with
  // (Flutter's is current only here, on the raster thread, so nothing can
  // share with it when the game starts), so Flutter sees the game's texture
  // through an EGLImage of it, bound to a texture of Flutter's own.
  if (f->flutter_name == 0 && f->image != EGL_NO_IMAGE_KHR) {
    static auto image_target = reinterpret_cast<ImageTargetTexture2D>(
      eglGetProcAddress("glEGLImageTargetTexture2DOES"));
    if (image_target != nullptr) {
      GLint previous = 0;
      glGetIntegerv(GL_TEXTURE_BINDING_2D, &previous);
      GLuint flutter_name = 0;
      glGenTextures(1, &flutter_name);
      glBindTexture(GL_TEXTURE_2D, flutter_name);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
      // Errors Skia left behind are not ours (bounded: a lost context
      // reports one forever).
      for (int i = 0; i < 16 && glGetError() != GL_NO_ERROR; i++) {}
      image_target(GL_TEXTURE_2D, f->image);
      glBindTexture(GL_TEXTURE_2D, previous);
      if (glGetError() == GL_NO_ERROR) {
        f->flutter_name = flutter_name;
      } else {
        std::cerr << "[AnglePlugin] Flutter's context could not bind the game's EGLImage" << std::endl;
        glDeleteTextures(1, &flutter_name);
        f->image = EGL_NO_IMAGE_KHR;
      }
    } else {
      f->image = EGL_NO_IMAGE_KHR;
    }
  }
  *target = f->target;
  *name = f->flutter_name != 0 ? f->flutter_name : f->name;
  *width = f->width;
  *height = f->height;
  return true;
}

FlAngleTextureGL *fl_angle_texture_gl_new(
  uint32_t target,
  uint32_t name,
  uint32_t width,
  uint32_t height,
  EGLImageKHR image
){
  auto r = FL_ANGLE_TEXTURE_GL(g_object_new(fl_angle_texture_gl_get_type(), nullptr));
  r->target = target;
  r->name = name;
  r->width = width;
  r->height = height;
  r->image = image;
  r->flutter_name = 0;
  return r;
}

static void fl_angle_texture_gl_finalize(GObject *object){
  FlAngleTextureGL* f = FL_ANGLE_TEXTURE_GL(object);
  if (f->flutter_name != 0) {
    std::lock_guard<std::mutex> lock(released_mutex);
    released_names.push_back(f->flutter_name);
  }
  G_OBJECT_CLASS(fl_angle_texture_gl_parent_class)->finalize(object);
}

static void fl_angle_texture_gl_class_init(FlAngleTextureGLClass *klass){
  FL_TEXTURE_GL_CLASS(klass)->populate = fl_angle_texture_gl_populate;
  G_OBJECT_CLASS(klass)->finalize = fl_angle_texture_gl_finalize;
}

static void fl_angle_texture_gl_init(FlAngleTextureGL *self){}
