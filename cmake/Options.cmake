include(Macros)

if(NOT CMAKE_SYSTEM_NAME OR NOT CMAKE_SYSTEM_PROCESSOR)
  message(FATAL_ERROR "CMake included this file before project() was called")
endif()

optionx(CI BOOL "If CI is enabled" DEFAULT OFF)
optionx(BUILDKITE BOOL "If Buildkite is enabled" DEFAULT OFF)
optionx(GITHUB_ACTIONS BOOL "If GitHub Actions is enabled" DEFAULT OFF)

optionx(CMAKE_BUILD_TYPE "Debug|Release|RelWithDebInfo|MinSizeRel" "The build type to use" REQUIRED)

if(CMAKE_BUILD_TYPE MATCHES "Release|RelWithDebInfo|MinSizeRel")
  setx(RELEASE ON)
else()
  setx(RELEASE OFF)
endif()

if(CMAKE_BUILD_TYPE MATCHES "Debug|RelWithDebInfo")
  setx(DEBUG ON)
else()
  setx(DEBUG OFF)
endif()

if(APPLE)
  setx(OS "darwin")
elseif(WIN32)
  setx(OS "windows")
elseif(LINUX)
  setx(OS "linux")
else()
  message(FATAL_ERROR "Unsupported operating system: ${CMAKE_SYSTEM_NAME}")
endif()

if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|arm")
  setx(ARCH "aarch64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "amd64|x86_64|x64|AMD64")
  setx(ARCH "x64")
else()
  message(FATAL_ERROR "Unsupported architecture: ${CMAKE_SYSTEM_PROCESSOR}")
endif()

if(ARCH STREQUAL "x64")
  optionx(ENABLE_BASELINE BOOL "If baseline features should be used for older CPUs (e.g. disables AVX, AVX2)" DEFAULT OFF)
endif()

if(ARCH STREQUAL "aarch64")
  set(DEFAULT_CPU "native")
elseif(ENABLE_BASELINE)
  set(DEFAULT_CPU "nehalem")
else()
  set(DEFAULT_CPU "haswell")
endif()

optionx(CPU STRING "The CPU to use for the compiler" DEFAULT ${DEFAULT_CPU})

optionx(ENABLE_LOGS BOOL "If debug logs should be enabled" DEFAULT ${DEBUG})
optionx(ENABLE_ASSERTIONS BOOL "If debug assertions should be enabled" DEFAULT ${DEBUG})
optionx(ENABLE_CANARY BOOL "If canary features should be enabled" DEFAULT ${DEBUG})
optionx(ENABLE_LTO BOOL "If LTO (link-time optimization) should be used" DEFAULT ${RELEASE})

if(LINUX)
  optionx(ENABLE_VALGRIND BOOL "If Valgrind support should be enabled" DEFAULT OFF)
endif()

if(APPLE AND ENABLE_LTO)
  message(WARNING "Link-Time Optimization is not supported on macOS because it requires -fuse-ld=lld and lld causes many segfaults on macOS (likely related to stack size)")
  setx(ENABLE_LTO OFF)
endif()

if(USE_VALGRIND AND NOT USE_BASELINE)
  message(WARNING "If valgrind is enabled, baseline must also be enabled")
  setx(USE_BASELINE ON)
endif()

file(READ ${CWD}/LATEST DEFAULT_VERSION)

optionx(VERSION STRING "The version of the build" DEFAULT ${DEFAULT_VERSION})

execute_process(
  COMMAND git rev-parse HEAD
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  OUTPUT_VARIABLE DEFAULT_REVISION
  OUTPUT_STRIP_TRAILING_WHITESPACE
  ERROR_QUIET
)

if(NOT DEFAULT_REVISION)
  set(DEFAULT_REVISION "unknown")
endif()

optionx(REVISION STRING "The git revision of the build" DEFAULT ${DEFAULT_REVISION})

if(ENABLE_CANARY)
  set(DEFAULT_CANARY_REVISION "1")
else()
  set(DEFAULT_CANARY_REVISION "0")
endif()

optionx(CANARY_REVISION STRING "The canary revision of the build" DEFAULT ${DEFAULT_CANARY_REVISION})

# Used in process.version, process.versions.node, napi, and elsewhere
optionx(NODEJS_VERSION STRING "The version of Node.js to report" DEFAULT "22.6.0")

# Used in process.versions.modules and compared while loading V8 modules
optionx(NODEJS_ABI_VERSION STRING "The ABI version of Node.js to report" DEFAULT "127")

set(DEFAULT_STATIC_SQLITE ON)
if(APPLE)
  set(DEFAULT_STATIC_SQLITE OFF)
endif()

optionx(USE_STATIC_SQLITE BOOL "If SQLite should be statically linked" DEFAULT ${DEFAULT_STATIC_SQLITE})

set(DEFAULT_STATIC_LIBATOMIC ON)

if(CMAKE_HOST_LINUX AND NOT WIN32 AND NOT APPLE)
  execute_process(
    COMMAND grep -w "NAME" /etc/os-release
    OUTPUT_VARIABLE LINUX_DISTRO
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )

  if(${LINUX_DISTRO} MATCHES "NAME=\"(Arch|Manjaro|Artix) Linux\"|NAME=\"openSUSE Tumbleweed\"")
    set(DEFAULT_STATIC_LIBATOMIC OFF)
  endif()
endif()

optionx(USE_STATIC_LIBATOMIC BOOL "If libatomic should be statically linked" DEFAULT ${DEFAULT_STATIC_LIBATOMIC})
optionx(USE_SYSTEM_ICU BOOL "Use the system-provided libicu. May fix startup crashes when building WebKit yourself." DEFAULT OFF)

# Set the CMAKE_C_FLAGS and CMAKE_CXX_FLAGS for building dependencies.
# This is a mess, since it doesn't use the CMake add_compile_options or target_compile_options commands.
# In the future, make some macros so we can set this automatically.
# e.g.
#       add_c_flags(-mtune=native) - applies to all dependencies
#       add_c_flags({target} -fno-rtti) - applies to a specific target

if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|arm|ARM64")
  if(APPLE)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mcpu=apple-m1")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mcpu=apple-m1")
  else()
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -march=armv8-a+crc -mtune=ampere1")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=armv8-a+crc -mtune=ampere1")
  endif()
