# CMakeLists.txt for flutter_local_ai Windows plugin

cmake_minimum_required(VERSION 3.14)
project(flutter_local_ai_plugin LANGUAGES CXX)

set(PLUGIN_NAME "flutter_local_ai_plugin")

# Define the plugin library target
add_library(${PLUGIN_NAME} SHARED
  "flutter_local_ai_plugin.cpp"
  "local_ai_pigeon.g.cpp"
  "local_ai_session_service.cpp"
)

# Apply a standard Windows set of build settings
# C++20 is required for coroutine support (co_await)
target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_20)
# <windows.h> would otherwise define min/max macros over the std:: ones.
target_compile_definitions(${PLUGIN_NAME} PRIVATE NOMINMAX)

# Windows AI Foundry (Phi Silica) is reached through the Windows App SDK's
# C++/WinRT projection. cmake/windows_ai.cmake resolves that projection — an
# explicit directory, the NuGet cache, or a download plus cppwinrt.exe — and
# reports the outcome in FLUTTER_LOCAL_AI_WINDOWS_AI_ENABLED. Under the
# default AUTO mode a projection that cannot be resolved degrades to the
# unconfigured build below, which reports windowsAiFoundryUnconfigured at
# runtime instead of failing to compile. Deploying the Windows App Runtime and
# giving the app package identity remain the host application's job.
include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/windows_ai.cmake")
if(FLUTTER_LOCAL_AI_WINDOWS_AI_ENABLED)
  # BEFORE: the generated winrt/base.h must shadow the Windows SDK's copy, or
  # the two C++/WinRT versions disagree and the projection refuses to compile.
  target_include_directories(${PLUGIN_NAME} BEFORE PRIVATE
    "${FLUTTER_LOCAL_AI_WINDOWS_AI_INCLUDE_DIR}")
  target_compile_definitions(${PLUGIN_NAME} PRIVATE WINDOWS_AI_AVAILABLE=1)
  # C++/WinRT needs exceptions (conformance mode is already implied by
  # /std:c++20), and the projection headers push a single translation unit
  # past the default COFF section limit.
  target_compile_options(${PLUGIN_NAME} PRIVATE /EHsc /bigobj)
  target_link_libraries(${PLUGIN_NAME} PRIVATE windowsapp runtimeobject)
else()
  target_compile_definitions(${PLUGIN_NAME} PRIVATE WINDOWS_AI_AVAILABLE=0)
endif()

# Link against Flutter Windows embedding
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# Set include directories so the header can be found as flutter_local_ai/flutter_local_ai_plugin.h
# The include directory is set to the plugin directory so that flutter_local_ai/flutter_local_ai_plugin.h resolves
target_include_directories(${PLUGIN_NAME} PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)

# List of absolute paths to libraries that should be bundled with the plugin
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(flutter_local_ai_plugin_bundled_libraries
  ""
  PARENT_SCOPE
)
