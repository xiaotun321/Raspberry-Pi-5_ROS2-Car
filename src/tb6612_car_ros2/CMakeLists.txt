cmake_minimum_required(VERSION 3.16)
project(tb6612_car_ros2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# 发布脚本传入版本与提交号，普通开发构建使用 dev/unknown。
set(CAR_VERSION "dev" CACHE STRING "Application release version")
set(CAR_GIT_COMMIT "unknown" CACHE STRING "Source commit identifier")
if(NOT CAR_VERSION MATCHES "^[A-Za-z0-9.+_~-]+$" OR
   NOT CAR_GIT_COMMIT MATCHES "^[A-Za-z0-9._-]+$")
  message(FATAL_ERROR "Invalid CAR_VERSION or CAR_GIT_COMMIT")
endif()
configure_file(../common/build_version.hpp.in generated/build_version.hpp @ONLY)

# 可选静态检查；默认关闭，开启时使用仓库根目录的 .clang-tidy。
option(ENABLE_CLANG_TIDY "Run clang-tidy while compiling" OFF)
if(ENABLE_CLANG_TIDY)
  find_program(CLANG_TIDY_EXECUTABLE NAMES clang-tidy)
  if(NOT CLANG_TIDY_EXECUTABLE)
    message(FATAL_ERROR "ENABLE_CLANG_TIDY requires clang-tidy")
  endif()
  set(CMAKE_CXX_CLANG_TIDY "${CLANG_TIDY_EXECUTABLE}")
endif()

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
  message(FATAL_ERROR "Car runtime requires Linux/ROS 2 (POSIX terminal and prctl)")
endif()

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(geometry_msgs REQUIRED)

# Follow hs411: shared headers in src/common, process entries in package/src.
add_library(common INTERFACE)
target_include_directories(common INTERFACE
  ${CMAKE_CURRENT_SOURCE_DIR}/../common
  ${CMAKE_CURRENT_BINARY_DIR}/generated
)

add_executable(keyboard_teleop src/proc_keyboard_teleop.cpp)
target_link_libraries(keyboard_teleop PRIVATE common)
# 显式指定 PUBLIC，避免 ament 内部链接调用与上面的 PRIVATE 关键字写法混用。
ament_target_dependencies(keyboard_teleop PUBLIC rclcpp geometry_msgs)
find_package(Threads REQUIRED)
add_executable(car_daemon src/proc_daemon.cpp)
target_link_libraries(car_daemon PRIVATE common Threads::Threads)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  target_compile_options(keyboard_teleop PRIVATE -Wall -Wextra -Wpedantic)
  target_compile_options(car_daemon PRIVATE -Wall -Wextra -Wpedantic)
endif()

install(TARGETS keyboard_teleop car_daemon DESTINATION lib/${PROJECT_NAME})
install(DIRECTORY launch DESTINATION share/${PROJECT_NAME})

if(BUILD_TESTING)
  enable_testing()
  add_subdirectory(test)
endif()

ament_package()
