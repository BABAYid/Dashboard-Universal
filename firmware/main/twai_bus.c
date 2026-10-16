// ============================================================================
//  twai_bus.c — отправка кадров через TWAI.
//
//  Про режим работы: шина двухузловая (ESP32 + приборка). Если приборки на
//  шине нет (стенд, обрыв провода), кадры не подтверждаются, контроллер
//  набирает ошибки и уходит в bus-off. Это не авария: twai_bus_poll()
//  поднимает шину заново, а счётчик ошибок уходит в кадр 0x7F0 — по нему
//  в диагностике приборки видно, что связь была не в порядке.
// ============================================================================
#include "twai_bus.h"

#include "driver/twai.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "board_pins.h"
#include "can_protocol.h"

static const char *TAG = "can";

static uint8_t  s_errors;
static uint32_t s_sent;
static bool     s_recovering;

esp_err_t twai_bus_init(void)
{
    twai_general_config_t general = TWAI_GENERAL_CONFIG_DEFAULT(
        PIN_CAN_TX, PIN_CAN_RX, TWAI_MODE_NORMAL);
    // Очередь на отправку: кадров немного (около 90 в секунду), но пусть
    // будет запас, чтобы задача не ждала освобождения очереди.
    general.tx_queue_len = 8;
    general.rx_queue_len = 4;

    twai_timing_config_t timing = TWAI_TIMING_CONFIG_500KBITS();
    twai_filter_config_t filter = TWAI_FILTER_CONFIG_ACCEPT_ALL();

    esp_err_t err = twai_driver_install(&general, &timing, &filter);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "драйвер TWAI не установился: %s", esp_err_to_name(err));
        return err;
    }
    err = twai_start();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "шина CAN не запустилась: %s", esp_err_to_name(err));
        twai_driver_uninstall();
        return err;
    }

    s_errors = 0;
    s_sent = 0;
    s_recovering = false;
    ESP_LOGI(TAG, "CAN поднят: %d кбит/с, TX=GPIO%d, RX=GPIO%d",
             CAN_BITRATE_KBPS, (int)PIN_CAN_TX, (int)PIN_CAN_RX);
    return ESP_OK;
}

bool twai_bus_send(uint32_t id, const uint8_t data[8])
{
    twai_message_t msg = {
        .identifier = id,
        .data_length_code = CAN_FRAME_BYTES,
        .extd = 0,          // классический CAN, 11-битный ID
        .rtr = 0,
        .ss = 0,
        .self = 0,
        .dlc_non_comp = 0,
    };
    for (int i = 0; i < CAN_FRAME_BYTES; ++i)
        msg.data[i] = data[i];

    esp_err_t err = twai_transmit(&msg, pdMS_TO_TICKS(5));
    if (err != ESP_OK) {
        if (err == ESP_ERR_TIMEOUT || err == ESP_FAIL) {
            // Очередь переполнена или шина в плохом состоянии — считаем как
            // ошибку связи, кадр потерян (для 0x100/0x200 это допустимо:
            // следующий придёт через 50 мс, а приборка следит за свежестью).
            if (s_errors < 255) ++s_errors;
        }
        return false;
    }
    ++s_sent;
    return true;
}

void twai_bus_poll(void)
{
    twai_status_info_t info;
    if (twai_get_status_info(&info) != ESP_OK)
        return;

    // Диагностика: сколько ошибок накопила шина. Значение из железа,
    // поэтому берём максимум из своего счётчика и аппаратного.
    if (info.bus_error_count > s_errors)
        s_errors = (info.bus_error_count > 255) ? 255 : (uint8_t)info.bus_error_count;

    if (info.state == TWAI_STATE_BUS_OFF) {
        ESP_LOGW(TAG, "шина ушла в bus-off (нет подтверждения кадров) — поднимаю заново");
        if (s_errors < 255) ++s_errors;
        twai_initiate_recovery();
        s_recovering = true;
    } else if (s_recovering && info.state == TWAI_STATE_STOPPED) {
        if (twai_start() == ESP_OK) {
            ESP_LOGI(TAG, "шина снова в работе");
            s_recovering = false;
        }
    }
}

uint8_t twai_bus_error_count(void)
{
    return s_errors;
}

uint32_t twai_bus_frames_sent(void)
{
    return s_sent;
}

const char *twai_bus_state_name(void)
{
    twai_status_info_t info;
    if (twai_get_status_info(&info) != ESP_OK)
        return "нет данных";
    switch (info.state) {
    case TWAI_STATE_STOPPED: return "остановлена";
    case TWAI_STATE_RUNNING: return "работает";
    case TWAI_STATE_BUS_OFF: return "bus-off";
    case TWAI_STATE_RECOVERING: return "восстановление";
    default: return "неизвестно";
    }
}
