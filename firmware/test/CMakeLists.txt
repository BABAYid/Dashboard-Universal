# ============================================================================
#  Тесты прошивки на компьютере — без ESP32 и без ESP-IDF.
#
#      cmake -S firmware/test -B firmware-build
#      cmake --build firmware-build
#      ./firmware-build/test_frames     # кодировщик кадров 0x100…0x7F0
#      ./firmware-build/test_signals    # таблица проводов
#
#  Или сразу оба:
#      ctest --test-dir firmware-build --output-on-failure
# ============================================================================
cmake_minimum_required(VERSION 3.16)
project(firmware_host_tests C)

set(CMAKE_C_STANDARD 11)

# --- Тест кодировщика кадров ---
add_executable(test_frames
    test_frames.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../main/can_protocol.c
)
target_include_directories(test_frames PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../main)

# --- Тест таблицы проводов ---
add_executable(test_signals
    test_signals.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../main/vehicle_signals.c
)
target_include_directories(test_signals PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../main)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(test_frames PRIVATE -Wall -Wextra -Werror)
    target_compile_options(test_signals PRIVATE -Wall -Wextra -Werror)
endif()

enable_testing()
add_test(NAME frames COMMAND test_frames)
add_test(NAME signals COMMAND test_signals)
