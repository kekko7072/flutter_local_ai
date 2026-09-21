# Resolves the C++/WinRT projection that reaches Windows AI Foundry (Phi
# Silica) through the Windows App SDK, so that a plain `flutter build windows`
# compiles the Windows AI arm without the host app touching CMake.
#
# Included from CMakeLists.txt. Sets, in the including scope:
#
#   FLUTTER_LOCAL_AI_WINDOWS_AI_ENABLED      ON when a projection was found or
#                                            generated, OFF otherwise.
#   FLUTTER_LOCAL_AI_WINDOWS_AI_INCLUDE_DIR  The directory holding
#                                            winrt/Microsoft.Windows.AI.Text.h.
#
# Every setting below is a CMake cache variable that can also be supplied as
# an environment variable of the same name — the env var is the Flutter-side
# knob, since `flutter build windows` offers no way to pass -D flags:
#
#   FLUTTER_LOCAL_AI_WINDOWS_AI                AUTO (default) | ON | OFF.
#       AUTO enables Windows AI whenever a projection can be resolved and
#       falls back to the unconfigured build (with a warning) when it cannot.
#       ON makes an unresolved projection a configure error. OFF skips it.
#   FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR         A ready-made projection
#       directory (contains winrt/Microsoft.Windows.AI.Text.h). Explicit wins.
#   FLUTTER_LOCAL_AI_WINDOWS_APP_SDK_AI_DIR    An extracted
#       Microsoft.WindowsAppSDK.AI package (contains metadata/*.winmd).
#   FLUTTER_LOCAL_AI_WINDOWS_APP_SDK_AI_VERSION  The NuGet version looked up
#       in the local NuGet cache and, failing that, downloaded.
#   FLUTTER_LOCAL_AI_CPPWINRT_EXE              A cppwinrt.exe to run.
#   FLUTTER_LOCAL_AI_CPPWINRT_VERSION          The Microsoft.Windows.CppWinRT
#       NuGet version looked up in the cache and, failing that, downloaded.
#   FLUTTER_LOCAL_AI_NUGET_DOWNLOAD            ON (default) | OFF. Whether a
#       missing package may be fetched from nuget.org into the build tree.
#
# Resolution order for the projection:
#   1. FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR, if it holds the header.
#   2. Generate one with cppwinrt.exe from the Windows App SDK AI metadata,
#      taking both from FLUTTER_LOCAL_AI_*_DIR/_EXE, then the NuGet global
#      packages folder (%NUGET_PACKAGES% or %USERPROFILE%\.nuget\packages),
#      then a download into ${CMAKE_BINARY_DIR}/flutter_local_ai.
#
# The generated projection is the full Windows SDK plus the App SDK AI
# namespaces, produced by one cppwinrt.exe so that winrt/base.h and every
# namespace header agree on their C++/WinRT version. It is placed ahead of the
# Windows SDK's own cppwinrt headers on the include path for the same reason.
#
# None of this deploys the Windows App Runtime or grants package identity;
# those stay with the host app. See doc/platform-support.md.

# --- Settings ---------------------------------------------------------------

# Cache value when set explicitly, else the env var, else the default.
macro(_flai_setting NAME DEFAULT DOC)
  set(${NAME} "${DEFAULT}" CACHE STRING "${DOC}")
  if("${${NAME}}" STREQUAL "${DEFAULT}"
     AND DEFINED ENV{${NAME}} AND NOT "$ENV{${NAME}}" STREQUAL "")
    set(${NAME} "$ENV{${NAME}}")
  endif()
endmacro()

_flai_setting(FLUTTER_LOCAL_AI_WINDOWS_AI "AUTO"
  "Windows AI Foundry support: AUTO, ON or OFF")
_flai_setting(FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR ""
  "Directory containing a generated winrt/Microsoft.Windows.AI.Text.h")
_flai_setting(FLUTTER_LOCAL_AI_WINDOWS_APP_SDK_AI_DIR ""
  "Extracted Microsoft.WindowsAppSDK.AI package (contains metadata/)")
_flai_setting(FLUTTER_LOCAL_AI_WINDOWS_APP_SDK_AI_VERSION "2.5.5"
  "Microsoft.WindowsAppSDK.AI NuGet version to resolve")
