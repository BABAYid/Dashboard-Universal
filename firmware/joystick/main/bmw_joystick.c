// ============================================================================
//  bmw_joystick.c — джойстик BMW iDrive: чем его кормить и как понимать.
//
//  Про раскладку кадра 0x267. В нём нет «номера кнопки» в привычном виде:
//  есть модификатор (что это вообще — кнопка, направление, нажатие на ручку),
//  состояние (нажато/отпущено или код направления) и указатель (какая именно
//  кнопка). Поэтому разбор идёт по модификатору, а указатель переводится в код
//  кнопки протокола приборки. Коды BMW (битовые маски 0x01…0x40) специально не
//  вынесены в заголовок: они нужны только здесь.
//
//  Про отпускание направлений. В кадре отпускания направления состояние
//  приходит 0x00, и какое направление отпустили — из него не видно. Поэтому
//  последнее нажатое направление запоминается (s_dir_code): иначе приборка
//  получила бы нажатие UP без отпускания и «залипла» на прокрутке.
// ============================================================================
#include "bmw_joystick.h"

#include <stddef.h>

#include "esp_log.h"
#include "esp_timer.h"

#include "can_bus.h"
#include "config.h"

static const char *TAG = "joy";

// ---------------------------------------------------------------------------
//  Внутренние коды BMW (только для этого файла)
// ---------------------------------------------------------------------------
//  Байт 4 кадра 0x267 — модификатор события.
#define BMW_MOD_BUTTON      0xC0
#define BMW_MOD_DIRECTION   0xDD
#define BMW_MOD_PRESS       0xDE

//  Байт 3 для направлений: кода «нажата/отпущена» нет, вместо него —
//  собственный код направления. Отпускание приходит нулём.
#define BMW_DIR_FWD         0x11   // вперёд  (UP)
#define BMW_DIR_BACK        0x41   // назад   (DOWN)
#define BMW_DIR_RIGHT       0x21   // вправо  (RIGHT)
#define BMW_DIR_LEFT        0x81   // влево   (LEFT)

//  Байт 5 для кнопок — битовая маска кнопки.
#define BMW_BTN_MENU        0x01
#define BMW_BTN_BACK        0x02
#define BMW_BTN_OPTION      0x04
#define BMW_BTN_RADIO       0x08
#define BMW_BTN_MEDIA       0x10
#define BMW_BTN_NAV         0x20
#define BMW_BTN_TEL         0x40

//  Первые два байта 0x267 и 0x264 — постоянная «шапка» кадра. По ней
//  проверяем, что кадр действительно от джойстика: ID на шине может совпасть
//  случайно (например, с кадром блока сбора в будущей версии протокола).
#define BMW_HEAD_0          0xE1
#define BMW_HEAD_1          0xFD

// ---------------------------------------------------------------------------
//  Состояние модуля
// ---------------------------------------------------------------------------
static bool     s_lights_on;        // габариты по последнему кадру 0x200
static uint16_t s_pressed;          // маска нажатых кнопок (бит = код 0x530)
static uint8_t  s_dir_code;         // последнее нажатое направление (0 = нет)
static int16_t  s_encoder;          // предыдущее значение счётчика энкодера
static bool     s_encoder_valid;    // предыдущее значение уже известно
static uint32_t s_last_activity_ms; // когда последний раз слышали 0x267/0x264
static uint32_t s_last_heartbeat_ms;
static uint32_t s_wake_retries;     // сколько раз будили по тишине подряд

// Монотонное время в миллисекундах. Одно на весь модуль: и приём, и передача
// сравнивают сроки в одной шкале, иначе «2 секунды тишины» считались бы от
// разных начал. Переполнение uint32 (≈49 суток) разностям не мешает.
static uint32_t now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

// ---------------------------------------------------------------------------
//  Отправка джойстику
// ---------------------------------------------------------------------------
static void send_wake(void)
{
    // 0x273: «проснись». Значения проверены на живом модуле F20 — с ними
    // джойстик выходит из сна и начинает отдавать 0x267/0x264.
    static const uint8_t wake[CAN_FRAME_BYTES] = {
        0x1D, 0xE1, 0x00, 0xF0, 0xFF, 0x7F, 0xDE, 0x00
    };
    if (!can_bus_transmit(JOY_ID_WAKE, wake))
        ESP_LOGW(TAG, "0x273 (пробуждение) не ушёл в шину");
}

