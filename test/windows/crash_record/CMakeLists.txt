cmake_minimum_required(VERSION 3.14)
project(crash_record_test LANGUAGES CXX)
cmake_policy(VERSION 3.14...3.25)
set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")

function(apply_standard_settings target)
  target_compile_features(${target} PUBLIC cxx_std_17)
  target_compile_options(${target} PRIVATE /W4 /WX /wd4100 /EHsc /utf-8)
  target_compile_definitions(${target} PRIVATE NOMINMAX _HAS_EXCEPTIONS=0)
endfunction()

add_subdirectory("../../../windows/crash_wer" crash_wer)
add_executable(crash_record_test
  "../crash_record_test.cpp"
  "../../../windows/runner/image_identity.cpp"
)
apply_standard_settings(crash_record_test)
target_link_libraries(crash_record_test PRIVATE psapi.lib shell32.lib ole32.lib)
enable_testing()
add_test(NAME crash_record COMMAND crash_record_test "$<TARGET_FILE:otzaria_crash_wer>")
