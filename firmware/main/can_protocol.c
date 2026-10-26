// ============================================================================
//  can_protocol.c — сборка кадров CAN (протокол 1.2).
//
//  Файл намеренно не тянет за собой ESP-IDF: его собирает и обычный gcc на
//  компьютере (см. firmware/test/). Любое изменение расположения данных
//  обязано сопровождаться правкой can_protocol_v1.2.txt, разбора в
//  Dashboard/can/CanBackend.cpp и теста Dashboard/tests/test_canprotocol.cpp.
// ============================================================================
#include "can_protocol.h"

#include <string.h>

uint8_t proto_clamp_u8(int32_t value, uint8_t min, uint8_t max)
{
    if (value < (int32_t)min) return min;
    if (value > (int32_t)max) return max;
    return (uint8_t)value;
}

uint16_t proto_clamp_u16(int32_t value, uint16_t min, uint16_t max)
{
    if (value < (int32_t)min) return min;
    if (value > (int32_t)max) return max;
    return (uint16_t)value;
}

void proto_build_speed_rpm(uint8_t out[CAN_FRAME_BYTES], uint8_t speed_kmh, uint16_t rpm)
{
    memset(out, 0, CAN_FRAME_BYTES);
    out[0] = speed_kmh;
    out[1] = (uint8_t)(rpm >> 8);
    out[2] = (uint8_t)(rpm & 0xFF);
}

void proto_build_lights(uint8_t out[CAN_FRAME_BYTES], const proto_lights_t *l)
{
    memset(out, 0, CAN_FRAME_BYTES);

    uint8_t light_byte = 0;
    if (l->left_turn)       light_byte |= (1u << 0);
    if (l->right_turn)      light_byte |= (1u << 1);
    if (l->high_beam)       light_byte |= (1u << 2);
    if (l->low_beam)        light_byte |= (1u << 3);
    if (l->position_lights) light_byte |= (1u << 4);
    if (l->fog_lights)      light_byte |= (1u << 5);
    if (l->reverse)         light_byte |= (1u << 6);
    if (l->brake)           light_byte |= (1u << 7);

    uint8_t ind_byte = 0;
    if (l->check_engine)            ind_byte |= (1u << 0);
    if (l->abs)                     ind_byte |= (1u << 1);
    if (l->hand_brake)              ind_byte |= (1u << 2);
    if (l->seat_belt_unfastened)    ind_byte |= (1u << 3);
    if (l->oil_pressure_alarm)      ind_byte |= (1u << 4);
    if (l->gear_lock)               ind_byte |= (1u << 5);

    out[0] = light_byte;
    out[1] = ind_byte;
}

void proto_build_sensors(uint8_t out[CAN_FRAME_BYTES], const proto_sensors_t *s)
{
    memset(out, 0, CAN_FRAME_BYTES);

    out[0] = s->engine_temp_c;
    out[1] = s->fuel_level_pct;
    out[2] = s->voltage_x10;
    out[3] = (uint8_t)s->outside_temp_c;
    out[4] = s->oil_pressure_alarm ? 1u : 0u;
    out[5] = (uint8_t)(s->fuel_rate_x10 >> 8);
    out[6] = (uint8_t)(s->fuel_rate_x10 & 0xFF);
}

void proto_build_gearbox(uint8_t out[CAN_FRAME_BYTES], const proto_gearbox_t *g)
{
    memset(out, 0, CAN_FRAME_BYTES);

    out[0] = g->mode;
    out[1] = g->gear;
    out[2] = g->lock ? 1u : 0u;
    out[3] = g->s1 ? 1u : 0u;
    out[4] = g->s2 ? 1u : 0u;
    out[5] = g->sl ? 1u : 0u;
}

void proto_build_gas(uint8_t out[CAN_FRAME_BYTES], bool gas_mode, bool sensor_valid,
                     uint16_t sensor_mv)
{
    memset(out, 0, CAN_FRAME_BYTES);

    uint8_t flags = 0;
    if (gas_mode)      flags |= (1u << 0);
    if (sensor_valid)  flags |= (1u << 1);

    out[0] = flags;
    out[1] = (uint8_t)(sensor_mv >> 8);
    out[2] = (uint8_t)(sensor_mv & 0xFF);
}

void proto_build_climate(uint8_t out[CAN_FRAME_BYTES], const proto_climate_t *c)
{
    memset(out, 0, CAN_FRAME_BYTES);

    uint8_t flags = 0;
    if (c->ac_on)          flags |= (1u << 0);
    if (c->auto_mode)      flags |= (1u << 1);
    if (c->recirculation)  flags |= (1u << 2);
    if (c->defrost)        flags |= (1u << 3);
    if (c->fan_auto)       flags |= (1u << 4);
    if (c->valid)          flags |= (1u << 5);

    out[0] = flags;
    out[1] = c->setpoint_x2;
    out[2] = c->fan_level;
    out[3] = c->airflow;
    out[4] = (uint8_t)c->cabin_temp_c;
    out[5] = (uint8_t)c->evaporator_temp_c;
    out[6] = c->setpoint_right_x2;
    out[7] = 0;
}

void proto_build_gps_position(uint8_t out[CAN_FRAME_BYTES], const proto_gps_pos_t *p)
{
    memset(out, 0, CAN_FRAME_BYTES);

    const uint32_t lat = (uint32_t)p->latitude_e7;
    const uint32_t lon = (uint32_t)p->longitude_e7;

    out[0] = (uint8_t)(lat >> 24);
    out[1] = (uint8_t)(lat >> 16);
    out[2] = (uint8_t)(lat >> 8);
    out[3] = (uint8_t)(lat & 0xFF);
    out[4] = (uint8_t)(lon >> 24);
    out[5] = (uint8_t)(lon >> 16);
    out[6] = (uint8_t)(lon >> 8);
    out[7] = (uint8_t)(lon & 0xFF);
}

void proto_build_gps_motion(uint8_t out[CAN_FRAME_BYTES], const proto_gps_motion_t *m)
{
    memset(out, 0, CAN_FRAME_BYTES);

    out[0] = m->course_x2;
    out[1] = m->speed_kmh;
    out[2] = m->hdop_x10;

    const uint8_t fix_type = (uint8_t)((m->fix_type > 2u) ? 2u : m->fix_type);
    out[3] = (uint8_t)((m->satellites > 31u ? 31u : m->satellites) | (fix_type << 5));

    out[4] = m->utc_second;
    out[5] = m->utc_minute;
    out[6] = m->utc_hour;

    uint8_t flags = 0;
    if (m->fix)         flags |= (1u << 0);
    if (m->time_valid)  flags |= (1u << 1);
    // Бит 2 «данные свежие» приборка проверяет сама по времени прихода кадра,
    // поэтому блок сбора его не выставляет.
    out[7] = flags;
}

void proto_build_device_status(uint8_t out[CAN_FRAME_BYTES], uint8_t counter,
                               uint32_t uptime_sec, uint8_t bus_errors)
{
    memset(out, 0, CAN_FRAME_BYTES);

    out[0] = counter;
    out[1] = FW_VERSION_BYTE;
    out[2] = (uint8_t)(uptime_sec >> 24);
    out[3] = (uint8_t)(uptime_sec >> 16);
    out[4] = (uint8_t)(uptime_sec >> 8);
    out[5] = (uint8_t)(uptime_sec & 0xFF);
    out[6] = bus_errors;

    uint8_t xor_sum = 0;
    for (int i = 0; i < 7; ++i)
        xor_sum ^= out[i];
    out[7] = xor_sum;
}
