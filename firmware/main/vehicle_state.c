// ============================================================================
//  vehicle_state.c — пересчёт проводов машины в значения протокола.
//
//  Правило, которое здесь соблюдается везде: НЕНАЗНАЧЕННЫЙ сигнал не должен
//  выглядеть на приборке как настоящее измерение. Поэтому:
//    • дискретные сигналы без провода дают 0 (лампа не горит) — это безопасно;
//    • аналоговые датчики без провода дают нейтральное значение из config.h
//      (0 % топлива зажгло бы лампу «бак пуст», 0 В — лампу зарядки,
//       0 °C наружной температуры — предупреждение «ГОЛОЛЁД»).
// ============================================================================
#include "vehicle_state.h"

#include <math.h>
#include <string.h>

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include "config.h"
#include "inputs_analog.h"
#include "inputs_digital.h"
#include "inputs_freq.h"
#include "vehicle_signals.h"

static const char *TAG = "state";

static vehicle_state_t   s_state;
static SemaphoreHandle_t s_lock;
static uint32_t          s_start_uptime_ms;
#if IGNITION_OFF_TO_SLEEP_S > 0
// Нужны только когда сон по зажиганию включён (см. config.h).
static bool              s_ignition_lost;
static uint32_t          s_ignition_off_since_ms;
#endif
static uint8_t           s_last_gear_mode = 2;   // N — если селектор ещё не читается

// ---------------------------------------------------------------------------
//  Доступ к дискретным сигналам
// ---------------------------------------------------------------------------
//  Для проводов, которые замыкаются на массу (ручник, давление масла, ремень,
//  концевики), на провод ставится внешняя подтяжка 4.7 кОм на +12 В
//  (см. vehicle_signals.h). Тогда вход платы ведёт себя так:
//      провод замкнут на массу (сигнал ЕСТЬ)   → светодиод оптопары погашен → вход = 1
//      провод отпущен       (сигнала НЕТ)     → по подтяжке течёт ток     → вход = 0
//  То есть состояние входа получается обратным смыслу сигнала, и флаг
//  SIG_FLAG_GROUND_SWITCHED в таблице проводов как раз это и означает.
static bool sig_on(vehicle_signal_id_t id)
{
    const vehicle_signal_t *s = vehicle_signal(id);
    if (s->source != SRC_DIN && s->source != SRC_PCF)
        return false;

    const bool input_active = din_signal(s->channel);
    if (s->flags & SIG_FLAG_GROUND_SWITCHED)
        return !input_active;
    return input_active;
}

static bool sig_assigned(vehicle_signal_id_t id)
{
    return vehicle_signal(id)->source != SRC_NONE;
}

// ---------------------------------------------------------------------------
//  Аналоговые датчики: милливольты → проценты и градусы
// ---------------------------------------------------------------------------
//  Линейная интерполяция по двум точкам калибровки. Для терморезисторов
//  зависимость нелинейная, но две точки дают правильные «холодно» и «горячо»,
//  а точную кривую добавим, когда будут замеры с машины.
static float map_two_points(int32_t value, int32_t v_at_a, int32_t out_at_a,
                            int32_t v_at_b, int32_t out_at_b)
{
    if (v_at_a == v_at_b)
        return (float)out_at_a;
    const float k = (float)(out_at_b - out_at_a) / (float)(v_at_b - v_at_a);
    return (float)out_at_a + k * (float)(value - v_at_a);
}

static uint8_t read_fuel_percent(void)
{
    if (!sig_assigned(SIG_FUEL_LEVEL) || !inputs_analog_ok())
        return PLACEHOLDER_FUEL_PCT;

    const uint8_t channel = vehicle_signal(SIG_FUEL_LEVEL)->channel;
    const int32_t mv = analog_mv(channel);
    float pct = map_two_points(mv, FUEL_EMPTY_MV, FUEL_EMPTY_PCT,
                               FUEL_FULL_MV, FUEL_FULL_PCT);
    return proto_clamp_u8((int32_t)lroundf(pct), 0, 100);
}

static uint8_t read_engine_temp(void)
{
    if (!sig_assigned(SIG_ENGINE_TEMP) || !inputs_analog_ok())
        return PLACEHOLDER_ENGINE_TEMP_C;

    const uint8_t channel = vehicle_signal(SIG_ENGINE_TEMP)->channel;
    const int32_t mv = analog_mv(channel);
    float temp = map_two_points(mv, TEMP_COLD_MV, TEMP_COLD_C,
                                TEMP_HOT_MV, TEMP_HOT_C);
    return proto_clamp_u8((int32_t)lroundf(temp), TEMP_MIN_C, TEMP_MAX_C);
}