_flai_setting(FLUTTER_LOCAL_AI_CPPWINRT_EXE ""
  "Path to cppwinrt.exe")
_flai_setting(FLUTTER_LOCAL_AI_CPPWINRT_VERSION "2.0.250303.1"
  "Microsoft.Windows.CppWinRT NuGet version to resolve")
_flai_setting(FLUTTER_LOCAL_AI_NUGET_DOWNLOAD "ON"
  "Allow fetching missing NuGet packages from nuget.org at configure time")

set(FLUTTER_LOCAL_AI_WINDOWS_AI_ENABLED OFF)
set(FLUTTER_LOCAL_AI_WINDOWS_AI_INCLUDE_DIR "")

string(TOUPPER "${FLUTTER_LOCAL_AI_WINDOWS_AI}" _flai_mode)
if(_flai_mode STREQUAL "AUTO")
  set(_flai_required OFF)
elseif(_flai_mode MATCHES "^(ON|1|TRUE|YES|Y)$")
  set(_flai_required ON)
else()
  message(STATUS "flutter_local_ai: Windows AI Foundry disabled "
                 "(FLUTTER_LOCAL_AI_WINDOWS_AI=${FLUTTER_LOCAL_AI_WINDOWS_AI}).")
  return()
endif()

# A failure is fatal under ON and a warning under AUTO. Takes the message as
# one or more string fragments, joined without separators.
function(_flai_fail)
  string(JOIN "" MESSAGE ${ARGV})
  if(_flai_required)
    message(FATAL_ERROR "flutter_local_ai: ${MESSAGE}")
  endif()
  message(WARNING
    "flutter_local_ai: ${MESSAGE}\n"
    "Building without Windows AI Foundry; the plugin will report "
    "windowsAiFoundryUnconfigured at runtime. Set "
    "FLUTTER_LOCAL_AI_WINDOWS_AI=OFF to silence this, or see "
    "doc/platform-support.md for the settings.")
endfunction()

set(_flai_header "winrt/Microsoft.Windows.AI.Text.h")
set(_flai_work_dir "${CMAKE_BINARY_DIR}/flutter_local_ai")
set(_flai_nuget_dir "${_flai_work_dir}/nuget")
set(_flai_projection_dir "${_flai_work_dir}/winrt_projection")

# --- 1. A ready-made projection ----------------------------------------------

if(FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR)
  file(TO_CMAKE_PATH "${FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR}" _flai_explicit)
  if(EXISTS "${_flai_explicit}/${_flai_header}")
    message(STATUS "flutter_local_ai: Windows AI projection from "
                   "FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR (${_flai_explicit}).")
    set(FLUTTER_LOCAL_AI_WINDOWS_AI_ENABLED ON)
    set(FLUTTER_LOCAL_AI_WINDOWS_AI_INCLUDE_DIR "${_flai_explicit}")
    return()
  endif()
  _flai_fail("FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR is set to "
             "'${FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR}' but it does not contain "
             "${_flai_header}.")
  return()
endif()

# --- 2. Locate or fetch a NuGet package --------------------------------------

# NuGet lowercases package ids in its global packages folder.
set(_flai_nuget_cache "$ENV{NUGET_PACKAGES}")
if(NOT _flai_nuget_cache)
  set(_flai_nuget_cache "$ENV{USERPROFILE}/.nuget/packages")
endif()
file(TO_CMAKE_PATH "${_flai_nuget_cache}" _flai_nuget_cache)

