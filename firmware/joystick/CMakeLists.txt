# ============================================================================
#  Модуль ввода приборной панели: джойстик BMW iDrive (F20/F30) на ESP32.
#
#  Это ОТДЕЛЬНЫЙ проект, а не компонент блока сбора (firmware/): у модуля
#  ввода своя ESP32, своя прошивка и своя задача — превращать события
#  джойстика в кадр 0x530. Общий у них только протокол шины
#  (can_protocol_v1.5.txt в корне проекта).
#
#  Сборка:
#      . $IDF_PATH/export.sh
#      idf.py set-target esp32
#      idf.py build
#      idf.py -p /dev/ttyUSB0 flash monitor
# ============================================================================
cmake_minimum_required(VERSION 3.16)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)

project(dashboard_joystick)
