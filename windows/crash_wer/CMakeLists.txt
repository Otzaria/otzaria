# WerFault אינו מוצא את ה-CRT של האפליקציה; הדגלים מקומיים לתיקייה זו.
# CMP0091 אינו NEW ב-project הראשי, ולכן MSVC_RUNTIME_LIBRARY אינו חל.
foreach(flags_var CMAKE_CXX_FLAGS_DEBUG CMAKE_CXX_FLAGS_PROFILE CMAKE_CXX_FLAGS_RELEASE)
  string(REPLACE "/MDd" "/MTd" ${flags_var} "${${flags_var}}")
  string(REPLACE "/MD" "/MT" ${flags_var} "${${flags_var}}")
endforeach()

add_library(otzaria_crash_wer SHARED
  "../runner/crash_wer.cpp"
  "../runner/crash_wer.def"
  "../runner/image_identity.cpp"
)
apply_standard_settings(otzaria_crash_wer)
target_compile_definitions(otzaria_crash_wer PRIVATE "NOMINMAX")
target_link_libraries(otzaria_crash_wer PRIVATE "dbghelp.lib" "psapi.lib")
