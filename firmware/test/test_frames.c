// ============================================================================
//  test_frames.c — проверка кодировщика кадров блока сбора на компьютере.
//
//  Собирается обычным gcc, ESP32 и ESP-IDF не нужны: проверяются байты,
//  которые прошивка положит в кадр, против примеров из can_protocol_v1.2.txt.
//  Это «встречная» проверка к тесту приборки: там байты разбирают, здесь —
//  собирают, и оба обязаны сходиться с одним документом.
//
//  Сборка и запуск:
//      cmake -S firmware/test -B firmware-build
//      cmake --build firmware-build
//      ./firmware-build/test_frames
//
//  Или одной строкой без cmake:
//      gcc -Wall -Wextra -o test_frames firmware/test/test_frames.c
//          firmware/main/can_protocol.c -Ifirmware/main && ./test_frames
//  (вторая строка — продолжение первой команды)
// ============================================================================
#include "can_protocol.h"

#include <stdio.h>
#include <string.h>

static int g_failures = 0;

static void check(int ok, const char *what)
{
    if (ok) {
        printf("  ок   %s\n", what);
    } else {
        ++g_failures;
        printf("  ОШИБКА: %s\n", what);
    }
}

static void check_frame(const uint8_t *got, const uint8_t *expected, int len, const char *what)
{
    int ok = (memcmp(got, expected, (size_t)len) == 0);
    if (!ok) {
        ++g_failures;
        printf("  ОШИБКА: %s\n     получено: ", what);
        for (int i = 0; i < CAN_FRAME_BYTES; ++i) printf("%02X ", got[i]);
        printf("\n     ожидалось:");
        for (int i = 0; i < CAN_FRAME_BYTES; ++i) printf("%02X ", expected[i]);
        printf("\n");
    } else {
        printf("  ок   %s\n", what);
    }
}