static uint8_t read_voltage_x10(void)
{
    if (!sig_assigned(SIG_BATTERY_VOLTAGE) || !inputs_analog_ok())
        return PLACEHOLDER_VOLTAGE_X10;

    const uint8_t channel = vehicle_signal(SIG_BATTERY_VOLTAGE)->channel;
    const int32_t mv = analog_mv(channel);
    // Пересчёт по калибровке: что показал АЦП против эталонного напряжения.
    int32_t volts_x10 = (int32_t)(((int64_t)mv * VOLTAGE_CAL_MV_AT_12V) /
                                  (VOLTAGE_ADC_MV_AT_CAL * 100LL));
    return proto_clamp_u8(volts_x10, 0, 255);
}

static int8_t read_outside_temp(void)
{
    if (!sig_assigned(SIG_OUTSIDE_TEMP) || !inputs_analog_ok())
        return PLACEHOLDER_OUTSIDE_TEMP_C;

    const uint8_t channel = vehicle_signal(SIG_OUTSIDE_TEMP)->channel;
    const int32_t mv = analog_mv(channel);
    const float temp = map_two_points(mv, OUTSIDE_TEMP_COLD_MV, OUTSIDE_TEMP_COLD_C,
                                      OUTSIDE_TEMP_HOT_MV, OUTSIDE_TEMP_HOT_C);

    int32_t value = (int32_t)lroundf(temp);
    if (value < OUTSIDE_TEMP_MIN_C) value = OUTSIDE_TEMP_MIN_C;
    if (value > OUTSIDE_TEMP_MAX_C) value = OUTSIDE_TEMP_MAX_C;
    return (int8_t)value;
}

// ---------------------------------------------------------------------------
//  Датчик уровня газа: сырое напряжение 0…5 В уходит в кадр как есть,
//  проценты по нему считает приборка (так кривую можно менять в настройках
//  панели, не перепрошивая блок).
// ---------------------------------------------------------------------------
#define GAS_SENSOR_MIN_MV   30      // ниже — обрыв или короткое замыкание
#define GAS_SENSOR_MAX_MV   5400    // выше — датчик неисправен или не тот вход

static void read_gas(uint16_t *mv, bool *valid)
{
    if (!sig_assigned(SIG_GAS_LEVEL) || !inputs_analog_ok()) {
        *mv = 0;
        *valid = false;
        return;
    }
    const uint8_t channel = vehicle_signal(SIG_GAS_LEVEL)->channel;
    const uint16_t value = analog_mv(channel);
    *mv = value;
    *valid = (value >= GAS_SENSOR_MIN_MV && value <= GAS_SENSOR_MAX_MV);
}

// ---------------------------------------------------------------------------
//  Частота → скорость, обороты, расход
// ---------------------------------------------------------------------------
static uint8_t read_speed_kmh(uint8_t previous)
{
    if (!sig_assigned(SIG_SPEED) || SPEED_IMPULSES_PER_KM <= 0)
        return 0;

    const uint8_t channel = vehicle_signal(SIG_SPEED)->channel;
    const float hz = inputs_freq_hz(channel);
    const float kmh = hz * 3600.0f / (float)SPEED_IMPULSES_PER_KM;

    uint8_t value = proto_clamp_u8((int32_t)lroundf(kmh), 0, 220);

    // Мёртвая зона: не дёргать показание из-за одного «лишнего» импульса.
    if (SPEED_HYSTERESIS_KMH > 0) {
        const int diff = (int)value - (int)previous;
        if (diff < 0) {
            if (-diff < SPEED_HYSTERESIS_KMH) value = previous;
        } else if (diff > 0) {
            if (diff < SPEED_HYSTERESIS_KMH) value = previous;
        }
    }
    return value;
}

static uint16_t read_rpm(void)
{
    if (!sig_assigned(SIG_RPM) || RPM_IMPULSES_PER_REV <= 0)
        return 0;

    const uint8_t channel = vehicle_signal(SIG_RPM)->channel;
    const float hz = inputs_freq_hz(channel);
    const float rpm = hz * 60.0f / (float)RPM_IMPULSES_PER_REV;
    return proto_clamp_u16((int32_t)lroundf(rpm), RPM_IDLE_MIN, RPM_MAX);
}

