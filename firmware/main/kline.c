// ============================================================================
//  kline.c — пассивный сниффер K-линии.
//
//  Железо: MC33290 (ISO 9141) + SN74LVC2T45 → UART2 (TX = GPIO17, RX = GPIO16),
//  контакт 3 разъёма X1. Передающая линия в этом режиме не используется:
//  UART TX в покое держит высокий уровень, то есть K-линия отпущена и никому
//  не мешает — можно слушать, пока по линии работает штатный сканер.
//
//  Что видно и что не видно: данные фазой обмена (10400 бод) печатаются как
//  есть. Медленная инициализация 5 бод (ей ЭБУ «будят» перед обменом) в таком
//  режиме выглядит как отдельные байты с паузами около 200 мс — по паузам её
//  и опознать. Если по дампу окажется, что нужен разбор инициализации
//  по фронтам, сюда добавится режим захвата переходов.
// ============================================================================
#include "kline.h"

#include <stdio.h>

#include "driver/uart.h"
#include "esp_log.h"
#include "esp_timer.h"

#include "board_pins.h"
#include "config.h"

static const char *TAG = "kline";

#define KLINE_UART          UART_NUM_2
#define KLINE_RX_BUF        1024
#define KLINE_CHUNK         128     // сколько байт забираем за один вызов
#define KLINE_LINE_CHARS    512
#define KLINE_GAP_US        20000   // пауза, после которой начинаем новую строку дампа

static bool     s_enabled;
static uint32_t s_bytes;
static uint32_t s_last_rx_us;

esp_err_t kline_init(void)
{
#if KLINE_ENABLED
    const uart_config_t cfg = {
        .baud_rate = KLINE_BAUD,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };

    esp_err_t err = uart_driver_install(KLINE_UART, KLINE_RX_BUF, 0, 0, NULL, 0);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "UART2 не поднялся: %s", esp_err_to_name(err));
        return err;
    }
    err = uart_param_config(KLINE_UART, &cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "UART2 не настроен: %s", esp_err_to_name(err));
        return err;
    }
    err = uart_set_pin(KLINE_UART, PIN_UART2_TX, PIN_UART2_RX,
                       UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "выводы UART2 не назначены: %s", esp_err_to_name(err));
        return err;
    }

    s_enabled = true;
    ESP_LOGW(TAG, "K-линия: включён сниффер (%d бод, только слушаем). "
                  "Запустите диагностический сканер и смотрите дамп ниже",
             KLINE_BAUD);
#else
    ESP_LOGI(TAG, "K-линия: сниффер выключен (KLINE_ENABLED = 0 в config.h)");
#endif
    return ESP_OK;
}

void kline_poll(void)
{
    if (!s_enabled)
        return;

    uint8_t buf[KLINE_CHUNK];
    const int n = uart_read_bytes(KLINE_UART, buf, sizeof(buf), 0);
    if (n <= 0)
        return;

    const uint32_t now_us = (uint32_t)esp_timer_get_time();
    const uint32_t gap_ms = (s_last_rx_us == 0)
                                ? 0
                                : (uint32_t)((now_us - s_last_rx_us) / 1000u);
    s_last_rx_us = now_us;
    s_bytes += (uint32_t)n;

    static char line[KLINE_LINE_CHARS];
    int used = 0;

    if (gap_ms >= (KLINE_GAP_US / 1000u))
        used += snprintf(line + used, sizeof(line) - (size_t)used, "пауза %u мс | ", (unsigned)gap_ms);

    for (int i = 0; i < n && used + 4 < (int)sizeof(line); ++i)
        used += snprintf(line + used, sizeof(line) - (size_t)used, "%02X ", buf[i]);

    ESP_LOGI(TAG, "K-line: %s", line);
}

bool kline_enabled(void)
{
    return s_enabled;
}

uint32_t kline_bytes_seen(void)
{
    return s_bytes;
}
