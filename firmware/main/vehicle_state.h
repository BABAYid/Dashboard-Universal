// ============================================================================
//  vehicle_state.h — состояние машины: то, что уходит в кадры CAN.
//
//  Слой между «железом» (inputs_*) и протоколом (can_protocol.*): здесь
//  частота превращается в километры в час, милливольты — в проценты топлива
//  и градусы, отдельные провода — в битовые маски ламп и режим АКПП.
//
//  Задача входов пишет состояние, задача CAN его читает — доступ закрыт
//  мьютексом, чтобы в кадр не попала половина старого и половина нового.
// ============================================================================
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "can_protocol.h"

typedef struct {
    uint8_t         speed_kmh;
    uint16_t        rpm;
    proto_lights_t  lights;
    proto_sensors_t sensors;
    proto_gearbox_t gearbox;
    bool            gas_mode;
    bool            gas_sensor_valid;
    uint16_t        gas_sensor_mv;

    // --- протокол 1.3 ---
    // Климат: пока блок сбора не читает родную панель, valid = false,
    // и приборка показывает «климат — нет данных» вместо выдуманных цифр.
    proto_climate_t    climate;
    // GPS: пока NMEA не разбирается, кадры уходят с нулями и fix = false.
    proto_gps_pos_t    gps_pos;
    proto_gps_motion_t gps_motion;

    // Отладочное и диагностическое: в кадры не уходит, но видно в консоли.
    bool            ignition_on;
    uint32_t        uptime_sec;
} vehicle_state_t;

void vehicle_state_init(void);

// Пересчёт состояния из входов. Вызывать каждые STATE_PERIOD_MS.
void vehicle_state_update(void);

// Копия состояния для задачи CAN. Значение возвращается по копии: указатель
// на внутреннюю структуру не отдаём, иначе задача CAN читала бы её во время
// обновления.
vehicle_state_t vehicle_state_get(void);

// Включено ли зажигание (для решения про сон). Если провод зажигания не
// назначен — всегда true.
bool vehicle_state_ignition_on(void);
