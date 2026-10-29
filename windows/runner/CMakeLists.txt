cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "otzar_window_automation.cpp"
  "hang_monitor.cpp"
  "drag_preview_window.cpp"
  "jump_list_manager.cpp"
  "main.cpp"
  "phantom_mouse_button_filter.cpp"
  "shift_key_normalizer.cpp"
  "splash_window.cpp"
  "startup_watchdog.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# ה-commit בדוחות התקיעה. `flutter build`/`run` מריצים configure בכל בנייה,
# ולכן הערך עדכני; רק startup_watchdog.cpp מקומפל מחדש כשהוא משתנה.
find_package(Git QUIET)
if(GIT_FOUND)
  execute_process(
    COMMAND "${GIT_EXECUTABLE}" rev-parse --short=12 HEAD
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    OUTPUT_VARIABLE OTZARIA_BUILD_COMMIT
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET)
  execute_process(
    COMMAND "${GIT_EXECUTABLE}" status --porcelain --untracked-files=no
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    OUTPUT_VARIABLE OTZARIA_BUILD_CHANGES
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET)
  if(OTZARIA_BUILD_COMMIT AND OTZARIA_BUILD_CHANGES)
    string(APPEND OTZARIA_BUILD_COMMIT "-dirty")
  endif()
endif()
if(OTZARIA_BUILD_COMMIT)
  set_property(SOURCE "startup_watchdog.cpp" APPEND PROPERTY
    COMPILE_DEFINITIONS "OTZARIA_BUILD_COMMIT=\"${OTZARIA_BUILD_COMMIT}\"")
endif()

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
# windowscodecs (WIC) — פענוח ה-PNG של סמל ה-splash הנייטיב (splash_window.cpp).
target_link_libraries(${BINARY_NAME} PRIVATE "windowscodecs.lib")
# ole32/shell32/propsys — Jump List מותאם (ICustomDestinationList, IShellLink,
# InitPropVariantFromString) ב-jump_list_manager.cpp.
target_link_libraries(${BINARY_NAME} PRIVATE "ole32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "propsys.lib")
# psapi — מפת המודולים של גלאי התקיעות (startup_watchdog.cpp).
target_link_libraries(${BINARY_NAME} PRIVATE "psapi.lib")
# comctl32 — SetWindowSubclass של phantom_mouse_button_filter.cpp ו-shift_key_normalizer.cpp.
target_link_libraries(${BINARY_NAME} PRIVATE "comctl32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
