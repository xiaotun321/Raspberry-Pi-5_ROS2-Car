cmake_minimum_required(VERSION 3.16)
project(tb6612_car_ros2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# 可选静态检查；默认关闭，开启时使用仓库根目录的 .clang-tidy。
option(ENABLE_CLANG_TIDY "Run clang-tidy while compiling" OFF)
if(ENABLE_CLANG_TIDY)
  find_program(CLANG_TIDY_EXECUTABLE NAMES clang-tidy)
  if(NOT CLANG_TIDY_EXECUTABLE)
    message(FATAL_ERROR "ENABLE_CLANG_TIDY requires clang-tidy")
  endif()
  set(CMAKE_CXX_CLANG_TIDY "${CLANG_TIDY_EXECUTABLE}")
endif()

if(NOT UNIX)
  message(FATAL_ERROR "keyboard_teleop requires a POSIX terminal; build on Linux/ROS 2")
endif()

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(geometry_msgs REQUIRED)

# Follow hs411: shared headers in src/common, process entries in package/src.
add_library(common INTERFACE)
target_include_directories(common INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/../common)

add_executable(keyboard_teleop src/proc_keyboard_teleop.cpp)
target_link_libraries(keyboard_teleop PRIVATE common)
# 显式指定 PUBLIC，避免 ament 内部链接调用与上面的 PRIVATE 关键字写法混用。
ament_target_dependencies(keyboard_teleop PUBLIC rclcpp geometry_msgs)
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
  target_compile_options(keyboard_teleop PRIVATE -Wall -Wextra -Wpedantic)
endif()

install(TARGETS keyboard_teleop DESTINATION lib/${PROJECT_NAME})
install(DIRECTORY launch DESTINATION share/${PROJECT_NAME})

if(BUILD_TESTING)
  enable_testing()
  add_subdirectory(test)
endif()

ament_package()