# Sets OUT_VAR to the extracted package directory for ID/VERSION, looking in
# the NuGet cache first and downloading into the build tree otherwise. PROBE is
# a path relative to the package root that proves the layout is the expected
# one. OUT_VAR is left empty when neither source works.
function(_flai_nuget_package OUT_VAR ID VERSION PROBE)
  set(${OUT_VAR} "" PARENT_SCOPE)
  string(TOLOWER "${ID}" _lower_id)

  set(_cached "${_flai_nuget_cache}/${_lower_id}/${VERSION}")
  if(EXISTS "${_cached}/${PROBE}")
    message(STATUS "flutter_local_ai: ${ID} ${VERSION} from the NuGet cache.")
    set(${OUT_VAR} "${_cached}" PARENT_SCOPE)
    return()
  endif()

  set(_extracted "${_flai_nuget_dir}/${_lower_id}.${VERSION}")
  if(EXISTS "${_extracted}/${PROBE}")
    set(${OUT_VAR} "${_extracted}" PARENT_SCOPE)
    return()
  endif()

  if(NOT FLUTTER_LOCAL_AI_NUGET_DOWNLOAD)
    message(STATUS "flutter_local_ai: ${ID} ${VERSION} is not in "
                   "${_flai_nuget_cache} and downloads are off.")
    return()
  endif()

  set(_url "https://www.nuget.org/api/v2/package/${ID}/${VERSION}")
  set(_nupkg "${_flai_nuget_dir}/${_lower_id}.${VERSION}.nupkg")
  message(STATUS "flutter_local_ai: downloading ${ID} ${VERSION} from nuget.org")
  file(MAKE_DIRECTORY "${_flai_nuget_dir}")
  file(DOWNLOAD "${_url}" "${_nupkg}" STATUS _status TLS_VERIFY ON
       INACTIVITY_TIMEOUT 60)
  list(GET _status 0 _code)
  if(NOT _code EQUAL 0)
    list(GET _status 1 _reason)
    message(STATUS "flutter_local_ai: download of ${_url} failed: ${_reason}")
    file(REMOVE "${_nupkg}")
    return()
  endif()

  # A .nupkg is a zip; `cmake -E tar` reads zip on every CMake this plugin
  # supports, unlike file(ARCHIVE_EXTRACT), which needs 3.18.
  file(REMOVE_RECURSE "${_extracted}")
  file(MAKE_DIRECTORY "${_extracted}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xf "${_nupkg}"
    WORKING_DIRECTORY "${_extracted}"
    RESULT_VARIABLE _rc OUTPUT_QUIET ERROR_VARIABLE _err)
  file(REMOVE "${_nupkg}")
  if(NOT _rc EQUAL 0 OR NOT EXISTS "${_extracted}/${PROBE}")
    message(STATUS "flutter_local_ai: could not extract ${ID} ${VERSION}: ${_err}")
    file(REMOVE_RECURSE "${_extracted}")
    return()
  endif()
  set(${OUT_VAR} "${_extracted}" PARENT_SCOPE)
endfunction()

# --- 2a. Windows App SDK AI metadata -----------------------------------------

set(_flai_metadata_dir "")
if(FLUTTER_LOCAL_AI_WINDOWS_APP_SDK_AI_DIR)
  file(TO_CMAKE_PATH "${FLUTTER_LOCAL_AI_WINDOWS_APP_SDK_AI_DIR}" _flai_sdk_dir)
  if(NOT EXISTS "${_flai_sdk_dir}/metadata/Microsoft.Windows.AI.Text.winmd")
    _flai_fail("FLUTTER_LOCAL_AI_WINDOWS_APP_SDK_AI_DIR is set to "
               "'${FLUTTER_LOCAL_AI_WINDOWS_APP_SDK_AI_DIR}' but it does not "
               "contain metadata/Microsoft.Windows.AI.Text.winmd.")
    return()
  endif()
else()
  _flai_nuget_package(_flai_sdk_dir
    "Microsoft.WindowsAppSDK.AI" "${FLUTTER_LOCAL_AI_WINDOWS_APP_SDK_AI_VERSION}"
    "metadata/Microsoft.Windows.AI.Text.winmd")
  if(NOT _flai_sdk_dir)
    _flai_fail("could not obtain Microsoft.WindowsAppSDK.AI "
               "${FLUTTER_LOCAL_AI_WINDOWS_APP_SDK_AI_VERSION} (no NuGet cache "
               "copy and no download).")
    return()
  endif()
endif()
set(_flai_metadata_dir "${_flai_sdk_dir}/metadata")

# --- 2b. cppwinrt.exe --------------------------------------------------------

