// ============================================================================
//  inputs_analog.c — чтение ADS1115 (4 аналоговых входа).
//
//  Работаем одиночными преобразованиями (single-shot) по кругу: запустили
//  канал — на следующем тике забрали результат. Так задача не спит по 10 мс
//  в ожидании преобразования, а полный круг по четырём каналам занимает
//  4 × ANALOG_PERIOD_MS (при 25 мс — 100 мс, для датчиков это с запасом).
//
//  Усиление ±4.096 В: после делителя 5.81 на модуль приходит не больше 2.5 В
//  (14.5 В в бортсети), поэтому вход не насыщается, а шаг получается 125 мкВ,
//  то есть на контакте разъёма — 0.73 мВ.
// ============================================================================
#include "inputs_analog.h"

#include <string.h>

#include "driver/i2c_master.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "board_pins.h"
#include "config.h"

static const char *TAG = "analog";

// Регистры ADS1115
#define ADS1115_REG_CONVERSION  0x00
#define ADS1115_REG_CONFIG      0x01

// Поля регистра конфигурации
#define ADS1115_OS_START        (1u << 15)
#define ADS1115_MUX_SINGLE(n)   ((uint16_t)((4 + (n)) << 12))   // 100…111 — AINn к GND
#define ADS1115_PGA_4V096       (1u << 9)                       // ±4.096 В
#define ADS1115_MODE_SINGLE     (1u << 8)
#define ADS1115_DR_128SPS       (4u << 5)
#define ADS1115_COMP_DISABLE    0x0003

static i2c_master_bus_handle_t s_bus1;
static i2c_master_dev_handle_t s_ads;

static uint16_t s_mv[AIN_COUNT];
static int16_t  s_raw[AIN_COUNT];
static uint8_t  s_next_channel;
static bool     s_pending[AIN_COUNT];    // по каналу запущено преобразование
static bool     s_valid[AIN_COUNT];      // по каналу есть хотя бы один отсчёт
static bool     s_ok;
static uint8_t  s_errors;

static uint16_t build_config(uint8_t channel)
{
    return (uint16_t)(ADS1115_OS_START |
                      ADS1115_MUX_SINGLE(channel) |
                      ADS1115_PGA_4V096 |
                      ADS1115_MODE_SINGLE |
                      ADS1115_DR_128SPS |
                      ADS1115_COMP_DISABLE);
}

static esp_err_t write_config(uint16_t value)
{
    uint8_t buf[3] = {
        ADS1115_REG_CONFIG,
        (uint8_t)(value >> 8),
        (uint8_t)(value & 0xFF),
    };
    return i2c_master_transmit(s_ads, buf, sizeof(buf), I2C_TIMEOUT_MS);
}

static esp_err_t read_conversion(int16_t *out)
{
    const uint8_t reg = ADS1115_REG_CONVERSION;
    uint8_t rx[2] = {0, 0};

    esp_err_t err = i2c_master_transmit_receive(s_ads, &reg, 1, rx, sizeof(rx), I2C_TIMEOUT_MS);
    if (err != ESP_OK)
        return err;

    *out = (int16_t)((rx[0] << 8) | rx[1]);
    return ESP_OK;
}

// Перевод кода АЦП в милливольты на контакте разъёма.
//   мВ = код × 125 мкВ × 5.81 / 1000
// Считаем в целом виде, чтобы не тащить в прошивку плавающую точку:
// коэффициент делителя хранится умноженным на 100.
static uint16_t code_to_mv(int16_t code)
{
    if (code < 0)
        code = 0;   // одиночное включение не бывает отрицательным: это шум/сбой
    int64_t uv_at_pin = (int64_t)code * ANALOG_ADC_LSB_UV;              // мкВ на входе модуля
    int64_t mv_at_connector = uv_at_pin * ANALOG_DIVIDER_RATIO_X100 /
                              (1000LL * 100LL);                          // мВ на контакте разъёма
    if (mv_at_connector > 65535)
        mv_at_connector = 65535;
    return (uint16_t)mv_at_connector;
}

esp_err_t inputs_analog_init(void)
{
    memset(s_mv, 0, sizeof(s_mv));
    memset(s_raw, 0, sizeof(s_raw));
    memset(s_pending, 0, sizeof(s_pending));
    memset(s_valid, 0, sizeof(s_valid));
    s_next_channel = 0;
    s_ok = false;
    s_errors = 0;

    i2c_master_bus_config_t bus_cfg = {
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .i2c_port = I2C_NUM_0,
        .scl_io_num = PIN_I2C1_SCL,
        .sda_io_num = PIN_I2C1_SDA,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    esp_err_t err = i2c_new_master_bus(&bus_cfg, &s_bus1);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "шина I2C-1 не поднялась: %s", esp_err_to_name(err));
        return err;
    }

    i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = I2C1_ADDR_ADS1115,
        .scl_speed_hz = I2C_FREQ_HZ,
    };
    err = i2c_master_bus_add_device(s_bus1, &dev_cfg, &s_ads);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "ADS1115 не добавлен на шину: %s", esp_err_to_name(err));
        return err;
    }

    // Пробный запуск преобразования: если модуль не отвечает, узнаем сразу,
    // а не по «нулевым» датчикам на приборке.
    err = write_config(build_config(0));
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "ADS1115 (0x%02X) не ответил: %s — аналоговые датчики недостоверны",
                 I2C1_ADDR_ADS1115, esp_err_to_name(err));
        return err;
    }

    s_ok = true;
    s_next_channel = 0;
    ESP_LOGI(TAG, "ADS1115 найден, усиление ±4.096 В, делитель 5.81");
    return ESP_OK;
}

void inputs_analog_update(void)
{
    uint8_t channel = s_next_channel;

    // 1. Забираем результат предыдущего канала (преобразование уже закончилось:
    //    при 128 выб/с оно занимает 7.8 мс, а пауза между вызовами — 25 мс).
    if (s_pending[channel]) {
        int16_t code = 0;
        esp_err_t err = read_conversion(&code);
        if (err == ESP_OK) {
            s_raw[channel] = code;
            const uint16_t mv = code_to_mv(code);
            if (!s_valid[channel]) {
                s_mv[channel] = mv;
                s_valid[channel] = true;
            } else {
                // Сглаживание: датчики медленные, а помех в машине много.
                // Новая точка берётся с весом 1/4.
                s_mv[channel] = (uint16_t)((3u * s_mv[channel] + mv) / 4u);
            }
        } else {
            if (s_errors < 255) ++s_errors;
            s_ok = false;
        }
        s_pending[channel] = false;
    }

    // 2. Запускаем следующий канал.
    s_next_channel = (uint8_t)((s_next_channel + 1) % AIN_COUNT);
    esp_err_t err = write_config(build_config(s_next_channel));
    if (err != ESP_OK) {
        if (s_errors < 255) ++s_errors;
        s_ok = false;
    } else {
        s_pending[s_next_channel] = true;
        s_ok = true;
    }
}

uint16_t analog_mv(uint8_t channel)
{
    if (channel >= AIN_COUNT)
        return 0;
    return s_mv[channel];
}

int16_t analog_raw(uint8_t channel)
{
    if (channel >= AIN_COUNT)
        return 0;
    return s_raw[channel];
}

bool inputs_analog_ok(void)
{
    return s_ok;
}

uint8_t inputs_analog_errors(void)
{
    return s_errors;
}
