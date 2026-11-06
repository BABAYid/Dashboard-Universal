# Компонент прошивки модуля ввода: шина CAN, протокол джойстика BMW, задачи.
idf_component_register(
    SRCS
        "main.c"
        "can_bus.c"
        "bmw_joystick.c"
    INCLUDE_DIRS
        "."
    REQUIRES
        driver
        esp_timer
)

# Предупреждения включены строго, как и в блоке сбора: прошивка автомобильная,
# тихо проглоченное предупреждение здесь дороже лишней строчки в сборке.
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra)
endif()
