// ============================================================================
//  inputs_digital.c — чтение дискретных входов DIN_1…DIN_23.
//
//  DIN_1…DIN_15  — выводы ESP32, активный низкий уровень.
//  DIN_16…DIN_23 — PCF8574 по I2C-2. У PCF8574 вход тоже активен низким
//                  уровнем; своих подтяжек у микросхемы почти нет (слабый
//                  источник 100 мкА), поэтому на плате на каждом канале стоит
//                  резистор 10 кОм на +3.3 В — он и держит линию.
//
//  Антидребезг: состояние входа меняется только после того, как новый уровень
//  продержался заданное число опросов. Дребезг контактов реле и выключателей
//  на 12 В с оптопарой короткий, но при опросе 50 Гц без фильтра в кадры
//  попадали бы «дребезжащие» лампы поворотников и стопов.
//
//  ВНИМАНИЕ К ПЛАТЕ: линия SDA шины I2C-2 сидит на GPIO12 (strapping MTDI).
//  Внешняя подтяжка 4.7 кОм на этой линии (R3) не даст модулю стартовать,
//  поэтому её не запаивают, а подтяжку включаем программно — здесь для этого
//  задан enable_internal_pullup.
// ============================================================================
#include "inputs_digital.h"

#include <string.h>

#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "esp_log.h"

#include "board_pins.h"
#include "config.h"
#include "vehicle_signals.h"

static const char *TAG = "digital";

// Выводы DIN_1…DIN_15 по порядку (индекс 0 — DIN_1).
static const gpio_num_t k_din_pins[DIN_DIRECT_COUNT] = {
    PIN_DIN_1,  PIN_DIN_2,  PIN_DIN_3,  PIN_DIN_4,  PIN_DIN_5,
    PIN_DIN_6,  PIN_DIN_7,  PIN_DIN_8,  PIN_DIN_9,  PIN_DIN_10,
    PIN_DIN_11, PIN_DIN_12, PIN_DIN_13, PIN_DIN_14, PIN_DIN_15,
};

// Выводы, где внутреннюю подтяжку включить нельзя (только вход, без pull-up).
static bool pin_has_internal_pullup(gpio_num_t pin)
{
    return !(pin == GPIO_NUM_34 || pin == GPIO_NUM_35 ||
             pin == GPIO_NUM_36 || pin == GPIO_NUM_39);
}

#define DEFAULT_DEBOUNCE_MS 30

static uint8_t  s_debounce_samples[DIN_CHANNELS + 1];   // индекс — DIN_n
static bool     s_raw[DIN_CHANNELS + 1];
static bool     s_stable[DIN_CHANNELS + 1];
static uint8_t  s_counter[DIN_CHANNELS + 1];
static uint16_t s_bitmap_direct;
static uint8_t  s_bitmap_pcf;
static bool     s_pcf_ok;
static uint8_t  s_i2c_errors;

static i2c_master_bus_handle_t s_bus2;
static i2c_master_dev_handle_t s_pcf;

// Период опроса нужен, чтобы переводить миллисекунды антидребезга в число
// опросов. Период задаётся в config.h и одинаков для всей прошивки.
static uint8_t debounce_samples_for(vehicle_signal_id_t id)
{
    const vehicle_signal_t *sig = vehicle_signal(id);
    uint16_t ms = sig->debounce_ms ? sig->debounce_ms : DEFAULT_DEBOUNCE_MS;
    uint16_t samples = (uint16_t)((ms + INPUTS_PERIOD_MS - 1) / INPUTS_PERIOD_MS);
    if (samples < 1) samples = 1;
    if (samples > 250) samples = 250;
    return (uint8_t)samples;
}

// Антидребезг для каждого входа берём из таблицы проводов: у стоп-сигналов
// и поворотников он короткий, у ламп-индикаторов может быть длиннее.
static void fill_debounce_from_signals(void)
{
    const vehicle_signal_t *list = vehicle_signals();
    for (size_t i = 0; i < vehicle_signals_count(); ++i) {
        const vehicle_signal_t *s = &list[i];
        if ((s->source == SRC_DIN || s->source == SRC_PCF) &&
            s->channel >= 1 && s->channel <= DIN_CHANNELS) {
            s_debounce_samples[s->channel] = debounce_samples_for(s->id);
        }
    }
    for (uint8_t ch = 1; ch <= DIN_CHANNELS; ++ch) {
        if (s_debounce_samples[ch] == 0)
            s_debounce_samples[ch] = debounce_samples_for(SIG_NONE);
    }
}

static esp_err_t init_direct_inputs(void)
{
    // Делим выводы на две группы: там, где внутренняя подтяжка есть,
    // включаем её (добавка к внешним 10 кОм на плате), на выводах 34/35/36/39
    // подтяжек внутри чипа нет — им хватает внешних резисторов.
    uint64_t mask_with_pullup = 0;
    uint64_t mask_input_only = 0;

    for (int i = 0; i < DIN_DIRECT_COUNT; ++i) {
        if (pin_has_internal_pullup(k_din_pins[i]))
            mask_with_pullup |= (1ULL << k_din_pins[i]);
        else
            mask_input_only |= (1ULL << k_din_pins[i]);
    }

    gpio_config_t cfg_with = {
        .pin_bit_mask = mask_with_pullup,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config_t cfg_only = {
        .pin_bit_mask = mask_input_only,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };

    esp_err_t err = ESP_OK;
    if (mask_with_pullup) {
        err = gpio_config(&cfg_with);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "не удалось настроить входы DIN_1…DIN_15: %s",
                     esp_err_to_name(err));
            return err;
        }
    }
    if (mask_input_only) {
        err = gpio_config(&cfg_only);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "не удалось настроить входы DIN_1…DIN_15: %s",
                     esp_err_to_name(err));
            return err;
        }
    }
    return err;
}

