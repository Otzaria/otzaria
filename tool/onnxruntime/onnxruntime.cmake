# Bundles Microsoft's official ONNX Runtime (pinned in onnxruntime_release.txt)
# into <exe dir>/onnxruntime/. The semantic engine loads it at run time through
# an explicit path; it is never linked, and never placed beside the executable.
#
# The NuGet package is downloaded once, verified by SHA-256, and cached outside
# the repository: $ENV{OTZARIA_BUILD_CACHE}, else the user's cache directory.

set(_OTZARIA_ORT_DIR "${CMAKE_CURRENT_LIST_DIR}")

function(_otzaria_ort_cache_dir out_var)
  if(DEFINED ENV{OTZARIA_BUILD_CACHE} AND NOT "$ENV{OTZARIA_BUILD_CACHE}" STREQUAL "")
    set(base "$ENV{OTZARIA_BUILD_CACHE}")
  elseif(WIN32 AND DEFINED ENV{LOCALAPPDATA})
    set(base "$ENV{LOCALAPPDATA}/otzaria-build-cache")
  elseif(DEFINED ENV{XDG_CACHE_HOME} AND NOT "$ENV{XDG_CACHE_HOME}" STREQUAL "")
    set(base "$ENV{XDG_CACHE_HOME}/otzaria-build-cache")
  elseif(DEFINED ENV{HOME})
    set(base "$ENV{HOME}/.cache/otzaria-build-cache")
  else()
    set(base "${CMAKE_BINARY_DIR}/otzaria-build-cache")
  endif()
  file(TO_CMAKE_PATH "${base}/onnxruntime" dir)
  set(${out_var} "${dir}" PARENT_SCOPE)
endfunction()

# target_platform: a Flutter target platform, e.g. windows-x64 or linux-arm64.
# destination: the install directory, e.g. "${CMAKE_INSTALL_PREFIX}/onnxruntime".
function(otzaria_bundle_onnxruntime target_platform destination)
  if(CMAKE_VERSION VERSION_LESS 3.18)
    message(FATAL_ERROR "Bundling ONNX Runtime needs CMake 3.18+ (file(ARCHIVE_EXTRACT)).")
  endif()

  file(STRINGS "${_OTZARIA_ORT_DIR}/onnxruntime_release.txt" lines REGEX "^[a-z]")
  set(version "")
  set(asset "")
  set(sha256 "")
  set(inner_library "")
  foreach(line IN LISTS lines)
    if(line MATCHES "^version ([0-9.]+)$")
      set(version "${CMAKE_MATCH_1}")
    elseif(line MATCHES "^package ([^ ]+) ([0-9a-f]+)$")
      set(asset "${CMAKE_MATCH_1}")
      set(sha256 "${CMAKE_MATCH_2}")
    elseif(line MATCHES "^${target_platform} ([^ ]+)$")
      set(inner_library "${CMAKE_MATCH_1}")
    endif()
  endforeach()
  if(version STREQUAL "" OR asset STREQUAL "" OR inner_library STREQUAL "")
    message(FATAL_ERROR "No pinned ONNX Runtime library for '${target_platform}'.")
  endif()

  _otzaria_ort_cache_dir(cache_dir)
  set(archive "${cache_dir}/${asset}")
  set(have_archive FALSE)
  if(EXISTS "${archive}")
    file(SHA256 "${archive}" actual)
    if(actual STREQUAL sha256)
      set(have_archive TRUE)
    else()
      file(REMOVE "${archive}")
    endif()
  endif()
  if(NOT have_archive)
    set(url "https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/${version}/${asset}")
    message(STATUS "Downloading ONNX Runtime ${version}: ${url}")
    file(MAKE_DIRECTORY "${cache_dir}")
    # הורדה לקובץ זמני: הורדה שנקטעה לא תשאיר במטמון ארכיון חלקי.
    file(DOWNLOAD "${url}" "${archive}.part"
      TLS_VERIFY ON
      INACTIVITY_TIMEOUT 120
      STATUS status)
    list(GET status 0 code)
    list(GET status 1 reason)
    if(NOT code EQUAL 0)
      # ה-curl של CMake לא סומך על מאגר התעודות של המערכת, ונכשל מאחורי סינון
      # שמחליף תעודות (נטפרי); curl של המערכת כן סומך עליו.
      find_program(OTZARIA_CURL_EXECUTABLE curl)
      if(OTZARIA_CURL_EXECUTABLE)
        message(STATUS "CMake download failed (${reason}); retrying with ${OTZARIA_CURL_EXECUTABLE}")
        execute_process(
          COMMAND "${OTZARIA_CURL_EXECUTABLE}" -fsSL --retry 3 --connect-timeout 30
            -o "${archive}.part" "${url}"
          RESULT_VARIABLE code)
        set(reason "curl exit code ${code}")
      endif()
    endif()
    if(code EQUAL 0)
      file(SHA256 "${archive}.part" actual)
      if(NOT actual STREQUAL sha256)
        set(code 1)
        set(reason "SHA-256 is ${actual}, expected ${sha256}")
      endif()
    endif()
    if(NOT code EQUAL 0)
      file(REMOVE "${archive}.part")
      message(FATAL_ERROR
        "Downloading ${url} failed: ${reason}\n"
        "To build offline, place ${asset} (SHA-256 ${sha256}) in ${cache_dir}.")
    endif()
    file(RENAME "${archive}.part" "${archive}")
  endif()

  if(target_platform MATCHES "^windows-")
    set(library_name "onnxruntime.dll")
  else()
    set(library_name "libonnxruntime.so")
  endif()

  set(extract_dir "${CMAKE_BINARY_DIR}/onnxruntime/${version}")
  set(stamp "${extract_dir}/${target_platform}.sha256")
  set(stamped "")
  if(EXISTS "${stamp}")
    file(READ "${stamp}" stamped)
  endif()
  if(NOT stamped STREQUAL sha256 OR NOT EXISTS "${extract_dir}/${inner_library}")
    file(REMOVE_RECURSE "${extract_dir}")
    # רק הספרייה של הפלטפורמה והרישיונות: החבילה כוללת את כל הפלטפורמות.
    file(ARCHIVE_EXTRACT INPUT "${archive}" DESTINATION "${extract_dir}"
      PATTERNS "${inner_library}" "LICENSE" "ThirdPartyNotices.txt")
    if(NOT EXISTS "${extract_dir}/${inner_library}")
      message(FATAL_ERROR "${asset} has no ${inner_library}.")
    endif()
    file(WRITE "${stamp}" "${sha256}")
  endif()

  install(FILES "${extract_dir}/${inner_library}"
    DESTINATION "${destination}" RENAME "${library_name}" COMPONENT Runtime)
  install(FILES "${extract_dir}/LICENSE" "${extract_dir}/ThirdPartyNotices.txt"
    DESTINATION "${destination}" COMPONENT Runtime)
endfunction()
