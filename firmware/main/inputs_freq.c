// ============================================================================
//  inputs_freq.c — измерение частоты на дискретных входах.
//
//  Обработчик прерывания короткий: только запомнить время прихода импульса.
//  Всё остальное (медиана периодов, перевод в герцы, таймаут) — в задаче.
//
//  Фильтр коротких импульсов: период меньше FREQ_MIN_PERIOD_US считается
//  помехой от зажигания и не учитывается. Наводки в бортсети дают пачки
//  коротких импульсов, без этого фильтра спидометр «дёргался» бы на месте.
// ============================================================================
#include "inputs_freq.h"

#include <string.h>

#include "driver/gpio.h"
#include "esp_attr.h"
#include "esp_log.h"
#include "esp_timer.h"

#include "board_pins.h"
#include "config.h"
#include "inputs_digital.h"
#include "vehicle_signals.h"

static const char *TAG = "freq";

// Частота выше 20 кГц для спидометра и тахометра не встречается, а оптопара
// PC817 с подтяжкой 10 кОм её всё равно уже не пропускает.
#define FREQ_MIN_PERIOD_US      50

typedef struct {
    uint8_t   channel;                 // DIN_n, на котором меряем частоту
    gpio_num_t pin;
    uint8_t   slot;                    // индекс для обработчика прерывания
} freq_channel_t;

static freq_channel_t s_channels[FREQ_CHANNELS_MAX];
static int      s_count;

static volatile uint32_t s_last_us[FREQ_CHANNELS_MAX];
static volatile uint32_t s_period_us[FREQ_CHANNELS_MAX];
static volatile uint32_t s_pulses[FREQ_CHANNELS_MAX];
static uint32_t s_median_buf[FREQ_CHANNELS_MAX][3];
static uint8_t  s_median_pos[FREQ_CHANNELS_MAX];
static float    s_hz[FREQ_CHANNELS_MAX];

static void IRAM_ATTR freq_isr(void *arg)
{
    const uint8_t slot = *(const uint8_t *)arg;
    const uint32_t now = (uint32_t)esp_timer_get_time();
    const uint32_t period = now - s_last_us[slot];

    if (period >= FREQ_MIN_PERIOD_US) {
        s_period_us[slot] = period;
        s_last_us[slot] = now;
    }
    // Считаем все импульсы: по ним видно, приходит ли сигнал вообще.
    s_pulses[slot]++;
}

static int slot_for_channel(uint8_t channel)
{
    for (int i = 0; i < s_count; ++i) {
        if (s_channels[i].channel == channel)
            return i;
    }
    return -1;
}

esp_err_t inputs_freq_init(void)
{
    memset(s_channels, 0, sizeof(s_channels));
    memset(s_median_buf, 0, sizeof(s_median_buf));
    memset(s_hz, 0, sizeof(s_hz));
    s_count = 0;

    // Собираем из таблицы проводов всё, что помечено как частотный вход.
    const vehicle_signal_t *list = vehicle_signals();
    for (size_t i = 0; i < vehicle_signals_count(); ++i) {
        const vehicle_signal_t *sig = &list[i];
        if (sig->source != SRC_FREQ)
            continue;
        if (s_count >= FREQ_CHANNELS_MAX) {
            ESP_LOGW(TAG, "частотных входов больше %d — сигнал «%s» пропущен",
                     FREQ_CHANNELS_MAX, sig->name);
            continue;
        }
        const int pin = inputs_digital_pin(sig->channel);
        if (pin < 0) {
            ESP_LOGW(TAG, "«%s»: DIN_%u нельзя использовать как частотный вход",
                     sig->name, (unsigned)sig->channel);
            continue;
        }
        s_channels[s_count].channel = sig->channel;
        s_channels[s_count].pin = (gpio_num_t)pin;
        s_channels[s_count].slot = (uint8_t)s_count;
        ++s_count;

        ESP_LOGI(TAG, "частотный вход «%s»: DIN_%u (GPIO %d)",
                 sig->name, (unsigned)sig->channel, pin);
    }

    if (s_count == 0) {
        ESP_LOGW(TAG, "частотных входов нет: скорость и обороты будут нулевыми "
                      "(таблица проводов ещё не заполнена)");
        return ESP_OK;
    }

    esp_err_t err = gpio_install_isr_service(0);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(TAG, "служба прерываний не поднялась: %s", esp_err_to_name(err));
        return err;
    }

    for (int i = 0; i < s_count; ++i) {
        gpio_config_t cfg = {
            .pin_bit_mask = (1ULL << s_channels[i].pin),
            .mode = GPIO_MODE_INPUT,
            .pull_up_en = GPIO_PULLUP_ENABLE,      // на 34/35/36/39 внутренней нет — сработает внешняя
            .pull_down_en = GPIO_PULLDOWN_DISABLE,
            .intr_type = GPIO_INTR_NEGEDGE,        // сигнал 12 В сажает вход на землю
        };
        err = gpio_config(&cfg);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "вход GPIO %d не настроен: %s", (int)s_channels[i].pin,
                     esp_err_to_name(err));
            return err;
        }
        err = gpio_isr_handler_add(s_channels[i].pin, freq_isr, &s_channels[i].slot);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "прерывание на GPIO %d не подключено: %s",
                     (int)s_channels[i].pin, esp_err_to_name(err));
            return err;
        }
    }
    return ESP_OK;
}

// Медиана трёх последних периодов: одиночный «лишний» импульс от помехи
// не должен дёргать стрелку спидометра.
static uint32_t median3(uint32_t *buf)
{
    uint32_t a = buf[0], b = buf[1], c = buf[2];
    if (a > b) { uint32_t t = a; a = b; b = t; }
    if (b > c) { uint32_t t = b; b = c; c = t; }
    if (a > b) { uint32_t t = a; a = b; b = t; }
    return b;
}

void inputs_freq_update(void)
{
    const uint32_t now = (uint32_t)esp_timer_get_time();

    for (int i = 0; i < s_count; ++i) {
        const uint32_t period = s_period_us[i];
        const uint32_t last = s_last_us[i];

        // Период нулевой — импульсов не было ни разу.
        if (period == 0) {
            s_hz[i] = 0.0f;
            continue;
        }

        // Импульсов нет дольше таймаута — считаем частоту нулевой
        // (машина стоит: скорость 0, обороты 0).
        if ((uint32_t)(now - last) > (uint32_t)(FREQ_TIMEOUT_MS * 1000u)) {
            s_hz[i] = 0.0f;
            continue;
        }

        s_median_buf[i][s_median_pos[i]] = period;
        s_median_pos[i] = (uint8_t)((s_median_pos[i] + 1) % 3);

        const uint32_t filtered = median3(s_median_buf[i]);
        if (filtered > 0)
            s_hz[i] = 1000000.0f / (float)filtered;
    }
}

float inputs_freq_hz(uint8_t channel)
{
    const int slot = slot_for_channel(channel);
    if (slot < 0)
        return 0.0f;
    return s_hz[slot];
}

uint32_t inputs_freq_pulses(uint8_t channel)
{
    const int slot = slot_for_channel(channel);
    if (slot < 0)
        return 0;
    return s_pulses[slot];
}

int inputs_freq_channel_count(void)
{
    return s_count;
}
