cmake_minimum_required(VERSION 3.16)

project(Dashboard VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Location Positioning WebView)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(appDashboard
    main.cpp
)

qt_add_qml_module(appDashboard
    URI Dashboard
    QML_FILES
        Main.qml
        Speedometer.qml
        Tachometer.qml
        Settings.qml
        Indicators.qml
        NavigationMap.qml
        MapWebView.qml
    RESOURCES
        resources.qrc
)

set_target_properties(appDashboard PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appDashboard
    PRIVATE Qt6::Quick Qt6::Location Qt6::Positioning Qt6::WebView
)

include(GNUInstallDirs)
install(TARGETS appDashboard
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
