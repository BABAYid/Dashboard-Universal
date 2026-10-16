// ============================================================================
//  main.c — блок сбора: читает провода машины и отправляет кадры по CAN.
//
//  Схема работы (три задачи, чтобы медленный I2C не задерживал быстрые входы):
//
//      task_inputs (20 мс)  — DIN_1…DIN_23, антидребезг, пересчёт состояния
//      task_analog (25 мс)  — один канал ADS1115 за вызов (круг по 4 — 100 мс)
//      task_can    (50 мс)  — кадры 0x100/0x200/0x300/0x400, раз в 200 мс газ,
//                             раз в 1 с статус, слежение за состоянием шины
//
//  Периоды заданы в config.h и совпадают с can_protocol_v1.2.txt.
//
//  Что в этой версии ещё не сделано (осознанно, ждёт списка проводов):
//    • GPS (GY-GPSV3-NEO-M8N) — висит на UART0, то есть на том же порту, что
//      консоль и прошивка по USB. Пока не используем; при прошивке с
//      подключённым GPS его передатчик мешает загрузчику (см. README).
//    • K-линия (MC33290, UART2) — не опрашивается, выводы свободны.
//    • Сон по зажиганию — каркас есть (vehicle_state_ignition_on), решение
//      отложено до списка проводов: непонятно, будет ли провод ACC.
// ============================================================================
#include <stdio.h>
#include <string.h>

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "board_pins.h"
#include "can_protocol.h"
#include "config.h"
#include "inputs_analog.h"
#include "inputs_digital.h"
#include "inputs_freq.h"
#include "twai_bus.h"
#include "vehicle_signals.h"
#include "vehicle_state.h"

static const char *TAG = "main";

// ---------------------------------------------------------------------------
//  Задача входов: дискретные сигналы, частота и пересчёт состояния
// ---------------------------------------------------------------------------
static void task_inputs(void *arg)
{
    (void)arg;
    TickType_t last_wake = xTaskGetTickCount();

    for (;;) {
        inputs_digital_update();
        inputs_freq_update();
        vehicle_state_update();
        vTaskDelayUntil(&last_wake, pdMS_TO_TICKS(INPUTS_PERIOD_MS));
    }
}

// ---------------------------------------------------------------------------
//  Задача АЦП
// ---------------------------------------------------------------------------
static void task_analog(void *arg)
{
    (void)arg;
    TickType_t last_wake = xTaskGetTickCount();

    for (;;) {
        inputs_analog_update();
        vTaskDelayUntil(&last_wake, pdMS_TO_TICKS(ANALOG_PERIOD_MS));
    }
}

// ---------------------------------------------------------------------------
//  Отладочная печать: раз в секунду в консоль. На столе это главный
//  инструмент проверки проводки — видно, какие входы сработали.
// ---------------------------------------------------------------------------
static void print_debug_state(const vehicle_state_t *st)
{
#if DEBUG_PRINT_STATE
    const uint16_t direct = din_bitmap_direct();
    char bits[DIN_CHANNELS + 1];
    for (int i = 0; i < DIN_CHANNELS; ++i)
        bits[i] = ((i < DIN_DIRECT_COUNT ? (direct >> i) : (din_bitmap_pcf() >> (i - DIN_DIRECT_COUNT))) & 1u)
                      ? '1' : '.';
    bits[DIN_CHANNELS] = '\0';

    ESP_LOGI(TAG, "DIN_1..23 [%s]", bits);
    ESP_LOGI(TAG, "скорость %u км/ч, обороты %u, режим %u, передача %u, газ %s",
             (unsigned)st->speed_kmh, (unsigned)st->rpm,
             (unsigned)st->gearbox.mode, (unsigned)st->gearbox.gear,
             st->gas_mode ? "да" : "нет");
    ESP_LOGI(TAG, "датчики: топливо %u %%, t двиг %u C, бортсеть %u.%u В, "
                  "t снаружи %d C, расход %u.%u л/100",
             (unsigned)st->sensors.fuel_level_pct,
             (unsigned)st->sensors.engine_temp_c,
             (unsigned)(st->sensors.voltage_x10 / 10),
             (unsigned)(st->sensors.voltage_x10 % 10),
             (int)st->sensors.outside_temp_c,
             (unsigned)(st->sensors.fuel_rate_x10 / 10),
             (unsigned)(st->sensors.fuel_rate_x10 % 10));
    ESP_LOGI(TAG, "АЦП мВ: AIN0 %u, AIN1 %u, AIN2 %u, AIN3 %u | I2C-2 %s, ошибок %u",
             (unsigned)analog_mv(0), (unsigned)analog_mv(1),
             (unsigned)analog_mv(2), (unsigned)analog_mv(3),
             inputs_digital_pcf_ok() ? "ок" : "нет ответа",
             (unsigned)inputs_digital_i2c_errors());
    ESP_LOGI(TAG, "CAN: %s, отправлено %u, ошибок %u | частотных входов %d",
             twai_bus_state_name(), (unsigned)twai_bus_frames_sent(),
             (unsigned)twai_bus_error_count(), inputs_freq_channel_count());
#else
    (void)st;
#endif
}