//  Расход: сигнал от ЭБУ — частота, пропорциональная потоку топлива (л/ч).
//  В кадр уходит мгновенный расход в л/100 км, как в протоколе.
static uint16_t read_fuel_rate_x10(uint8_t speed_kmh)
{
    if (!sig_assigned(SIG_FUEL_RATE) || FUEL_RATE_IMPULSES_PER_LITER <= 0)
        return 0;
    if (speed_kmh < 3)
        return 0;   // на стоянке мгновенный расход в л/100 км не определён

    const uint8_t channel = vehicle_signal(SIG_FUEL_RATE)->channel;
    const float hz = inputs_freq_hz(channel);
    const float liters_per_hour = hz * 3600.0f / (float)FUEL_RATE_IMPULSES_PER_LITER;
    const float l_per_100km = liters_per_hour / (float)speed_kmh * 100.0f;
    return proto_clamp_u16((int32_t)lroundf(l_per_100km * 10.0f), 0, 999);
}

// ---------------------------------------------------------------------------
//  АКПП: режим по селектору, передача — по проводам S1/S2
// ---------------------------------------------------------------------------
static void read_gearbox(proto_gearbox_t *g)
{
    const bool s1_assigned = sig_assigned(SIG_GEAR_S1);
    const bool s2_assigned = sig_assigned(SIG_GEAR_S2);
    const bool s1 = sig_on(SIG_GEAR_S1);
    const bool s2 = sig_on(SIG_GEAR_S2);

    uint8_t mode;
    if (sig_on(SIG_GEAR_P))      mode = 0;
    else if (sig_on(SIG_GEAR_R)) mode = 1;
    else if (sig_on(SIG_GEAR_N)) mode = 2;
    else if (sig_on(SIG_GEAR_D)) mode = 3;
    else                         mode = s_last_gear_mode;   // селектор между положениями — держим прежнее

    if (sig_assigned(SIG_GEAR_P) || sig_assigned(SIG_GEAR_R) ||
        sig_assigned(SIG_GEAR_N) || sig_assigned(SIG_GEAR_D)) {
        s_last_gear_mode = mode;
    } else {
        mode = 2;   // селектор не подключён: не показываем выдуманную передачу
    }

    // Соответствие проверено на машине (см. can_protocol_v1.2.txt):
    //   S1=ON,  S2=OFF → D1
    //   S1=ON,  S2=ON  → D2
    //   S1=OFF, S2=ON  → D3
    //   S1=OFF, S2=OFF → D4
    uint8_t gear = 0;
    if (mode == 3 && s1_assigned && s2_assigned) {
        if (s1 && !s2)      gear = 1;
        else if (s1 && s2)  gear = 2;
        else if (!s1 && s2) gear = 3;
        else                gear = 4;
    }

    const bool lock = sig_on(SIG_GEAR_LOCK);

    g->mode = mode;
    g->gear = gear;
    g->lock = lock;
    g->s1 = s1;
    g->s2 = s2;
    g->sl = lock;
}

// ---------------------------------------------------------------------------
//  Публичные функции
// ---------------------------------------------------------------------------
void vehicle_state_init(void)
{
    s_lock = xSemaphoreCreateMutex();
    memset(&s_state, 0, sizeof(s_state));
    s_start_uptime_ms = (uint32_t)(xTaskGetTickCount() * portTICK_PERIOD_MS);

    // Пока источников нет, климат и GPS отдают «нет данных»: приборка по этим
    // признакам не рисует выдуманные цифры, а пишет «—».
    s_state.climate.valid = false;
    s_state.climate.fan_level = CLIMATE_FAN_NONE;
    s_state.climate.cabin_temp_c = CLIMATE_TEMP_NONE;
    s_state.climate.evaporator_temp_c = CLIMATE_TEMP_NONE;
    s_state.gps_motion.course_x2 = GPS_VALUE_NONE;
    s_state.gps_motion.speed_kmh = GPS_VALUE_NONE;
    s_state.gps_motion.hdop_x10 = GPS_VALUE_NONE;
    s_state.gps_motion.fix = false;

    // Предупреждаем о проводах, которые плата так не прочитает.
    const vehicle_signal_t *list = vehicle_signals();
    int assigned = 0;
    for (size_t i = 0; i < vehicle_signals_count(); ++i) {
        const vehicle_signal_t *s = &list[i];
        if (s->source == SRC_NONE) {
            ESP_LOGW(TAG, "«%s»: провод не назначен — на приборке будет нейтральное значение%s%s",
                     s->name, s->note[0] ? ", " : "", s->note);
            continue;
        }
        ++assigned;
        if (s->flags & SIG_FLAG_GROUND_SWITCHED) {
            ESP_LOGW(TAG, "«%s»: провод замыкается на массу — нужна подтяжка 4.7 кОм "
                          "на +12 В (лучше от ACC), прошивка читает вход инверсно",
                     s->name);
        }
    }
    ESP_LOGI(TAG, "назначено сигналов: %d из %u", assigned,
             (unsigned)vehicle_signals_count());
}

