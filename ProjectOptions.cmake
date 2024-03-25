include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(embedded_test_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(embedded_test_setup_options)
  option(embedded_test_ENABLE_HARDENING "Enable hardening" ON)
  option(embedded_test_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    embedded_test_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    embedded_test_ENABLE_HARDENING
    OFF)

  embedded_test_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR embedded_test_PACKAGING_MAINTAINER_MODE)
    option(embedded_test_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(embedded_test_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(embedded_test_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(embedded_test_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(embedded_test_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(embedded_test_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(embedded_test_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(embedded_test_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(embedded_test_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(embedded_test_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(embedded_test_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(embedded_test_ENABLE_PCH "Enable precompiled headers" OFF)
    option(embedded_test_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(embedded_test_ENABLE_IPO "Enable IPO/LTO" ON)
    option(embedded_test_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(embedded_test_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(embedded_test_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(embedded_test_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(embedded_test_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(embedded_test_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(embedded_test_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(embedded_test_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(embedded_test_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(embedded_test_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(embedded_test_ENABLE_PCH "Enable precompiled headers" OFF)
    option(embedded_test_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      embedded_test_ENABLE_IPO
      embedded_test_WARNINGS_AS_ERRORS
      embedded_test_ENABLE_USER_LINKER
      embedded_test_ENABLE_SANITIZER_ADDRESS
      embedded_test_ENABLE_SANITIZER_LEAK
      embedded_test_ENABLE_SANITIZER_UNDEFINED
      embedded_test_ENABLE_SANITIZER_THREAD
      embedded_test_ENABLE_SANITIZER_MEMORY
      embedded_test_ENABLE_UNITY_BUILD
      embedded_test_ENABLE_CLANG_TIDY
      embedded_test_ENABLE_CPPCHECK
      embedded_test_ENABLE_COVERAGE
      embedded_test_ENABLE_PCH
      embedded_test_ENABLE_CACHE)
  endif()

  embedded_test_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (embedded_test_ENABLE_SANITIZER_ADDRESS OR embedded_test_ENABLE_SANITIZER_THREAD OR embedded_test_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(embedded_test_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(embedded_test_global_options)
  if(embedded_test_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    embedded_test_enable_ipo()
  endif()

  embedded_test_supports_sanitizers()

  if(embedded_test_ENABLE_HARDENING AND embedded_test_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR embedded_test_ENABLE_SANITIZER_UNDEFINED
       OR embedded_test_ENABLE_SANITIZER_ADDRESS
       OR embedded_test_ENABLE_SANITIZER_THREAD
       OR embedded_test_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${embedded_test_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${embedded_test_ENABLE_SANITIZER_UNDEFINED}")
    embedded_test_enable_hardening(embedded_test_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(embedded_test_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(embedded_test_warnings INTERFACE)
  add_library(embedded_test_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  embedded_test_set_project_warnings(
    embedded_test_warnings
    ${embedded_test_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(embedded_test_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    embedded_test_configure_linker(embedded_test_options)
  endif()

  include(cmake/Sanitizers.cmake)
  embedded_test_enable_sanitizers(
    embedded_test_options
    ${embedded_test_ENABLE_SANITIZER_ADDRESS}
    ${embedded_test_ENABLE_SANITIZER_LEAK}
    ${embedded_test_ENABLE_SANITIZER_UNDEFINED}
    ${embedded_test_ENABLE_SANITIZER_THREAD}
    ${embedded_test_ENABLE_SANITIZER_MEMORY})

  set_target_properties(embedded_test_options PROPERTIES UNITY_BUILD ${embedded_test_ENABLE_UNITY_BUILD})

  if(embedded_test_ENABLE_PCH)
    target_precompile_headers(
      embedded_test_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(embedded_test_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    embedded_test_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(embedded_test_ENABLE_CLANG_TIDY)
    embedded_test_enable_clang_tidy(embedded_test_options ${embedded_test_WARNINGS_AS_ERRORS})
  endif()

  if(embedded_test_ENABLE_CPPCHECK)
    embedded_test_enable_cppcheck(${embedded_test_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(embedded_test_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    embedded_test_enable_coverage(embedded_test_options)
  endif()

  if(embedded_test_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(embedded_test_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(embedded_test_ENABLE_HARDENING AND NOT embedded_test_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR embedded_test_ENABLE_SANITIZER_UNDEFINED
       OR embedded_test_ENABLE_SANITIZER_ADDRESS
       OR embedded_test_ENABLE_SANITIZER_THREAD
       OR embedded_test_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    embedded_test_enable_hardening(embedded_test_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
