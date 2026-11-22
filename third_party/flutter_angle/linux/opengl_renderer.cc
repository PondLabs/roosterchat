#include "include/opengl_renderer.h"
#include "include/fl_angle_texture_gl.h"
#include <flutter_linux/fl_texture_registrar.h>

#include <cstdint>

// ROOSTER: an EGLImage of a texture of `context`, for Flutter's context to
// bind (both contexts live on Flutter's EGL display, see initOpenGL).
static EGLImageKHR create_texture_image(EGLDisplay display, EGLContext context, GLuint texture) {
  static auto create_image = reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(
    eglGetProcAddress("eglCreateImageKHR"));
  if (create_image == nullptr) return EGL_NO_IMAGE_KHR;
  const EGLint attributes[] = {EGL_GL_TEXTURE_LEVEL_KHR, 0, EGL_NONE};
  EGLImageKHR image = create_image(
    display, context, EGL_GL_TEXTURE_2D_KHR,
    reinterpret_cast<EGLClientBuffer>(static_cast<uintptr_t>(texture)), attributes);
  if (image == EGL_NO_IMAGE_KHR) {
    std::cerr << "[AnglePlugin] eglCreateImageKHR failed: 0x" << std::hex << eglGetError() << std::dec << std::endl;
  }
  return image;
}

static void destroy_texture_image(EGLDisplay display, EGLImageKHR image) {
  static auto destroy_image = reinterpret_cast<PFNEGLDESTROYIMAGEKHRPROC>(
    eglGetProcAddress("eglDestroyImageKHR"));
  if (image != EGL_NO_IMAGE_KHR && destroy_image != nullptr) destroy_image(display, image);
}

OpenglRenderer::OpenglRenderer(
  FlTextureRegistrar* textureRegistrar, 
  EGLDisplay display, 
  EGLContext context,
  int width, 
  int height
){
  std::cout << "[OpenglRenderer] Creating Headless GPU Renderer..." << std::endl;
  this->textureRegistrar = textureRegistrar;
  this->eglDisplay = display;
  this->eglContext = context;
  this->texId = 0;
  this->textureId = 0;
  this->texture = nullptr;

  changeSize(width, height);
}

FlValue *OpenglRenderer::createTexture() {
  g_autoptr(FlValue) value = fl_value_new_map ();
  fl_value_set_string_take(value, "textureId", fl_value_new_int(textureId));
  fl_value_set_string_take(value, "openglTexture", fl_value_new_int((int64_t)texId));
  return fl_value_ref(value);
}

void OpenglRenderer::changeSize(int width, int height) {
  const int MAX_TEXTURE_SIZE = 8192;
  if (width <= 0 || height <= 0 || width > MAX_TEXTURE_SIZE || height > MAX_TEXTURE_SIZE) {
    return;
  }

  this->width = width;
  this->height = height;

  // 1. Unregister and dispose previous frame assets cleanly
  if (texture != nullptr) {
    fl_texture_registrar_unregister_texture(textureRegistrar, texture);
    texture = nullptr;
    textureId = 0;
  }

  GLint prevTexture2D;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prevTexture2D);

  // 💡 THREAD SAFETY FIX: Back up whatever context is currently active on this thread right now
  EGLDisplay prevDisplay = eglGetCurrentDisplay();
  EGLContext prevContext = eglGetCurrentContext();
  EGLSurface prevDraw = eglGetCurrentSurface(EGL_DRAW);
  EGLSurface prevRead = eglGetCurrentSurface(EGL_READ);

  eglMakeCurrent(eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, eglContext);

  // ROOSTER: Flutter's texture of the old image keeps its storage (an
  // EGLImage's siblings outlive it) until Flutter lets the texture go.
  destroy_texture_image(eglDisplay, image);
  image = EGL_NO_IMAGE_KHR;
  if (texId != 0) {
    glDeleteTextures(1, &texId);
    texId = 0;
  }

  glGenTextures(1, &texId);
  glBindTexture(GL_TEXTURE_2D, texId);

  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, 0);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

  image = create_texture_image(eglDisplay, eglContext, texId);
  glFlush();

  if (prevContext != EGL_NO_CONTEXT && prevDisplay != EGL_NO_DISPLAY) {
    eglMakeCurrent(prevDisplay, prevDraw, prevRead, prevContext);
  } 
  else {
    eglMakeCurrent(eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  }

  glBindTexture(GL_TEXTURE_2D, prevTexture2D);

  auto ft = fl_angle_texture_gl_new(GL_TEXTURE_2D, texId, width, height, image);
  std::cerr << "Create Texture" <<std::endl;
  texture = FL_TEXTURE(ft);
  fl_texture_registrar_register_texture(textureRegistrar, texture);
  textureId = fl_texture_get_id(texture);

  std::cerr << "[OpenglRenderer] Pure Shared GL Texture bound successfully. ID: " << texId << std::endl;
}

void OpenglRenderer::updateTexture() {
  if (texture) {
    fl_texture_registrar_mark_texture_frame_available(textureRegistrar, texture);
  }
}

void OpenglRenderer::dispose(bool release_context) {
  std::cout << "[OpenglRenderer] Releasing GPU resources..." << std::endl;
  destroy_texture_image(eglDisplay, image);
  image = EGL_NO_IMAGE_KHR;

  if (texId != 0) {
    glDeleteTextures(1, &texId);
    texId = 0;
  }

  if (release_context && texture) {
    fl_texture_registrar_unregister_texture(textureRegistrar, texture);
    textureId = 0;
    texture = nullptr;
  }
}

OpenglRenderer::~OpenglRenderer() {
  dispose(true);
}