cmake_minimum_required(VERSION 3.16)

project(Dashboard VERSION 0.2 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick WebView Network Concurrent HttpServer WebSockets)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(appDashboard
    main.cpp
)

# Сгенерированный qmltyperegistrar код подключает <CanBackend.h> и
# <MediaBackend.h> по имени файла
target_include_directories(appDashboard PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/can
    ${CMAKE_CURRENT_SOURCE_DIR}/gps
    ${CMAKE_CURRENT_SOURCE_DIR}/media
    ${CMAKE_CURRENT_SOURCE_DIR}/speedcam
    ${CMAKE_CURRENT_SOURCE_DIR}/network)

# Все ресурсы (картинки, шрифт) кладутся в ресурсную систему по пути модуля:
# qrc:/qt/qml/Dashboard/images/... — в QML на них ссылаемся относительными путями
# ("images/taho.png"). Абсолютных путей file:///home/... в проекте быть не должно:
# на устройстве (nanoPC-T6) другой пользователь и другая папка.
qt_add_qml_module(appDashboard
    URI Dashboard
    VERSION 1.0
    SOURCES
        can/CanBackend.h
        can/CanBackend.cpp
        gps/GpsBackend.h
        gps/GpsBackend.cpp
        media/MediaBackend.h
        media/MediaBackend.cpp
        speedcam/SpeedCamManager.h
        speedcam/SpeedCamManager.cpp
        network/NetworkServer.h
        network/NetworkServer.cpp
        WeatherProvider.h
        WeatherProvider.cpp
    QML_FILES
        Main.qml
        CenterPanel.qml
        Gauge.qml
        GasAnimation.qml
        Car3DView.qml
        Car3DScene.qml
        EngineView.qml
        WeatherFx.qml
        Speedometer.qml
        Tachometer.qml
        Settings.qml
        Indicators.qml
        CameraWarning.qml
        InputController.qml
        NavPanel.qml
        GenesisSkin.qml
        MapView.qml
        RouteService.qml
    RESOURCES
        # Финальная модель от дизайнера (Toyota Ipsum, метры, 4.59 x 2.05 x 1.73):
        # кузов, 4 двери, задняя дверь, капот, колёса, фары/фонари/поворотники
        # отдельными узлами, 9 материалов без текстур.
        assets/ipsum_fin.glb
        assets/3.glb
        assets/engine_anim.js
        # Бип предупреждения о камере (Smart Driver)
        assets/sounds/camera_beep.wav
        fonts/KdamThmorPro-Regular.ttf
        images/ABS.png
        images/lights_glow.png
        images/around_in.png
        images/batt.png
        images/belt.png
        images/check.png
        images/fuel_tank.png
        images/fuel_tank_gas.png
        images/gabarit.png
        images/gear_D1.png
        images/gear_D2.png
        images/gear_D3.png
        images/gear_D4.png
        images/gear_L.png
        images/gear_N.png
        images/gear_P.png
        images/gear_R.png
        images/H_brake.png
        images/hi_beam.png
        images/left_turn.png
        images/line_down.png
        images/line_up.png
        images/low_L.png
        images/needls_fuel.svg
        images/needls_spd.svg
        images/needls_temp.svg
        images/needls_tho.svg
        images/oil_press.png
        images/right_turn.png
        images/snow.png
        images/Speedometr.png
        images/taho.png
        images/temp_dvs.png
        images/temp_dvs_blue.png
        images/temp_dvs_red.png
        images/tuman.png
        # Мягкое свечение поворотников (радиальный градиент с плавным краем)
        images/turn_glow.png
        images/genesis/dial_glow.png
        images/genesis/dial_speed.png
        images/genesis/dial_tach.png
        images/genesis/footer.png
        images/genesis/icon_clock.png
        images/genesis/icon_coolant.png
        images/genesis/icon_fuel.png
        images/genesis/icon_snow.png
        images/genesis/ind_driving_mode.png
        images/genesis/ind_gear.png
        images/genesis/ind_speed_limit.png
        images/genesis/needle.png
        images/genesis/scale_temp.png
        images/genesis/scale_fuel.png
        images/genesis/odometer.png
        images/genesis/range.png
        images/genesis/rim_left.png
        images/genesis/rim_right.png
        images/genesis/warn_abs.png
        map/maplibre-gl.css
        map/maplibre-gl.js
        map/style.json
        map/index.html
        images/genesis/warn_attention_red.png
        images/genesis/warn_attention_yellow.png
        images/genesis/warn_battery.png
        images/genesis/warn_brake_red.png
        images/genesis/warn_brake_yellow.png
        images/genesis/warn_car_arrow_down.png
        images/genesis/warn_car_arrows.png
        images/genesis/warn_car_slope.png
        images/genesis/warn_car_terrain.png
        images/genesis/warn_car_triangle.png
        images/genesis/warn_check_engine.png
        images/genesis/warn_cruise.png
        images/genesis/warn_fog_front.png
        images/genesis/warn_fog_rear.png
        images/genesis/warn_glow_plugs.png
        images/genesis/warn_hand_brake.png
        images/genesis/warn_headlight_level.png
        images/genesis/warn_high_beam.png
        images/genesis/warn_low_range.png
        images/genesis/warn_oil_pressure.png
        images/genesis/warn_position_lights.png
        images/genesis/warn_seat_belt.png
        images/genesis/warn_snowflake.png
        images/genesis/warn_stability_esc.png
        images/genesis/warn_stability_off.png
        images/genesis/warn_tire_pressure.png
        # Значки типов камер от дизайнера (для предупреждений Smart Driver)
        images/speedcam/type_102.png
)

set_target_properties(appDashboard PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appDashboard
    PRIVATE Qt6::Quick Qt6::WebView Qt6::Network Qt6::Concurrent
            Qt6::HttpServer Qt6::WebSockets
)

include(GNUInstallDirs)
install(TARGETS appDashboard
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# ---------------------------------------------------------------------------
#  Тест разбора CAN-протокола (не входит в обычную сборку):
#      cmake -S Dashboard -B build -DDASHBOARD_BUILD_TESTS=ON
#      cmake --build build --target test_canprotocol && ./build/test_canprotocol
# ---------------------------------------------------------------------------
option(DASHBOARD_BUILD_TESTS "Собрать тест разбора CAN-протокола" OFF)

if(DASHBOARD_BUILD_TESTS)
    add_executable(test_canprotocol
        tests/test_canprotocol.cpp
        can/CanBackend.cpp
    )
    target_include_directories(test_canprotocol PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/can)
    target_link_libraries(test_canprotocol PRIVATE Qt6::Quick)

    # Тест базы камер: разбор speedcam.txt, гаверсинус, фильтры, демо-камера.
    add_executable(test_speedcam
        tests/test_speedcam.cpp
        speedcam/SpeedCamManager.cpp
    )
    target_include_directories(test_speedcam PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/speedcam)
    target_link_libraries(test_speedcam PRIVATE Qt6::Core Qt6::Qml Qt6::Concurrent)
endif()
