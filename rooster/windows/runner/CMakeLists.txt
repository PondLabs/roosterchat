cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "call_ducking.cpp"
  "flutter_window.cpp"
  "game_overlay.cpp"
  "instance_lock.cpp"
  "main.cpp"
  "splash_window.cpp"
  "utils.cpp"
  "voice_thumb_bar.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# ROOSTER: the program answers for the GL names flutter_angle looks up in the
# whole process, and hands each on to ANGLE: an export per name in
# angle_names.def, forwarded to libGLESv2.dll (the file says why; without
# this, Sunny Side Putt's textures can go to Windows' OPENGL32.dll instead).
# The linker writes a forwarder only for a name some import library knows,
# so the same file is made into one first. Nothing of ANGLE is linked in:
# the exports are names, resolved when the VM asks for them.
set(ROOSTER_ANGLE_NAMES_DEF "${CMAKE_CURRENT_SOURCE_DIR}/angle_names.def")
set(ROOSTER_ANGLE_NAMES_LIB "${CMAKE_CURRENT_BINARY_DIR}/angle_names.lib")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${ROOSTER_ANGLE_NAMES_DEF}")
add_custom_command(
  OUTPUT "${ROOSTER_ANGLE_NAMES_LIB}"
  COMMAND "${CMAKE_AR}" /nologo "/def:${ROOSTER_ANGLE_NAMES_DEF}"
    "/machine:${CMAKE_VS_PLATFORM_NAME}" "/out:${ROOSTER_ANGLE_NAMES_LIB}"
  DEPENDS "${ROOSTER_ANGLE_NAMES_DEF}"
  VERBATIM
)
add_custom_target(rooster_angle_names DEPENDS "${ROOSTER_ANGLE_NAMES_LIB}")
add_dependencies(${BINARY_NAME} rooster_angle_names)
target_link_libraries(${BINARY_NAME} PRIVATE "${ROOSTER_ANGLE_NAMES_LIB}")
file(STRINGS "${ROOSTER_ANGLE_NAMES_DEF}" ROOSTER_ANGLE_NAMES
  REGEX "^  [A-Za-z0-9_]+$")
foreach(name ${ROOSTER_ANGLE_NAMES})
  string(STRIP "${name}" name)
  target_link_options(${BINARY_NAME} PRIVATE
    "/EXPORT:${name}=libGLESv2.${name}")
endforeach(name)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
# ROOSTER: the loading square asks Windows for the monitor's DPI, not the
# engine, which is not loaded yet when it shows (see ../CMakeLists.txt).
target_link_libraries(${BINARY_NAME} PRIVATE "shcore.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
