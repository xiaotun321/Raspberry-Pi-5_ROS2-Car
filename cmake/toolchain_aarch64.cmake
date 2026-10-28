# 参考 hs411 的 toolchain_x5.cmake；库和头文件来自开发板，构建工具在主机运行。
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

if(NOT DEFINED ENV{CAR_SYSROOT} OR "$ENV{CAR_SYSROOT}" STREQUAL "")
  message(FATAL_ERROR "Set CAR_SYSROOT in version/cross.conf or the environment")
endif()
if(NOT DEFINED ENV{CAR_CROSS_PREFIX} OR "$ENV{CAR_CROSS_PREFIX}" STREQUAL "")
  message(FATAL_ERROR "Set CAR_CROSS_PREFIX to the cross compiler executable prefix")
endif()
if(NOT EXISTS "$ENV{CAR_TARGET_GCC_LIBDIR}/libstdc++.so")
  message(FATAL_ERROR "Use version/autogen.sh to detect CAR_TARGET_GCC_LIBDIR")
endif()
set(CMAKE_SYSROOT "$ENV{CAR_SYSROOT}")
set(CMAKE_C_COMPILER "$ENV{CAR_CROSS_PREFIX}gcc")
set(CMAKE_CXX_COMPILER "$ENV{CAR_CROSS_PREFIX}g++")
set(CMAKE_ASM_COMPILER "$ENV{CAR_CROSS_PREFIX}gcc")
set(CMAKE_AR "$ENV{CAR_CROSS_PREFIX}ar")
set(CMAKE_RANLIB "$ENV{CAR_CROSS_PREFIX}ranlib")
set(CMAKE_STRIP "$ENV{CAR_CROSS_PREFIX}strip")
set(CMAKE_LINKER "$ENV{CAR_CROSS_PREFIX}ld")

# Arm 官方 none-linux-gnu 工具链不一定自动识别 Debian/Ubuntu multiarch 目录。
set(CMAKE_LIBRARY_ARCHITECTURE aarch64-linux-gnu)
set(CAR_MULTIARCH "${CMAKE_SYSROOT}/usr/lib/aarch64-linux-gnu")
set(CMAKE_C_FLAGS_INIT
  "-isystem ${CMAKE_SYSROOT}/usr/include/aarch64-linux-gnu -B${CAR_MULTIARCH}/")
set(CMAKE_CXX_FLAGS_INIT "${CMAKE_C_FLAGS_INIT}")
set(CMAKE_EXE_LINKER_FLAGS_INIT
  "-L$ENV{CAR_TARGET_GCC_LIBDIR} -L${CAR_MULTIARCH} -L${CMAKE_SYSROOT}/lib/aarch64-linux-gnu")

file(GLOB CAR_VENDOR_PREFIXES LIST_DIRECTORIES true "${CMAKE_SYSROOT}/opt/ros/jazzy/opt/*")
set(CAR_LIBRARY_DIRS
  "${CAR_MULTIARCH}"
  "${CMAKE_SYSROOT}/lib/aarch64-linux-gnu"
  "${CMAKE_SYSROOT}/opt/ros/jazzy/lib"
)
foreach(prefix IN LISTS CAR_VENDOR_PREFIXES)
  list(APPEND CAR_LIBRARY_DIRS "${prefix}/lib")
endforeach()
# rpath-link 只用于链接期，不把构建机 sysroot 路径写入开发板运行路径。
foreach(directory IN LISTS CAR_LIBRARY_DIRS)
  string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT " -Wl,-rpath-link,${directory}")
endforeach()
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${CMAKE_EXE_LINKER_FLAGS_INIT}")

set(CMAKE_FIND_ROOT_PATH "${CMAKE_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
list(PREPEND CMAKE_PREFIX_PATH
  "${CMAKE_SYSROOT}/opt/ros/jazzy" "${CMAKE_SYSROOT}/usr" ${CAR_VENDOR_PREFIXES})

# ament 使用主机 Python 生成构建文件，不能运行 sysroot 内的 ARM Python。
set(Python3_EXECUTABLE "/usr/bin/python3" CACHE FILEPATH "Host Python interpreter")
set(Python3_FIND_STRATEGY LOCATION)
set(Python3_FIND_IMPLEMENTATIONS CPython)
set(ENV{PKG_CONFIG_SYSROOT_DIR} "${CMAKE_SYSROOT}")
set(ENV{PKG_CONFIG_PATH} "")
set(ENV{PKG_CONFIG_LIBDIR}
  "${CAR_MULTIARCH}/pkgconfig:${CMAKE_SYSROOT}/usr/share/pkgconfig:${CMAKE_SYSROOT}/opt/ros/jazzy/lib/pkgconfig")
