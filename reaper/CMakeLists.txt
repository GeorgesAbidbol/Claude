cmake_minimum_required(VERSION 3.20)
project(reaper_ma3tools VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(MSVC)
  # Static C++ runtime: the DLL loads without the Visual C++ Redistributable.
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
  # Sources and string literals are UTF-8 (French accents in menus and dialogs).
  add_compile_options(/utf-8)
endif()

option(MA3TOOLS_BUILD_EXTENSION "Build the REAPER extension (downloads the REAPER SDK and WDL)" ON)
option(MA3TOOLS_BUILD_TESTS "Build the unit tests" ON)

# Core logic, independent of REAPER.
add_library(ma3core STATIC src/osc.cpp src/template.cpp src/schedule.cpp src/sender.cpp src/triggers.cpp)
target_include_directories(ma3core PUBLIC src)
find_package(Threads REQUIRED)
target_link_libraries(ma3core PUBLIC Threads::Threads)
if(WIN32)
  target_link_libraries(ma3core PUBLIC ws2_32)
endif()

if(MA3TOOLS_BUILD_TESTS)
  enable_testing()
  add_executable(ma3tests tests/tests.cpp)
  target_link_libraries(ma3tests PRIVATE ma3core)
  add_test(NAME ma3tests COMMAND ma3tests)
endif()

if(MA3TOOLS_BUILD_EXTENSION)
  include(FetchContent)
  # reaper_plugin.h includes "../WDL/swell/swell.h": it resolves against the include path
  # vendor/WDL/WDL (the WDL repository keeps its sources in a WDL/ subfolder).
  set(VENDOR_DIR ${CMAKE_BINARY_DIR}/vendor)
  FetchContent_Declare(reaper_sdk
    GIT_REPOSITORY https://github.com/justinfrankel/reaper-sdk.git
    GIT_TAG a98b8bf959f99702fe4aeae045b7434c76188683
    SOURCE_DIR ${VENDOR_DIR}/reaper-sdk)
  FetchContent_Declare(wdl
    GIT_REPOSITORY https://github.com/justinfrankel/WDL.git
    GIT_TAG 0c2af4f68b052ce974cb53dc510f88978dc99dbd
    GIT_SHALLOW FALSE
    SOURCE_DIR ${VENDOR_DIR}/WDL)
  FetchContent_Populate(reaper_sdk)
  FetchContent_Populate(wdl)

  # SWELL (menus on macOS/Linux) is provided by REAPER at run time through the modstub.
  set(SWELL_DIR ${VENDOR_DIR}/WDL/WDL/swell)
  if(APPLE)
    enable_language(OBJCXX)
    set(SWELL_STUB ${SWELL_DIR}/swell-modstub.mm)
  elseif(UNIX)
    set(SWELL_STUB ${SWELL_DIR}/swell-modstub-generic.cpp)
  endif()
  add_library(reaper_ma3tools SHARED src/main.cpp ${SWELL_STUB})
  target_link_libraries(reaper_ma3tools PRIVATE ma3core)
  if(APPLE)
    target_link_libraries(reaper_ma3tools PRIVATE "-framework Cocoa")
  endif()
  target_include_directories(reaper_ma3tools PRIVATE ${VENDOR_DIR}/reaper-sdk/sdk ${VENDOR_DIR}/WDL/WDL)
  target_compile_definitions(reaper_ma3tools PRIVATE SWELL_PROVIDED_BY_APP)
  set_target_properties(reaper_ma3tools PROPERTIES PREFIX "" CXX_VISIBILITY_PRESET hidden)
  if(APPLE)
    set_target_properties(reaper_ma3tools PROPERTIES SUFFIX ".dylib")
  endif()

  # End-to-end test: fake REAPER host + UDP listener (Linux and macOS).
  if(MA3TOOLS_BUILD_TESTS AND NOT WIN32)
    find_package(Python3 COMPONENTS Interpreter)
    add_executable(fake_host tests/fake_host.cpp)
    target_include_directories(fake_host PRIVATE ${VENDOR_DIR}/reaper-sdk/sdk ${VENDOR_DIR}/WDL/WDL)
    target_compile_definitions(fake_host PRIVATE SWELL_PROVIDED_BY_APP)
    target_link_libraries(fake_host PRIVATE ${CMAKE_DL_LIBS})
    if(Python3_FOUND)
      add_test(NAME e2e COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/e2e.py
               $<TARGET_FILE:fake_host> $<TARGET_FILE:reaper_ma3tools>)
    endif()
  endif()
endif()
