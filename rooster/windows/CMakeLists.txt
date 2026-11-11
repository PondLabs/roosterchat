# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(rooster LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "rooster")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Visual Studio 2026 (MSVC 14.51, on GitHub's windows-2025 runners) refuses
# <experimental/coroutine> unless told to take it, and permission_handler_windows
# still includes it. Set for the whole directory, so every plugin below gets it.
add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# ROOSTER: the engine and the plugins are plain imports of the runner. They
# were delay-loaded (/DELAYLOAD) in v1.45.2 and v1.45.3, to get the loading
# square (runner/splash_window.h) up before Windows had loaded them, and on
# those builds Sunny Side Putt drew everything it textures black on Windows.
# Delay-loading only set the order that did it: the plugins, and ANGLE with
# them, were loaded after the engine and the OPENGL32.dll it imports, and the
# game's texture uploads were bound to OPENGL32 (runner/angle_names.def has
# the whole of it, and the fix, which does not depend on the order). With
# that fix a delay-loaded build draws the game right, looked at in November
# 2026: the GPU had nothing to do with it.

# ROOSTER: one ANGLE in the bundle. flutter_angle and
# media_kit_libs_windows_video each ship a libEGL.dll and a libGLESv2.dll,
# different builds of ANGLE (2.1.14811 and 2.1.18844), and both were copied
# into the same folder. The releases hold media_kit's; which of the two a
# local build was left with varied from one build to the next. media_kit's
# serves both plugins (flutter_angle's imports libEGL.dll and libGLESv2.dll by
# name), so flutter_angle's copies stay out, and its zlib.dll with them: only
# its own libGLESv2.dll wants it, and media_kit ships one of that name too.
list(FILTER PLUGIN_BUNDLED_LIBRARIES EXCLUDE REGEX
  "/flutter_angle/windows/bin/dll/(libEGL|libGLESv2|zlib)\\.dll$")

# ROOSTER: two different files of one name in the bundle are an error here,
# not something the install step settles by which it copies last.
set(_rooster_bundled_names)
set(_rooster_bundled_paths)
foreach(_rooster_lib IN LISTS PLUGIN_BUNDLED_LIBRARIES)
  if(_rooster_lib MATCHES "^\\$<")
    continue()
  endif()
  get_filename_component(_rooster_name "${_rooster_lib}" NAME)
  string(TOLOWER "${_rooster_name}" _rooster_name)
  list(FIND _rooster_bundled_names "${_rooster_name}" _rooster_at)
  if(_rooster_at EQUAL -1)
    list(APPEND _rooster_bundled_names "${_rooster_name}")
    list(APPEND _rooster_bundled_paths "${_rooster_lib}")
  else()
    list(GET _rooster_bundled_paths ${_rooster_at} _rooster_first)
    if(NOT _rooster_first STREQUAL _rooster_lib)
      message(FATAL_ERROR "Two plugins bundle ${_rooster_name}: "
        "${_rooster_first} and ${_rooster_lib}. Keep one (see the ANGLE "
        "note in windows/CMakeLists.txt).")
    endif()
  endif()
endforeach()

# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

# The executable was called cockhouse.exe, and commet.exe before that. Builds
# from before only take an update that holds their own name, and start it
# afterwards, and their pinned and Start menu shortcuts point at it. A copy
# under each name keeps both working; see docs/adr/0003-rename-to-rooster.md
# for when they can go.
install(FILES "$<TARGET_FILE:${BINARY_NAME}>" DESTINATION "${CMAKE_INSTALL_PREFIX}"
  RENAME "cockhouse.exe" COMPONENT Runtime)
install(FILES "$<TARGET_FILE:${BINARY_NAME}>" DESTINATION "${CMAKE_INSTALL_PREFIX}"
  RENAME "commet.exe" COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# The CEF host is built only by the release/qualification job after the
# locked CEF distribution has been staged. Keeping it opt-in means ordinary
# Flutter development remains independent of a multi-hundred-megabyte native
# runtime while still making the production target part of this project.
option(ROOSTER_BUILD_CEF_HOST "Build the bundled Windows CEF host" OFF)
if(DEFINED ENV{ROOSTER_BUILD_CEF_HOST} AND
   "$ENV{ROOSTER_BUILD_CEF_HOST}" STREQUAL "ON")
  set(ROOSTER_BUILD_CEF_HOST ON)
endif()
if((NOT DEFINED CEF_ROOT OR CEF_ROOT STREQUAL "") AND DEFINED ENV{CEF_ROOT})
  set(CEF_ROOT "$ENV{CEF_ROOT}" CACHE PATH
    "Locked CEF SDK/runtime staging directory" FORCE)
endif()
# Added after the installation settings above: cef_host installs into
# ${CMAKE_INSTALL_PREFIX}/cef_host, and relative destinations would resolve
# against the unexpanded $<TARGET_FILE_DIR:...> prefix.
if(ROOSTER_BUILD_CEF_HOST)
  add_subdirectory("cef_host")
endif()
