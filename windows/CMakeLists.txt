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

# The host application owns Windows App SDK deployment/bootstrap and MSIX
# capabilities. Enabling this requires the 2.0+ C++/WinRT projections.
option(FLUTTER_LOCAL_AI_WINDOWS_AI "Enable Windows App SDK language model" OFF)
set(FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR "" CACHE PATH
  "Directory containing the generated winrt/Microsoft.Windows.AI.Text.h")
if(FLUTTER_LOCAL_AI_WINDOWS_AI)
  if(NOT EXISTS "${FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR}/winrt/Microsoft.Windows.AI.Text.h")
    message(FATAL_ERROR "Set FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR to the Windows App SDK 2.0+ projection directory. See doc/gemma-readiness.md.")
  endif()
  target_include_directories(${PLUGIN_NAME} PRIVATE "${FLUTTER_LOCAL_AI_WINRT_INCLUDE_DIR}")
  target_compile_definitions(${PLUGIN_NAME} PRIVATE WINDOWS_AI_AVAILABLE=1)
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
