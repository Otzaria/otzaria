cmake_minimum_required(VERSION 3.16)
project(otzaria_zvfs_c_tests C)

# Optional: -DZVFS_SQLITE_AMALGAMATION=<dir with sqlite3.c> builds test_vfs.
set(ZVFS_SQLITE_AMALGAMATION "" CACHE PATH "SQLite amalgamation directory")
# OFF for cross-compile checks (Android/iOS): builds only the library.
option(ZVFS_BUILD_TESTS "Build test executables" ON)

set(PKG ${CMAKE_CURRENT_SOURCE_DIR}/../..)
file(GLOB ZSTD_SOURCES
  ${PKG}/third_party/zstd/lib/common/*.c
  ${PKG}/third_party/zstd/lib/compress/*.c
  ${PKG}/third_party/zstd/lib/decompress/*.c
  ${PKG}/third_party/zstd/lib/dictBuilder/*.c)

add_library(zvfs_static STATIC
  ${ZSTD_SOURCES}
  ${PKG}/src/zvfs_platform.c
  ${PKG}/src/zvfs_core.c
  ${PKG}/src/zvfs_convert.c
  ${PKG}/src/zvfs_dicts.c
  ${PKG}/src/zvfs_sqlite.c
  ${PKG}/src/zvfs_overlay.c
  ${PKG}/src/zvfs_reader.c
  ${PKG}/src/zvfs_compact.c)
# Keep in sync with hook/build.dart.
target_compile_definitions(zvfs_static PUBLIC
  ZSTD_DISABLE_ASM=1 ZSTD_LEGACY_SUPPORT=0 ZSTD_TRACE=0
  ZSTDLIB_VISIBLE= ZSTDERRORLIB_VISIBLE= ZDICTLIB_VISIBLE=
  ZSTDLIB_STATIC_API= ZDICTLIB_STATIC_API=)
target_include_directories(zvfs_static PUBLIC
  ${PKG}/src ${PKG}/third_party/zstd/lib)
target_include_directories(zvfs_static PRIVATE ${PKG}/third_party/sqlite)
find_package(Threads REQUIRED)
target_link_libraries(zvfs_static PUBLIC Threads::Threads)
if(MSVC)
  target_compile_options(zvfs_static PRIVATE /W3)
else()
  target_compile_options(zvfs_static PRIVATE -Wall -Wextra -Wno-unused-parameter)
endif()

if(NOT ZVFS_BUILD_TESTS)
  return()
endif()
# test-only seams in the library (never in the shipped build)
target_compile_definitions(zvfs_static PUBLIC ZVFS_TEST_HOOKS=1)

add_executable(zvfs_core_tests test_core.c)
target_link_libraries(zvfs_core_tests zvfs_static)

add_executable(zvfs_cli zvfs_cli.c)
target_link_libraries(zvfs_cli zvfs_static)

enable_testing()
add_test(NAME core COMMAND zvfs_core_tests)
set_tests_properties(core PROPERTIES ENVIRONMENT "ZVFS_TEST_TMP=${CMAKE_CURRENT_BINARY_DIR}")

if(ZVFS_SQLITE_AMALGAMATION)
  add_library(sqlite_amal STATIC ${ZVFS_SQLITE_AMALGAMATION}/sqlite3.c)
  target_include_directories(sqlite_amal PUBLIC ${ZVFS_SQLITE_AMALGAMATION})
  target_compile_definitions(sqlite_amal PUBLIC SQLITE_THREADSAFE=1)
  if(UNIX)
    target_link_libraries(sqlite_amal PUBLIC m ${CMAKE_DL_LIBS})
  endif()
  foreach(t vfs)
    add_executable(zvfs_${t}_tests test_${t}.c)
    target_link_libraries(zvfs_${t}_tests zvfs_static sqlite_amal)
    add_test(NAME ${t} COMMAND zvfs_${t}_tests)
    set_tests_properties(${t} PROPERTIES ENVIRONMENT "ZVFS_TEST_TMP=${CMAKE_CURRENT_BINARY_DIR}")
  endforeach()
endif()
