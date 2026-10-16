# ============================================================================
#  Прошивка блока сбора приборной панели (ESP32, ESP-IDF).
#
#  Сборка:
#      . $IDF_PATH/export.sh
#      idf.py set-target esp32
#      idf.py build
#      idf.py -p /dev/ttyUSB0 flash monitor
#
#  Кодировщик кадров (main/can_protocol.c) проверяется ещё и на компьютере,
#  без ESP-IDF: firmware/test/ — см. firmware/README.md.
# ============================================================================
cmake_minimum_required(VERSION 3.16)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)

project(dashboard_collector)