static void send_lights(void)
{
    // 0x202: подсветка кнопок. Модуль принимает её только ДВУМЯ кадрами
    // подряд — одиночный он молча игнорирует, поэтому шлём дважды и сразу.
    static const uint8_t lights[CAN_FRAME_BYTES] = { 0xFD };
    can_bus_transmit(JOY_ID_LIGHT, lights);
    can_bus_transmit(JOY_ID_LIGHT, lights);
}

// ---------------------------------------------------------------------------
//  Габариты: 0x200 от блока сбора, байт 0, бит 4
//
//  Подсветка отправляется ТОЛЬКО по фронту включения. Поток кадров 0x202
//  модуль воспринимает как команду и держит подсветку, но постоянная посылка
//  — лишний трафик на шине и риск, что выключение габаритов не сработает.
//  На выключение не отправляем ничего: модуль гасит подсветку сам, когда
//  перестаёт получать команду.
// ---------------------------------------------------------------------------
static void handle_collector_lights(const uint8_t d[8])
{
    const bool on = (d[0] & 0x10u) != 0;
    if (on == s_lights_on)
        return;                     // фронта нет — молчим

    s_lights_on = on;
    if (!on) {
        ESP_LOGI(TAG, "0x200: габариты выключились — 0x202 не шлю, модуль гаснет сам");
        return;
    }

    send_lights();
    ESP_LOGI(TAG, "0x200: габариты включились → 0x202 FD (подсветка, два кадра)");
}

// ---------------------------------------------------------------------------
//  Кнопки: единая точка учёта нажатий
//
//  Модуль повторяет кадр, пока кнопку держат, поэтому наружу выдаётся только
//  смена состояния. Иначе приборка получала бы десяток «нажата» подряд и
//  прокручивала список, пока палец на кнопке.
// ---------------------------------------------------------------------------
static bool mark_button(uint8_t code, bool pressed, input_event_t *event)
{
    const uint16_t mask = (uint16_t)(1u << code);
    const bool was_pressed = (s_pressed & mask) != 0;
    if (was_pressed == pressed)
        return false;

    if (pressed)
        s_pressed |= mask;
    else
        s_pressed &= (uint16_t)~mask;

    event->kind = IN_EVENT_BUTTON;
    event->code = code;
    event->value = pressed ? 1 : 0;
    return true;
}

static uint8_t button_code_from_pointer(uint8_t pointer)
{
    switch (pointer) {
    case BMW_BTN_MENU:   return IN_BTN_MENU;
    case BMW_BTN_BACK:   return IN_BTN_BACK;
    case BMW_BTN_OPTION: return IN_BTN_OPTION;
    case BMW_BTN_RADIO:  return IN_BTN_RADIO;
    case BMW_BTN_MEDIA:  return IN_BTN_MEDIA;
    case BMW_BTN_NAV:    return IN_BTN_NAV;
    case BMW_BTN_TEL:    return IN_BTN_TEL;
    default:             return 0;
    }
}

static uint8_t button_code_from_direction(uint8_t state)
{
    switch (state) {
    case BMW_DIR_FWD:   return IN_BTN_UP;
    case BMW_DIR_BACK:  return IN_BTN_DOWN;
    case BMW_DIR_RIGHT: return IN_BTN_RIGHT;
    case BMW_DIR_LEFT:  return IN_BTN_LEFT;
    default:            return 0;
    }
}

