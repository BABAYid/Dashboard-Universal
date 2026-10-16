# ============================================================================
#  Тест кодировщика кадров протокола — собирается и запускается на компьютере.
#  ESP-IDF и ESP32 не нужны: проверяются только байты кадра.
#
#      cmake -S firmware/test -B firmware-build
#      cmake --build firmware-build
#      ./firmware-build/test_frames
# ============================================================================
cmake_minimum_required(VERSION 3.16)
project(firmware_frames_test C)

set(CMAKE_C_STANDARD 11)

add_executable(test_frames
    test_frames.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../main/can_protocol.c
)

target_include_directories(test_frames PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../main)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(test_frames PRIVATE -Wall -Wextra -Werror)
endif()

enable_testing()
add_test(NAME frames COMMAND test_frames)
