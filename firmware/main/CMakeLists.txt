# Компонент прошивки: карта платы, драйверы входов, состояние машины, кадры CAN.
idf_component_register(
    SRCS
        "main.c"
        "can_protocol.c"
        "inputs_digital.c"
        "inputs_analog.c"
        "inputs_freq.c"
        "vehicle_signals.c"
        "vehicle_state.c"
        "twai_bus.c"
    INCLUDE_DIRS
        "."
    REQUIRES
        driver
        esp_timer
        esp_driver_gpio
        esp_driver_i2c
)

# Предупреждения компилятора включены строго: прошивка автомобильная, тихо
# проглоченное предупреждение здесь дороже лишней строчки в сборке.
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra)
endif()