// ---------------------------------------------------------------------------
//  0x267 — события: кнопки, направления, нажатие на ручку
//  Формат: E1 FD [счётчик] [состояние] [модификатор] [указатель]
// ---------------------------------------------------------------------------
static bool parse_event(const uint8_t d[8], input_event_t *event)
{
    const uint8_t state    = d[3];
    const uint8_t modifier = d[4];
    const uint8_t pointer  = d[5];

    switch (modifier) {
    case BMW_MOD_BUTTON: {
        const uint8_t code = button_code_from_pointer(pointer);
        if (code == 0) {
            ESP_LOGW(TAG, "0x267: неизвестная кнопка (указатель 0x%02X) — пропускаю",
                     pointer);
            return false;
        }
        return mark_button(code, state != 0x00, event);
    }

    case BMW_MOD_DIRECTION: {
        const uint8_t code = button_code_from_direction(state);
        if (code != 0) {
            s_dir_code = code;
            return mark_button(code, true, event);
        }
        // Состояние 0x00 при модификаторе «направление» — это отпускание.
        // Какое именно направление отпустили, в кадре не сказано: берём
        // последнее нажатое и считаем, что отпустили его.
        if (state == 0x00 && s_dir_code != 0) {
            const uint8_t released = s_dir_code;
            s_dir_code = 0;
            return mark_button(released, false, event);
        }
        return false;
    }

    case BMW_MOD_PRESS: {
        // Нажатие на саму ручку джойстика. Указатель 0x01 — единственный
        // известный; всё остальное считаем мусором, чтобы не выдумывать
        // событий, которых приборка не ждёт.
        if (pointer != 0x01) {
            ESP_LOGW(TAG, "0x267: нажатие ручки с указателем 0x%02X — пропускаю",
                     pointer);
            return false;
        }
        return mark_button(IN_BTN_PRESS, state != 0x00, event);
    }

    default:
        ESP_LOGD(TAG, "0x267: модификатор 0x%02X не разбираем (состояние 0x%02X)",
                 modifier, state);
        return false;
    }
}

// ---------------------------------------------------------------------------
//  0x264 — энкодер: 16-битный счётчик поворотов
//  Формат: E1 FD [счётчик] [младший байт] [старший байт] 1E
//
//  Нам нужно не значение счётчика, а его изменение. Разность считается по
//  беззнаковой 16-битной арифметике: при переполнении (0xFFFF → 0x0000)
//  она всё равно даёт правильную знаковую дельту, тогда как «в лоб» через
//  int получилось бы +65535 вместо +1.
// ---------------------------------------------------------------------------
static bool parse_encoder(const uint8_t d[8], input_event_t *event)
{
    const int16_t value = (int16_t)(uint16_t)(d[3] | ((uint16_t)d[4] << 8));

    if (!s_encoder_valid) {
        // Первый кадр после старта: предыдущего значения нет. Запоминаем и
        // молчим — иначе при включении в приборку улетело бы «случайное»
        // число щелчков, которого никто не делал.
        s_encoder = value;
        s_encoder_valid = true;
        return false;
    }

    const int16_t delta = (int16_t)(uint16_t)((uint16_t)value - (uint16_t)s_encoder);
    s_encoder = value;

    if (delta == 0)
        return false;               // энкодер стоит — событий не выдумываем

    int32_t out = (int32_t)delta;
#if JOY_ENCODER_INVERT
    out = -out;
#endif

    // В кадре 0x530 дельта — int8. За один кадр может прийти несколько
    // щелчков, но не полторы сотни: такое значение означает сбой на шине
    // или скачок счётчика, и отправлять его приборке нельзя — она получила
    // бы прокрутку на 127 позиций.
    if (out > 127 || out < -127) {
        ESP_LOGW(TAG, "0x264: скачок энкодера %d за один кадр — ограничиваю до ±127",
                 (int)out);
        out = (out > 0) ? 127 : -127;
    }

    event->kind = IN_EVENT_ENCODER;
    event->code = 0;
    event->value = (int8_t)out;
    return true;
}

// ---------------------------------------------------------------------------
//  Разбор принятого кадра
// ---------------------------------------------------------------------------
bool joy_handle_frame(uint32_t id, uint8_t dlc, const uint8_t data[8],
                      input_event_t *event)
{
    if (event == NULL)
        return false;

    // Кадры джойстика всегда 8 байт. Короткий кадр с тем же ID — это не наш
    // случай (или обрыв на шине), разбирать его нечем.
    if (dlc < 6)
        return false;

    const uint8_t *d = data;

    if (id == JOY_ID_EVENT) {
        if (d[0] != BMW_HEAD_0 || d[1] != BMW_HEAD_1)
            return false;
        s_last_activity_ms = now_ms();
        s_wake_retries = 0;          // джойстик проснулся — счётчик повторов сброшен
        return parse_event(d, event);
    }

    if (id == JOY_ID_ENCODER) {
        if (d[0] != BMW_HEAD_0 || d[1] != BMW_HEAD_1)
            return false;
        s_last_activity_ms = now_ms();
        s_wake_retries = 0;
        return parse_encoder(d, event);
    }

    if (id == JOY_ID_EVENT_ACK) {
        // 0x5E7 — подтверждение событий. Своих нажатий мы уже разобрали по
        // 0x267; если слать 0x530 по подтверждению, приборка получит по два
        // кадра на каждое нажатие.
        return false;
    }

    if (id == CAN_ID_COLLECTOR_LIGHTS) {
        handle_collector_lights(d);
        return false;
    }

    // Всё остальное на шине (0x100 скорость, 0x300 датчики, наши же 0x202 и
    // 0x563, если контроллер их когда-нибудь вернёт) модулю ввода не нужно.
    return false;
}