else()
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mtune=${CPU}")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mtune=${CPU}")
endif()

if(WIN32)
  list(APPEND CMAKE_ARGS -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded)
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} /Z7 /MT /Ob2 /DNDEBUG /U_DLL")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /Z7 /MT /Ob2 /DNDEBUG /U_DLL -Xclang -fno-c++-static-destructors")
  if(ENABLE_LTO)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fuse-ld=lld -flto -Xclang -emit-llvm-bc")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fuse-ld=lld -flto -Xclang -emit-llvm-bc")
  endif()
else()
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fno-exceptions -fvisibility=hidden -fvisibility-inlines-hidden -mno-omit-leaf-frame-pointer -fno-omit-frame-pointer -fno-asynchronous-unwind-tables -fno-unwind-tables")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-exceptions -fno-rtti -fvisibility=hidden -fvisibility-inlines-hidden -mno-omit-leaf-frame-pointer -fno-omit-frame-pointer -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-c++-static-destructors")
  if(ENABLE_LTO)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -flto=full")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -flto=full -fwhole-program-vtables -fforce-emit-vtables")
    set(CMAKE_LINKER_FLAGS "${CMAKE_LINKER_FLAGS} -flto=full -fwhole-program-vtables -fforce-emit-vtables")
  endif()
  if(LINUX)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -ffunction-sections -fdata-sections -faddrsig")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ffunction-sections -fdata-sections -faddrsig")
    set(CMAKE_LINKER_FLAGS "${CMAKE_LINKER_FLAGS} -Wl,-z,norelro")
  endif()
  if(APPLE)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -D_LIBCXX_ENABLE_ASSERTIONS=0 -D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_NONE")
  endif()
endif()