static esp_err_t init_pcf8574(void)
{
    i2c_master_bus_config_t bus_cfg = {
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .i2c_port = I2C_NUM_1,
        .scl_io_num = PIN_I2C2_SCL,
        .sda_io_num = PIN_I2C2_SDA,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    esp_err_t err = i2c_new_master_bus(&bus_cfg, &s_bus2);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "шина I2C-2 не поднялась: %s", esp_err_to_name(err));
        return err;
    }

    i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = I2C2_ADDR_PCF8574,
        .scl_speed_hz = I2C_FREQ_HZ,
    };
    err = i2c_master_bus_add_device(s_bus2, &dev_cfg, &s_pcf);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "PCF8574 не добавлен на шину: %s", esp_err_to_name(err));
        return err;
    }

    // Проверяем связь сразу: читаем байт состояния входов.
    uint8_t value = 0xFF;
    err = i2c_master_receive(s_pcf, &value, 1, I2C_TIMEOUT_MS);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "PCF8574 (0x%02X) не ответил: %s — входы DIN_16…DIN_23 недостоверны",
                 I2C2_ADDR_PCF8574, esp_err_to_name(err));
        return err;
    }
    ESP_LOGI(TAG, "PCF8574 найден, входы DIN_16…DIN_23 = 0x%02X", value);
    return ESP_OK;
}

esp_err_t inputs_digital_init(void)
{
    memset(s_raw, 0, sizeof(s_raw));
    memset(s_stable, 0, sizeof(s_stable));
    memset(s_counter, 0, sizeof(s_counter));
    memset(s_debounce_samples, 0, sizeof(s_debounce_samples));
    fill_debounce_from_signals();

    esp_err_t err = init_direct_inputs();
    if (err != ESP_OK)
        return err;

    err = init_pcf8574();
    s_pcf_ok = (err == ESP_OK);
    return err;
}

static void apply_debounce(uint8_t ch)
{
    if (s_raw[ch] == s_stable[ch]) {
        s_counter[ch] = 0;
        return;
    }
    if (s_counter[ch] < 255)
        ++s_counter[ch];
    if (s_counter[ch] >= s_debounce_samples[ch]) {
        s_stable[ch] = s_raw[ch];
        s_counter[ch] = 0;
    }
}

void inputs_digital_update(void)
{
    // --- DIN_1…DIN_15 напрямую ---
    uint16_t direct = 0;
    for (int i = 0; i < DIN_DIRECT_COUNT; ++i) {
        // Активный низкий уровень: 0 на выводе = сигнал есть.
        bool present = (gpio_get_level(k_din_pins[i]) == 0);
        if (present)
            direct |= (uint16_t)(1u << i);
        s_raw[i + 1] = present;
        apply_debounce((uint8_t)(i + 1));
    }
    s_bitmap_direct = direct;

    // --- DIN_16…DIN_23 через PCF8574 ---
    uint8_t pcf = 0xFF;
    esp_err_t err = i2c_master_receive(s_pcf, &pcf, 1, I2C_TIMEOUT_MS);
    if (err != ESP_OK) {
        if (s_i2c_errors < 255) ++s_i2c_errors;
        s_pcf_ok = false;
        // Значения не трогаем: держим последние достоверные, чтобы лампы
        // не моргали из-за случайного сбоя I2C. Признак недостоверности
        // виден в диагностике приборки по счётчику ошибок шины.
        return;
    }
    s_pcf_ok = true;
    s_bitmap_pcf = (uint8_t)~pcf;

    for (int i = 0; i < DIN_PCF_COUNT; ++i) {
        bool present = ((pcf >> i) & 1u) == 0;    // активный низкий уровень
        s_raw[DIN_DIRECT_COUNT + i + 1] = present;
        apply_debounce((uint8_t)(DIN_DIRECT_COUNT + i + 1));
    }
}

bool din_signal(uint8_t channel)
{
    if (channel < 1 || channel > DIN_CHANNELS)
        return false;
    if (channel > DIN_DIRECT_COUNT && !s_pcf_ok && s_i2c_errors > 0)
        return false;   // входы расширителя недостоверны — сигнала не показываем
    return s_stable[channel];
}

bool din_raw(uint8_t channel)
{
    if (channel < 1 || channel > DIN_CHANNELS)
        return false;
    return s_raw[channel];
}

uint16_t din_bitmap_direct(void)
{
    return s_bitmap_direct;
}

uint8_t din_bitmap_pcf(void)
{
    return s_bitmap_pcf;
}

bool inputs_digital_pcf_ok(void)
{
    return s_pcf_ok;
}

uint8_t inputs_digital_i2c_errors(void)
{
    return s_i2c_errors;
}

int inputs_digital_pin(uint8_t channel)
{
    if (channel < 1 || channel > DIN_DIRECT_COUNT)
        return (int)GPIO_NUM_NC;      // входы 16…23 идут через PCF8574, у них нет вывода ESP32
    return (int)k_din_pins[channel - 1];
}