void vehicle_state_update(void)
{
    vehicle_state_t next;

    xSemaphoreTake(s_lock, portMAX_DELAY);
    next = s_state;   // берём предыдущее как основу: аккумуляторы и «залипания» живут здесь
    xSemaphoreGive(s_lock);

    next.uptime_sec = ((uint32_t)(xTaskGetTickCount() * portTICK_PERIOD_MS) -
                       s_start_uptime_ms) / 1000u;

    // --- скорость и обороты ---
    next.speed_kmh = read_speed_kmh(next.speed_kmh);
    next.rpm = read_rpm();

    // --- лампы и свет ---
    next.lights.left_turn = sig_on(SIG_LEFT_TURN);
    next.lights.right_turn = sig_on(SIG_RIGHT_TURN);
    next.lights.high_beam = sig_on(SIG_HIGH_BEAM);
    next.lights.low_beam = sig_on(SIG_LOW_BEAM);
    next.lights.position_lights = sig_on(SIG_POSITION_LIGHTS);
    next.lights.fog_lights = sig_on(SIG_FOG_LIGHTS);
    next.lights.reverse = sig_on(SIG_REVERSE);
    next.lights.brake = sig_on(SIG_BRAKE);
    next.lights.check_engine = sig_on(SIG_CHECK_ENGINE);
    next.lights.abs = sig_on(SIG_ABS);
    next.lights.hand_brake = sig_on(SIG_HAND_BRAKE);
    next.lights.seat_belt_unfastened = sig_on(SIG_SEAT_BELT);
    next.lights.oil_pressure_alarm = sig_on(SIG_OIL_PRESSURE);

    read_gearbox(&next.gearbox);
    next.lights.gear_lock = next.gearbox.lock;

    // --- датчики ---
    next.sensors.engine_temp_c = read_engine_temp();
    next.sensors.fuel_level_pct = read_fuel_percent();
    next.sensors.voltage_x10 = read_voltage_x10();
    next.sensors.outside_temp_c = read_outside_temp();
    next.sensors.oil_pressure_alarm = next.lights.oil_pressure_alarm;
    next.sensors.fuel_rate_x10 = read_fuel_rate_x10(next.speed_kmh);

    // --- газ ---
    next.gas_mode = sig_on(SIG_GAS_MODE);
    read_gas(&next.gas_sensor_mv, &next.gas_sensor_valid);

    // --- зажигание ---
    // ACC — это «плюс 12 В» при включённом зажигании. Если провод ACC
    // замыкается на массу, в таблице проводов у него стоит флаг
    // SIG_FLAG_GROUND_SWITCHED, и его учитывает sig_on().
    if (sig_assigned(SIG_IGNITION))
        next.ignition_on = sig_on(SIG_IGNITION);
    else
        next.ignition_on = true;

    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_state = next;
    xSemaphoreGive(s_lock);
}

vehicle_state_t vehicle_state_get(void)
{
    vehicle_state_t copy;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    copy = s_state;
    xSemaphoreGive(s_lock);
    return copy;
}

bool vehicle_state_ignition_on(void)
{
#if IGNITION_OFF_TO_SLEEP_S <= 0
    // Сон по зажиганию пока не используется: провода ACC в списке нет,
    // поэтому блок работает всегда (см. config.h и firmware/README.md).
    return true;
#else
    const vehicle_state_t copy = vehicle_state_get();

    if (!sig_assigned(SIG_IGNITION))
        return true;

    const uint32_t now = (uint32_t)(xTaskGetTickCount() * portTICK_PERIOD_MS);
    if (copy.ignition_on) {
        s_ignition_lost = false;
        return true;
    }
    if (!s_ignition_lost) {
        s_ignition_lost = true;
        s_ignition_off_since_ms = now;
    }
    return (uint32_t)(now - s_ignition_off_since_ms) <
           (uint32_t)(IGNITION_OFF_TO_SLEEP_S * 1000u);
#endif
}
