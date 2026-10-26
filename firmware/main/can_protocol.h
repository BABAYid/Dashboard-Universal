// ============================================================================
//  can_protocol.h — сборка кадров CAN по протоколу версии 1.2.
//
//  Это чистый C без зависимостей от ESP-IDF: тот же код собирается и
//  проверяется на компьютере (firmware/test/test_frames.c). Так кодировщик
//  блока сбора и разбор приборки (Dashboard/can/CanBackend.cpp) сверяются
//  по одному документу — can_protocol_v1.2.txt.
//
//  Формат: классический CAN, 11-битный ID, 8 байт, многобайтные значения —
//  старший байт первым. Скорость шины 500 кбит/с.
// ============================================================================
#pragma once

#include <stdint.h>
#include <stdbool.h>

// ---------------------------------------------------------------------------
//  Идентификаторы кадров и периоды отправки
// ---------------------------------------------------------------------------
#define CAN_ID_SPEED_RPM        0x100u   // 50 мс
#define CAN_ID_LIGHTS           0x200u   // 50 мс
#define CAN_ID_SENSORS          0x300u   // 50 мс
#define CAN_ID_GEARBOX          0x400u   // 50 мс
#define CAN_ID_GAS              0x500u   // 200 мс
#define CAN_ID_CLIMATE          0x510u   // 200 мс (протокол 1.3)
#define CAN_ID_GPS_POS          0x520u   // 500 мс (протокол 1.3)
#define CAN_ID_GPS_MOTION       0x521u   // 500 мс (протокол 1.3)
#define CAN_ID_DEVICE_STATUS    0x7F0u   // 1000 мс

#define CAN_PERIOD_FAST_MS      50
#define CAN_PERIOD_GAS_MS       200
#define CAN_PERIOD_CLIMATE_MS   200
#define CAN_PERIOD_GPS_MS       500
#define CAN_PERIOD_STATUS_MS    1000

#define CAN_FRAME_BYTES         8

// Версия прошивки блока сбора: старший ниббл — major, младший — minor.
// Протокол 1.3 — значит 0x13. Приборка показывает это число в диагностике.
#define FW_VERSION_MAJOR        1
#define FW_VERSION_MINOR        3
#define FW_VERSION_BYTE         ((uint8_t)((FW_VERSION_MAJOR << 4) | FW_VERSION_MINOR))

// ---------------------------------------------------------------------------
//  0x100 — скорость и обороты
// ---------------------------------------------------------------------------
//  byte 0    скорость, км/ч, uint8 (0…220)
//  byte 1-2  обороты, об/мин, uint16, старший байт первым
//  byte 3-7  резерв
void proto_build_speed_rpm(uint8_t out[CAN_FRAME_BYTES], uint8_t speed_kmh, uint16_t rpm);

// ---------------------------------------------------------------------------
//  0x200 — лампы и индикаторы (битовые маски)
// ---------------------------------------------------------------------------
//  Байт 0: бит 0 левый поворотник, 1 правый, 2 дальний, 3 ближний,
//          4 габариты, 5 противотуманки, 6 задний ход, 7 стоп-сигналы.
//  Байт 1: бит 0 Check Engine, 1 ABS, 2 ручник, 3 ремень (1 = не пристёгнут),
//          4 давление масла (1 = авария), 5 LOCK (SL), 6-7 резерв.
//  Передаётся ФАКТИЧЕСКОЕ состояние лампы: поворотники — уже мигающий сигнал.
typedef struct {
    bool left_turn;
    bool right_turn;
    bool high_beam;
    bool low_beam;
    bool position_lights;
    bool fog_lights;
    bool reverse;
    bool brake;
    bool check_engine;
    bool abs;
    bool hand_brake;
    bool seat_belt_unfastened;
    bool oil_pressure_alarm;
    bool gear_lock;
} proto_lights_t;

void proto_build_lights(uint8_t out[CAN_FRAME_BYTES], const proto_lights_t *lights);

// ---------------------------------------------------------------------------
//  0x300 — данные с датчиков
// ---------------------------------------------------------------------------
//  byte 0    температура двигателя, °C, uint8 (0…120)
//  byte 1    уровень топлива, %, uint8
//  byte 2    напряжение бортсети ×10, uint8 (14.2 В → 142)
//  byte 3    наружная температура, °C, int8 (-5 → 0xFB)
//  byte 4    давление масла: 0 норма, 1 авария (дубль 0x200 бит 4)
//  byte 5-6  мгновенный расход ×10, uint16 (8.5 л/100 → 85)
//  byte 7    резерв
typedef struct {
    uint8_t  engine_temp_c;
    uint8_t  fuel_level_pct;
    uint8_t  voltage_x10;
    int8_t   outside_temp_c;
    bool     oil_pressure_alarm;
    uint16_t fuel_rate_x10;
} proto_sensors_t;

void proto_build_sensors(uint8_t out[CAN_FRAME_BYTES], const proto_sensors_t *sensors);

// ---------------------------------------------------------------------------
//  0x400 — АКПП
// ---------------------------------------------------------------------------
//  byte 0  режим: 0 P, 1 R, 2 N, 3 D, 4 L
//  byte 1  передача: 0 не активна, 1…4 = D1…D4 (имеет смысл только в D)
//  byte 2  LOCK (SL): 0/1
//  byte 3  провод S1: 0/1
//  byte 4  провод S2: 0/1
//  byte 5  провод SL: 0/1 (дубль байта 2)
typedef struct {
    uint8_t mode;      // 0…4
    uint8_t gear;      // 0…4
    bool    lock;
    bool    s1;
    bool    s2;
    bool    sl;
} proto_gearbox_t;

void proto_build_gearbox(uint8_t out[CAN_FRAME_BYTES], const proto_gearbox_t *gearbox);

// ---------------------------------------------------------------------------
//  0x500 — газовое оборудование
// ---------------------------------------------------------------------------
//  byte 0    флаги: бит 0 — едем на газе, бит 1 — датчик уровня газа исправен
//  byte 1-2  напряжение датчика уровня газа, мВ, uint16, старший байт первым
//  byte 3-7  резерв
//  Проценты считает приборка, блок отдаёт сырое напряжение.
void proto_build_gas(uint8_t out[CAN_FRAME_BYTES], bool gas_mode, bool sensor_valid,
                     uint16_t sensor_mv);

// ---------------------------------------------------------------------------
//  0x7F0 — статус блока сбора
// ---------------------------------------------------------------------------
//  byte 0    счётчик кадров статуса (mod 256)
//  byte 1    версия прошивки (0x12 = 1.2)
//  byte 2-5  время работы, секунды, uint32, старший байт первым
//  byte 6    счётчик ошибок шины TWAI, насыщается на 255
//  byte 7    XOR байтов 0…6
void proto_build_device_status(uint8_t out[CAN_FRAME_BYTES], uint8_t counter,
                               uint32_t uptime_sec, uint8_t bus_errors);

// ---------------------------------------------------------------------------
//  Вспомогательное: ограничение значений диапазонами протокола
// ---------------------------------------------------------------------------
uint8_t  proto_clamp_u8(int32_t value, uint8_t min, uint8_t max);
uint16_t proto_clamp_u16(int32_t value, uint16_t min, uint16_t max);
