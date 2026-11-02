# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.
#
# ROOSTER: vendored from media_kit_libs_windows_video 1.0.11 for Windows on
# Arm. The x64 inputs are upstream's, unchanged. The arm64 inputs are the
# ones media_kit's own Windows ARM64 change (media-kit/media-kit#1436) takes:
# libmpv from media-kit/libmpv-win32-video-cmake (20241021, aarch64) and
# ANGLE from Carapacik/flutter-windows-ANGLE-OpenGL-ES v1.1.0
# (alexmercerind/flutter-windows-ANGLE-OpenGL-ES#8), each pinned by SHA-256.
# The v1.1.0 ANGLE archive keeps its DLLs in lib/, beside the import
# libraries, where the v1.0.1 one had them at the root.

cmake_minimum_required(VERSION 3.14)

# This option is read by the other packages which are part of package:media_kit.
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

# Deal with MSVC incompatiblity
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# ROOSTER: the architecture being built. Flutter passes
# FLUTTER_TARGET_PLATFORM (windows-x64 or windows-arm64) and the Visual
# Studio generator platform says the same thing.
if(DEFINED FLUTTER_TARGET_PLATFORM AND FLUTTER_TARGET_PLATFORM MATCHES "arm64")
  set(MEDIA_KIT_ARCH "arm64")
elseif(DEFINED FLUTTER_TARGET_PLATFORM AND FLUTTER_TARGET_PLATFORM MATCHES "x64")
  set(MEDIA_KIT_ARCH "x64")