// ---------------------------------------------------------------------------
//  Задача CAN: сборка и отправка кадров по расписанию протокола 1.2
// ---------------------------------------------------------------------------
static void task_can(void *arg)
{
    (void)arg;
    TickType_t last_wake = xTaskGetTickCount();
    uint32_t tick = 0;
    uint8_t status_counter = 0;
    uint8_t frame[CAN_FRAME_BYTES];
    bool can_ok = true;

    const uint32_t gas_every = CAN_PERIOD_GAS_MS / CAN_PERIOD_FAST_MS;       // 4 тика
    const uint32_t status_every = CAN_PERIOD_STATUS_MS / CAN_PERIOD_FAST_MS; // 20 тиков

    for (;;) {
        const vehicle_state_t st = vehicle_state_get();

        if (!vehicle_state_ignition_on()) {
            // Зажигание выключено: по протоколу блок может перестать
            // передавать кадры — приборка воспримет это как потерю связи,
            // что допустимо. Дальше уходим в сон (см. app_sleep_until_ignition).
            app_sleep_until_ignition();
        }

        if (!can_ok) {
            can_ok = twai_bus_init() == ESP_OK;
            if (!can_ok) {
                ESP_LOGW(TAG, "шина CAN недоступна, повтор через секунду");
                vTaskDelay(pdMS_TO_TICKS(1000));
                last_wake = xTaskGetTickCount();
                continue;
            }
        }

        // 0x100 — скорость и обороты (50 мс)
        proto_build_speed_rpm(frame, st.speed_kmh, st.rpm);
        twai_bus_send(CAN_ID_SPEED_RPM, frame);

        // 0x200 — лампы и индикаторы (50 мс)
        proto_build_lights(frame, &st.lights);
        twai_bus_send(CAN_ID_LIGHTS, frame);

        // 0x300 — датчики (50 мс)
        proto_build_sensors(frame, &st.sensors);
        twai_bus_send(CAN_ID_SENSORS, frame);

        // 0x400 — АКПП (50 мс)
        proto_build_gearbox(frame, &st.gearbox);
        twai_bus_send(CAN_ID_GEARBOX, frame);

        // 0x500 — газ (200 мс)
        if (tick % gas_every == 0) {
            proto_build_gas(frame, st.gas_mode, st.gas_sensor_valid, st.gas_sensor_mv);
            twai_bus_send(CAN_ID_GAS, frame);
        }

        // 0x7F0 — статус блока (1000 мс)
        if (tick % status_every == 0) {
            uint8_t errors = twai_bus_error_count();
            const uint8_t analog_errors = inputs_analog_errors();
            if (analog_errors > errors)
                errors = analog_errors;    // ошибки датчиков тоже видно в диагностике
            proto_build_device_status(frame, status_counter++, st.uptime_sec, errors);
            twai_bus_send(CAN_ID_DEVICE_STATUS, frame);
            print_debug_state(&st);
        }

        ++tick;

        // Слежение за шиной и восстановление после bus-off.
        twai_bus_poll();

        vTaskDelayUntil(&last_wake, pdMS_TO_TICKS(CAN_PERIOD_FAST_MS));
    }
}

// ---------------------------------------------------------------------------
//  Запуск
// ---------------------------------------------------------------------------
void app_main(void)
{
    ESP_LOGI(TAG, "=== Блок сбора приборной панели ===");
    ESP_LOGI(TAG, "прошивка %d.%d, протокол CAN %s",
             FW_VERSION_MAJOR, FW_VERSION_MINOR, "1.2");
    ESP_LOGI(TAG, "плата: ESP32 DevKit V1 + оптопары DIN_1…DIN_23, ADS1115, PCF8574");

    // 1. Дискретные входы. Если PCF8574 не ответил — это не повод не работать:
    //    входы DIN_1…DIN_15 живут своей жизнью, а причина видна в логе.
    if (inputs_digital_init() != ESP_OK)
        ESP_LOGW(TAG, "входы DIN_16…DIN_23 недоступны (PCF8574), остальное работает");

    // 2. Частотные входы (спидометр, тахометр) — по таблице проводов.
    inputs_freq_init();

    // 3. Аналоговые датчики.
    if (inputs_analog_init() != ESP_OK)
        ESP_LOGW(TAG, "ADS1115 недоступен — топливо, температура и газ будут заглушками");

    // 4. Состояние машины (и предупреждения о незаполненной таблице проводов).
    vehicle_state_init();

    // 5. Шина CAN. Если не поднялась — задача CAN будет пробовать заново.
    if (twai_bus_init() != ESP_OK)
        ESP_LOGW(TAG, "CAN не поднялся с первого раза, задача попробует снова");

    // 6. Задачи.
    xTaskCreate(task_inputs, "inputs", 4096, NULL, APP_TASK_PRIORITY_INPUTS, NULL);
    xTaskCreate(task_analog, "analog", 4096, NULL, APP_TASK_PRIORITY_INPUTS, NULL);
    xTaskCreate(task_can, "can", 4096, NULL, APP_TASK_PRIORITY_CAN, NULL);

    ESP_LOGI(TAG, "запущено: входы %d мс, АЦП %d мс, кадры %d мс",
             INPUTS_PERIOD_MS, ANALOG_PERIOD_MS, CAN_PERIOD_FAST_MS);
}