// ---------------------------------------------------------------------------
//  Жизнеобеспечение: heartbeat и повторное пробуждение
// ---------------------------------------------------------------------------
void joy_init(void)
{
    s_lights_on = false;    // про габариты ещё ничего не знаем: первое
                            // включение обязано считаться фронтом
    s_pressed = 0;
    s_dir_code = 0;
    s_encoder = 0;
    s_encoder_valid = false;
    s_wake_retries = 0;

    const uint32_t now = now_ms();
    s_last_activity_ms = now;   // старт не считается «джойстик молчит»
    s_last_heartbeat_ms = now;

    // «Пробуждение» при старте: ESP32 мог перезагрузиться, пока модуль спал,
    // и тогда наша половина сеанса связи потеряна. Один лишний кадр 0x273
    // ничего не ломает.
    ESP_LOGI(TAG, "отправляю джойстику пробуждение (0x273)");
    send_wake();
}

void joy_periodic(void)
{
    const uint32_t now = now_ms();

    // 0x563 — heartbeat. Модуль засыпает без этих кадров, поэтому они идут
    // строго по таймеру и не зависят от того, трогают джойстик или нет.
    // Расписание не «догоняется» пачкой после задержки: пачка выглядит для
    // модуля как сбой, а пропущенные 100 мс не заметны.
    if (now - s_last_heartbeat_ms >= JOY_HEARTBEAT_MS) {
        static const uint8_t heartbeat[CAN_FRAME_BYTES] = { 0x63 };
        can_bus_transmit(JOY_ID_HEARTBEAT, heartbeat);
        s_last_heartbeat_ms = now;
    }

    // Тишина 2 секунды. Джойстик молчит и когда его просто не трогают, так
    // что повтор идёт всё время тишины, а не только после реального сна
    // модуля: отличить «спит» от «не трогают» по шине нельзя, а лишнее
    // пробуждение дешевле потерянных нажатий.
    if (now - s_last_activity_ms >= JOY_WAKE_RETRY_MS) {
        const uint32_t silence = now - s_last_activity_ms;
        ++s_wake_retries;
        send_wake();
        s_last_activity_ms = now;   // следующий повтор — ещё через 2 секунды

        // В журнал — первый повтор (значит, джойстик правда замолчал) и
        // потом каждый 15-й: иначе строка «молчит» вытеснит из лога события.
        if (s_wake_retries == 1 || (s_wake_retries % JOY_WAKE_LOG_EVERY) == 0) {
            ESP_LOGW(TAG, "от джойстика нет кадров %u мс — повторяю 0x273 (повтор №%u)",
                     (unsigned)silence, (unsigned)s_wake_retries);
        }
    }
}

// ---------------------------------------------------------------------------
//  Имена кнопок для журнала
// ---------------------------------------------------------------------------
const char *joy_button_name(uint8_t code)
{
    switch (code) {
    case IN_BTN_MENU:   return "MENU";
    case IN_BTN_BACK:   return "BACK";
    case IN_BTN_OPTION: return "OPTION";
    case IN_BTN_RADIO:  return "RADIO";
    case IN_BTN_MEDIA:  return "MEDIA";
    case IN_BTN_NAV:    return "NAV";
    case IN_BTN_TEL:    return "TEL";
    case IN_BTN_UP:     return "UP";
    case IN_BTN_DOWN:   return "DOWN";
    case IN_BTN_LEFT:   return "LEFT";
    case IN_BTN_RIGHT:  return "RIGHT";
    case IN_BTN_PRESS:  return "PRESS";
    default:            return "?";
    }
}