int main(void)
{
    uint8_t f[CAN_FRAME_BYTES];

    printf("0x100 — скорость и обороты (пример из документации)\n");
    proto_build_speed_rpm(f, 102, 2450);
    {
        const uint8_t exp[8] = {0x66, 0x09, 0x92, 0, 0, 0, 0, 0};
        check_frame(f, exp, 8, "102 км/ч, 2450 об/мин");
    }
    proto_build_speed_rpm(f, 0, 0);
    {
        const uint8_t exp[8] = {0, 0, 0, 0, 0, 0, 0, 0};
        check_frame(f, exp, 8, "машина стоит: нули");
    }
    proto_build_speed_rpm(f, 220, 8000);
    {
        const uint8_t exp[8] = {0xDC, 0x1F, 0x40, 0, 0, 0, 0, 0};   // 220 = 0xDC
        check_frame(f, exp, 8, "верх шкалы: 220 км/ч, 8000 об/мин");
    }

    printf("0x200 — лампы (пример: правый поворотник, ближний свет, ABS)\n");
    {
        proto_lights_t l;
        memset(&l, 0, sizeof(l));
        l.right_turn = true;
        l.low_beam = true;
        l.abs = true;
        proto_build_lights(f, &l);
        const uint8_t exp[8] = {0x0A, 0x02, 0, 0, 0, 0, 0, 0};
        check_frame(f, exp, 8, "байт 0 = 0x0A, байт 1 = 0x02");
    }
    {
        proto_lights_t l;
        memset(&l, 0, sizeof(l));
        l.position_lights = true;
        l.check_engine = true;
        l.hand_brake = true;
        l.seat_belt_unfastened = true;
        l.gear_lock = true;
        proto_build_lights(f, &l);
        const uint8_t exp[8] = {0x10, 0x2D, 0, 0, 0, 0, 0, 0};
        check_frame(f, exp, 8, "габариты + чек/ABS-нет/ручник/ремень/LOCK = 0x2D");
    }
    {
        proto_lights_t l;
        memset(&l, 0, sizeof(l));
        l.brake = true;
        l.reverse = true;
        l.oil_pressure_alarm = true;
        proto_build_lights(f, &l);
        const uint8_t exp[8] = {0xC0, 0x10, 0, 0, 0, 0, 0, 0};
        check_frame(f, exp, 8, "стопы + задний ход, авария по маслу");
    }

    printf("0x300 — датчики (пример из документации)\n");
    {
        proto_sensors_t s;
        s.engine_temp_c = 90;
        s.fuel_level_pct = 42;
        s.voltage_x10 = 142;
        s.outside_temp_c = -5;
        s.oil_pressure_alarm = false;
        s.fuel_rate_x10 = 85;
        proto_build_sensors(f, &s);
        const uint8_t exp[8] = {0x5A, 0x2A, 0x8E, 0xFB, 0x00, 0x00, 0x55, 0x00};
        check_frame(f, exp, 8, "90 °C, 42 %, 14.2 В, -5 °C, расход 8.5");
    }
    {
        proto_sensors_t s;
        memset(&s, 0, sizeof(s));
        s.outside_temp_c = 20;
        s.oil_pressure_alarm = true;
        s.fuel_rate_x10 = 999;
        proto_build_sensors(f, &s);
        const uint8_t exp[8] = {0, 0, 0, 0x14, 0x01, 0x03, 0xE7, 0x00};
        check_frame(f, exp, 8, "расход 99.9 л/100 (999 = 0x03E7 — в версии 1.0 не влезал)");
    }
    {
        proto_sensors_t s;
        memset(&s, 0, sizeof(s));
        s.outside_temp_c = -40;
        proto_build_sensors(f, &s);
        check(f[3] == 0xD8, "наружная температура -40 °C → 0xD8 (int8)");
    }

    printf("0x400 — АКПП (пример: режим D, передача D2)\n");
    {
        proto_gearbox_t g;
        g.mode = 3;
        g.gear = 2;
        g.lock = false;
        g.s1 = true;
        g.s2 = true;
        g.sl = false;
        proto_build_gearbox(f, &g);
        const uint8_t exp[8] = {0x03, 0x02, 0x00, 0x01, 0x01, 0x00, 0, 0};
        check_frame(f, exp, 8, "D2, LOCK выкл, S1/S2 вкл");
    }

    printf("0x500 — газовое оборудование (пример из документации)\n");
    proto_build_gas(f, true, true, 2350);
    {
        const uint8_t exp[8] = {0x03, 0x09, 0x2E, 0, 0, 0, 0, 0};
        check_frame(f, exp, 8, "газ включён, датчик исправен, 2.35 В");
    }
    proto_build_gas(f, false, true, 5000);
    {
        const uint8_t exp[8] = {0x02, 0x13, 0x88, 0, 0, 0, 0, 0};
        check_frame(f, exp, 8, "бензин, датчик исправен, полный баллон 5 В");
    }
    proto_build_gas(f, true, false, 0);
    check(f[0] == 0x01 && f[1] == 0x00 && f[2] == 0x00,
          "датчик не отвечает: бит 1 флагов снят, напряжение 0");

    printf("0x7F0 — статус блока сбора\n");
    proto_build_device_status(f, 0, 3600, 3);
    {
        // XOR байтов 0…6: 00^13^00^00^0E^10^03 = 0x0E
        const uint8_t exp[8] = {0x00, FW_VERSION_BYTE, 0x00, 0x00, 0x0E, 0x10, 0x03, 0x0E};
        check_frame(f, exp, 8, "счётчик 0, время работы 3600 с, ошибок 3, XOR сходится");
        check(FW_VERSION_BYTE == 0x13, "версия прошивки в кадре — 0x13 (протокол 1.3)");
    }
    proto_build_device_status(f, 200, 0x01020304u, 250);
    check(f[0] == 200 && f[2] == 0x01 && f[3] == 0x02 && f[4] == 0x03 && f[5] == 0x04,
          "время работы укладывается старшим байтом первым");
    {
        uint8_t xor_sum = 0;
        for (int i = 0; i < 7; ++i) xor_sum ^= f[i];
        check(f[7] == xor_sum, "контрольная сумма пересчитана верно");
    }

    printf("0x510 — климат (протокол 1.3)\n");
    {
        proto_climate_t c;
        memset(&c, 0, sizeof(c));
        c.ac_on = true;
        c.valid = true;
        c.setpoint_x2 = 45;                    // 22.5 °C
        c.fan_level = 3;
        c.airflow = CLIMATE_AIRFLOW_FACE;
        c.cabin_temp_c = 24;
        c.evaporator_temp_c = CLIMATE_TEMP_NONE;
        proto_build_climate(f, &c);
        const uint8_t exp[8] = {0x21, 0x2D, 0x03, 0x04, 0x18, 0x80, 0x00, 0x00};
        check_frame(f, exp, 8, "AC + данные достоверны, 22.5 °C, вентилятор 3, поток «лицо», в салоне 24");
    }
    {
        proto_climate_t c;
        memset(&c, 0, sizeof(c));
        c.fan_level = CLIMATE_FAN_NONE;
        c.cabin_temp_c = CLIMATE_TEMP_NONE;
        c.evaporator_temp_c = CLIMATE_TEMP_NONE;
        proto_build_climate(f, &c);
        check(f[0] == 0x00 && f[2] == 0xFF && f[4] == 0x80 && f[5] == 0x80,
              "нет данных: бит достоверности снят, вентилятор 0xFF, температуры 0x80");
    }
    {
        proto_climate_t c;
        memset(&c, 0, sizeof(c));
        c.auto_mode = true;
        c.recirculation = true;
        c.defrost = true;
        c.fan_auto = true;
        c.valid = true;
        proto_build_climate(f, &c);
        check(f[0] == (0x02 | 0x04 | 0x08 | 0x10 | 0x20),
              "AUTO + рециркуляция + обдув лобового + вентилятор в авторежиме");
    }

    printf("0x520 — GPS: положение (протокол 1.3)\n");
    {
        proto_gps_pos_t p = {.latitude_e7 = 557558000, .longitude_e7 = 376173000};
        proto_build_gps_position(f, &p);
        const uint8_t exp[8] = {0x21, 0x3B, 0xA8, 0xF0, 0x16, 0x6B, 0xF1, 0xC8};
        check_frame(f, exp, 8, "Москва 55.7558 / 37.6173, старший байт первым");
    }
    {
        proto_gps_pos_t p = {.latitude_e7 = -338688000, .longitude_e7 = 151209300};
        proto_build_gps_position(f, &p);
        const uint8_t exp[8] = {0xEB, 0xD0, 0x08, 0x00, 0x09, 0x03, 0x45, 0x54};
        check_frame(f, exp, 8, "южное полушарие: отрицательная широта как int32");
    }

    printf("0x521 — GPS: движение и качество (протокол 1.3)\n");
    {
        proto_gps_motion_t m;
        memset(&m, 0, sizeof(m));
        m.course_x2 = 67;                      // 134…135°
        m.speed_kmh = 60;
        m.hdop_x10 = 11;
        m.satellites = 8;
        m.fix_type = GPS_FIX_3D;
        m.utc_second = 20;
        m.utc_minute = 35;
        m.utc_hour = 14;
        m.fix = true;
        m.time_valid = true;
        proto_build_gps_motion(f, &m);
        const uint8_t exp[8] = {0x43, 0x3C, 0x0B, 0x48, 0x14, 0x23, 0x0E, 0x03};
        check_frame(f, exp, 8, "курс, скорость 60, HDOP 1.1, 8 спутников + 3D, 14:35:20");
    }
    {
        proto_gps_motion_t m;
        memset(&m, 0, sizeof(m));
        m.course_x2 = GPS_VALUE_NONE;
        m.speed_kmh = GPS_VALUE_NONE;
        m.hdop_x10 = GPS_VALUE_NONE;
        m.fix_type = GPS_FIX_NONE;
        proto_build_gps_motion(f, &m);
        check(f[0] == 0xFF && f[1] == 0xFF && f[2] == 0xFF && f[7] == 0x00,
              "нет фикса: поля «нет данных», флаг фикса снят");
    }
    {
        proto_gps_motion_t m;
        memset(&m, 0, sizeof(m));
        m.satellites = 40;                     // больше 31 — насыщается
        m.fix_type = 7;                        // больше 2 — считается 3D
        proto_build_gps_motion(f, &m);
        check((f[3] & 0x1F) == 31 && ((f[3] >> 5) & 0x07) == 2,
              "спутники насыщаются на 31, тип фикса — не больше 3D");
    }

    printf("Ограничение значений\n");
    check(proto_clamp_u8(-3, 0, 220) == 0, "отрицательная скорость → 0");
    check(proto_clamp_u8(300, 0, 220) == 220, "скорость выше шкалы → 220");
    check(proto_clamp_u16(99999, 0, 999) == 999, "расход выше 99.9 → 999");

    printf("\n");
    if (g_failures == 0)
        printf("Все проверки пройдены.\n");
    else
        printf("Провалено проверок: %d\n", g_failures);

    return g_failures == 0 ? 0 : 1;
}
