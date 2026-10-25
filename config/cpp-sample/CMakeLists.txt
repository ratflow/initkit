cmake_minimum_required(VERSION 3.24)
project(cpp-sample LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# library with a header, so LSP navigation (gd / gr / K / <leader>ch) has
# something interesting to do
add_library(calc src/calc.cpp)
target_include_directories(calc PUBLIC include)

add_executable(cpp-sample src/main.cpp)
target_link_libraries(cpp-sample PRIVATE calc)

# tests: GoogleTest fetched through vcpkg (see vcpkg.json + CMakePresets.json)
enable_testing()
find_package(GTest CONFIG REQUIRED)
add_executable(unit_tests tests/test_calc.cpp)
target_link_libraries(unit_tests PRIVATE calc GTest::gtest_main)
include(GoogleTest)
gtest_discover_tests(unit_tests)