set(_flai_cppwinrt "")
if(FLUTTER_LOCAL_AI_CPPWINRT_EXE)
  file(TO_CMAKE_PATH "${FLUTTER_LOCAL_AI_CPPWINRT_EXE}" _flai_cppwinrt)
  if(NOT EXISTS "${_flai_cppwinrt}")
    _flai_fail("FLUTTER_LOCAL_AI_CPPWINRT_EXE is set to "
               "'${FLUTTER_LOCAL_AI_CPPWINRT_EXE}' but no such file exists.")
    return()
  endif()
else()
  _flai_nuget_package(_flai_cppwinrt_pkg
    "Microsoft.Windows.CppWinRT" "${FLUTTER_LOCAL_AI_CPPWINRT_VERSION}"
    "bin/cppwinrt.exe")
  if(_flai_cppwinrt_pkg)
    set(_flai_cppwinrt "${_flai_cppwinrt_pkg}/bin/cppwinrt.exe")
  else()
    # Last resort: the copy every Windows 10/11 SDK installs. Its version is
    # whatever the SDK shipped, but it still produces a self-consistent
    # projection because base.h is generated alongside the namespaces.
    set(_flai_kits "$ENV{ProgramFiles\(x86\)}/Windows Kits/10/bin")
    file(TO_CMAKE_PATH "${_flai_kits}" _flai_kits)
    file(GLOB _flai_sdk_cppwinrt "${_flai_kits}/10.0.*/x64/cppwinrt.exe")
    if(_flai_sdk_cppwinrt)
      list(SORT _flai_sdk_cppwinrt)
      list(GET _flai_sdk_cppwinrt -1 _flai_cppwinrt)
      message(STATUS "flutter_local_ai: using the Windows SDK's cppwinrt.exe "
                     "(${_flai_cppwinrt}).")
    endif()
  endif()
  if(NOT _flai_cppwinrt)
    _flai_fail("no cppwinrt.exe: Microsoft.Windows.CppWinRT "
               "${FLUTTER_LOCAL_AI_CPPWINRT_VERSION} is not in the NuGet cache, "
               "could not be downloaded, and no Windows SDK copy was found.")
    return()
  endif()
endif()

# --- 3. Generate the projection ----------------------------------------------

# Regenerate only when the inputs change; the projection is several hundred
# files and this runs on every configure.
set(_flai_stamp_file "${_flai_projection_dir}/.flutter_local_ai_stamp")
set(_flai_stamp "sdk=${_flai_metadata_dir};cppwinrt=${_flai_cppwinrt}")
set(_flai_previous "")
if(EXISTS "${_flai_stamp_file}")
  file(READ "${_flai_stamp_file}" _flai_previous)
endif()

if(NOT _flai_previous STREQUAL _flai_stamp
   OR NOT EXISTS "${_flai_projection_dir}/${_flai_header}")
  message(STATUS "flutter_local_ai: generating the C++/WinRT projection into "
                 "${_flai_projection_dir} (first build only)")
  file(REMOVE_RECURSE "${_flai_projection_dir}")
  file(MAKE_DIRECTORY "${_flai_projection_dir}")
  execute_process(
    COMMAND "${_flai_cppwinrt}"
      -input sdk
      -input "${_flai_metadata_dir}"
      -output "${_flai_projection_dir}"
      -overwrite
    RESULT_VARIABLE _flai_rc
    OUTPUT_VARIABLE _flai_out
    ERROR_VARIABLE _flai_err)
  if(NOT _flai_rc EQUAL 0 OR NOT EXISTS "${_flai_projection_dir}/${_flai_header}")
    file(REMOVE_RECURSE "${_flai_projection_dir}")
    _flai_fail("cppwinrt.exe failed to generate the projection "
               "(exit ${_flai_rc}).\n${_flai_out}\n${_flai_err}")
    return()
  endif()
  file(WRITE "${_flai_stamp_file}" "${_flai_stamp}")
endif()

message(STATUS "flutter_local_ai: Windows AI Foundry enabled "
               "(Windows App SDK AI ${FLUTTER_LOCAL_AI_WINDOWS_APP_SDK_AI_VERSION}).")
set(FLUTTER_LOCAL_AI_WINDOWS_AI_ENABLED ON)
set(FLUTTER_LOCAL_AI_WINDOWS_AI_INCLUDE_DIR "${_flai_projection_dir}")
