# CMakeLists.txt for flutter_local_ai Windows plugin

cmake_minimum_required(VERSION 3.14)
project(flutter_local_ai_plugin LANGUAGES CXX)

set(PLUGIN_NAME "flutter_local_ai_plugin")

# Define the plugin library target
add_library(${PLUGIN_NAME} SHARED
  "flutter_local_ai_plugin.cpp"
)

# Apply a standard Windows set of build settings
target_compile_features(${PLUGIN_NAME} PUBLIC cxx_std_17)

# Link against Flutter Windows embedding
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# List of absolute paths to libraries that should be bundled with the plugin
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(flutter_local_ai_plugin_bundled_libraries
  ""
  PARENT_SCOPE
)