else()
  string(TOLOWER "${CMAKE_GENERATOR_PLATFORM}" _media_kit_generator_platform)
  if(_media_kit_generator_platform STREQUAL "arm64")
    set(MEDIA_KIT_ARCH "arm64")
  elseif(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(MEDIA_KIT_ARCH "x64")
  else()
    message(FATAL_ERROR "media_kit_libs_windows_video: 32-bit Windows is not supported")
  endif()
endif()
message(STATUS "media_kit_libs_windows_video: building for ${MEDIA_KIT_ARCH}")

# ------------------------------------------------------------------------------
function(download_and_verify url md5 locationForArchive)
  # Check if the archive exists.
  if(EXISTS "${locationForArchive}")
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    # If MD5 doesn't match, delete the archive to download again.
    if(NOT md5 STREQUAL ARCHIVE_MD5)
      file(REMOVE "${locationForArchive}")
      message(STATUS "MD5 mismatch. File deleted.")
    endif()
  endif()

  # Download the archive if it doesn't exist.
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(DOWNLOAD "${url}" "${locationForArchive}")
    message(STATUS "Downloaded archive to ${locationForArchive}.")

    # Verify MD5 of the newly downloaded file.
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    if(md5 STREQUAL ARCHIVE_MD5)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      message(FATAL_ERROR "${locationForArchive} Integrity check failed, please try to re-build project again.")
    endif()
  endif()
endfunction()

# ROOSTER: the arm64 archives are pinned by SHA-256, and a failed download
# is removed rather than kept for the next configure to trip over.
function(download_and_verify_sha256 url sha256 locationForArchive)
  if(EXISTS "${locationForArchive}")
    file(SHA256 "${locationForArchive}" ARCHIVE_SHA256)
    if(NOT sha256 STREQUAL ARCHIVE_SHA256)
      file(REMOVE "${locationForArchive}")
      message(STATUS "SHA-256 mismatch. File deleted.")
    endif()
  endif()

  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(DOWNLOAD "${url}" "${locationForArchive}" STATUS _download_status)
    list(GET _download_status 0 _download_code)
    if(NOT _download_code EQUAL 0)
      file(REMOVE "${locationForArchive}")
      message(FATAL_ERROR "${url}: download failed: ${_download_status}")
    endif()
    message(STATUS "Downloaded archive to ${locationForArchive}.")

    file(SHA256 "${locationForArchive}" ARCHIVE_SHA256)
    if(sha256 STREQUAL ARCHIVE_SHA256)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      file(REMOVE "${locationForArchive}")
      message(FATAL_ERROR "${locationForArchive} Integrity check failed, please try to re-build project again.")
    endif()
  endif()
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  # Check if the directory exists
  if(EXISTS "${dir}")
    # Check if the directory is not empty
    file(GLOB dir_contents "${dir}/*")

    if(dir_contents)
      set(${result_var} TRUE PARENT_SCOPE)
    else()
      set(${result_var} FALSE PARENT_SCOPE)
      message(STATUS "Directory ${dir} exists but is empty!")
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
    message(STATUS "Directory ${dir} does not exist!")
  endif()
endfunction()

# libmpv archive containing the pre-built shared libraries & headers.
if(MEDIA_KIT_ARCH STREQUAL "arm64")
  # ROOSTER: media_kit's own aarch64 build of libmpv.
  set(LIBMPV "mpv-dev-aarch64-20241021-git-0f78584.7z")
  set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-video-cmake/releases/download/20241021/${LIBMPV}")
  set(LIBMPV_SHA256 "d445d02ab2ee60b1b5988f08ce4d2394cdcc594e98321b746a313313e96133ae")
else()
  set(LIBMPV "mpv-dev-x86_64-20230924-git-652a1dd.7z")

  # Download URL & MD5 hash of the libmpv archive.
  set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/${LIBMPV}")
  set(LIBMPV_MD5 "a832ef24b3a6ff97cd2560b5b9d04cd8")
endif()

# Download location of the libmpv archive.
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")

if(MEDIA_KIT_ARCH STREQUAL "arm64")
  download_and_verify_sha256(
    ${LIBMPV_URL}
    ${LIBMPV_SHA256}
    ${LIBMPV_ARCHIVE}
  )
else()
  download_and_verify(
    ${LIBMPV_URL}
    ${LIBMPV_MD5}
    ${LIBMPV_ARCHIVE}
  )
endif()

check_directory_exists_and_not_empty(${LIBMPV_SRC} LIBMPV_SRC_VALID)

# Extract the libmpv archive.
if(NOT LIBMPV_SRC_VALID)
  message(STATUS "Extracting ${LIBMPV}...")
  make_directory("${LIBMPV_SRC}")
  add_custom_target("${PROJECT_NAME}_LIBMPV_EXTRACT" ALL)
  add_custom_command(
    TARGET "${PROJECT_NAME}_LIBMPV_EXTRACT"
    COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${LIBMPV_ARCHIVE}\""
    COMMAND xcopy "\"${LIBMPV_SRC}/include/mpv\"" "\"${LIBMPV_SRC}/mpv\"" /E /H /C /I
    COMMAND rmdir "\"${LIBMPV_SRC}/include\"" /S /Q
    COMMAND ren "\"${LIBMPV_SRC}/mpv\"" "\"include\""
    WORKING_DIRECTORY "${LIBMPV_SRC}"
  )
endif()

# ------------------------------------------------------------------------------

# ANGLE archive containing the pre-built shared libraries & headers.
if(MEDIA_KIT_ARCH STREQUAL "arm64")
  # ROOSTER: the arm64 ANGLE, from the change that brings it to media_kit.
  set(ANGLE "ANGLE-d10b3bd2324e-windows-arm64.7z")
  set(ANGLE_URL "https://github.com/Carapacik/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.1.0/${ANGLE}")
  set(ANGLE_SHA256 "886e8c78c87e670a2681198574092585ef9a7d95a8a5d94c5aa06e27d03dc38c")
else()
  set(ANGLE "ANGLE.7z")

  # Download URL & MD5 hash of the ANGLE archive.
  set(ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z")
  set(ANGLE_MD5 "e866f13e8d552348058afaafe869b1ed")
endif()

# Download location of the ANGLE archive.
set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")

if(MEDIA_KIT_ARCH STREQUAL "arm64")
  download_and_verify_sha256(
    ${ANGLE_URL}
    ${ANGLE_SHA256}
    ${ANGLE_ARCHIVE}
  )
else()
  download_and_verify(
    ${ANGLE_URL}
    ${ANGLE_MD5}
    ${ANGLE_ARCHIVE}
  )
endif()

check_directory_exists_and_not_empty(${ANGLE_SRC} ANGLE_SRC_VALID)

# Extract the ANGLE archive.
if(NOT ANGLE_SRC_VALID)
  message(STATUS "Extracting ${ANGLE}...")
  make_directory("${ANGLE_SRC}")
  add_custom_target("${PROJECT_NAME}_ANGLE_EXTRACT" ALL)
  add_custom_command(
    TARGET "${PROJECT_NAME}_ANGLE_EXTRACT"
    COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${ANGLE_ARCHIVE}\""
    WORKING_DIRECTORY "${ANGLE_SRC}"
  )
endif()

# ------------------------------------------------------------------------------
set(PLUGIN_NAME "media_kit_libs_windows_video_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h"
  "media_kit_libs_windows_video_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES
  CXX_VISIBILITY_PRESET
  hidden
)
target_compile_definitions(
  ${PLUGIN_NAME}
  PRIVATE
  FLUTTER_PLUGIN_IMPL
)

target_include_directories(
  ${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(
  ${PLUGIN_NAME}
  PRIVATE
  flutter
  flutter_wrapper_plugin
)

if(MEDIA_KIT_ARCH STREQUAL "arm64")
  # ROOSTER: the v1.1.0 archive's layout: DLLs in lib/, and SwiftShader's
  # ICD file, which vulkan-1.dll finds beside it.
  set(
    media_kit_libs_windows_video_bundled_libraries
    "${LIBMPV_SRC}/libmpv-2.dll"
    "${ANGLE_SRC}/lib/d3dcompiler_47.dll"
    "${ANGLE_SRC}/lib/libEGL.dll"
    "${ANGLE_SRC}/lib/libGLESv2.dll"
    "${ANGLE_SRC}/lib/vk_swiftshader.dll"
    "${ANGLE_SRC}/lib/vk_swiftshader_icd.json"
    "${ANGLE_SRC}/lib/vulkan-1.dll"
    PARENT_SCOPE
  )
else()
  set(
    media_kit_libs_windows_video_bundled_libraries
    "${LIBMPV_SRC}/libmpv-2.dll"
    "${ANGLE_SRC}/d3dcompiler_47.dll"
    "${ANGLE_SRC}/libEGL.dll"
    "${ANGLE_SRC}/libGLESv2.dll"
    "${ANGLE_SRC}/vk_swiftshader.dll"
    "${ANGLE_SRC}/vulkan-1.dll"
    "${ANGLE_SRC}/zlib.dll"
    PARENT_SCOPE
  )
endif()
