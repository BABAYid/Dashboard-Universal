#include <stdio.h>
#include <string.h>
#include "bmw_joystick.h"
#include "can_bus.h"
#include "stubs_log.h"

typedef struct { uint32_t id; uint8_t data[8]; } cap_t;
extern cap_t g_caps[64];
extern int g_ncaps;
extern int64_t esp_timer_get_time(void);
uint32_t dbg_now_us_advance(uint32_t ms);

static int fails;

static void frame(uint32_t id, uint8_t a,uint8_t b,uint8_t c,uint8_t d,uint8_t e,uint8_t f, uint8_t g, uint8_t h)
{
    uint8_t data[8] = {a,b,c,d,e,f,g,h};
    input_event_t ev;
    if (joy_handle_frame(id, 8, data, &ev))
        printf("  -> событие: kind=%u code=0x%02X value=%d (%s)\n",
               ev.kind, ev.code, ev.value, joy_button_name(ev.code));
    else
        printf("  -> событий нет\n");
}
static void expect(bool cond, const char *what) {
    if (!cond) { printf("FAIL: %s\n", what); fails++; } else printf("ok:   %s\n", what);
}

int main(void)
{
    joy_init();   /* 0x273 должен уйти */
    expect(g_ncaps == 1 && g_caps[0].id == 0x273 && g_caps[0].data[0] == 0x1D, "старт: 0x273 пробуждение");

    printf("NAV нажата:\n");
    frame(0x267, 0xE1,0xFD,0x01,0x01,0xC0,0x20,0,0);
    printf("NAV повтор (должно быть тихо):\n");
    frame(0x267, 0xE1,0xFD,0x02,0x01,0xC0,0x20,0,0);
    printf("NAV отпущена:\n");
    frame(0x267, 0xE1,0xFD,0x03,0x00,0xC0,0x20,0,0);

    printf("габариты ВКЛ:\n");
    g_ncaps = 0;
    frame(0x200, 0x10,0,0,0,0,0,0,0);
    expect(g_ncaps == 2 && g_caps[0].id == 0x202 && g_caps[1].id == 0x202, "0x202 дважды на фронте");
    printf("габариты ещё раз ВКЛ (фронта нет):\n");
    g_ncaps = 0;
    frame(0x200, 0x10,0,0,0,0,0,0,0);
    expect(g_ncaps == 0, "0x202 не повторяется без фронта");
    printf("габариты ВЫКЛ:\n");
    g_ncaps = 0;
    frame(0x200, 0x00,0,0,0,0,0,0,0);
    expect(g_ncaps == 0, "на выключение ничего не шлём");

    printf("направление вперёд:\n");
    frame(0x267, 0xE1,0xFD,0x04,0x11,0xDD,0x00,0,0);
    printf("направление отпущено:\n");
    frame(0x267, 0xE1,0xFD,0x05,0x00,0xDD,0x00,0,0);
    printf("нажатие ручки:\n");
    frame(0x267, 0xE1,0xFD,0x06,0x01,0xDE,0x01,0,0);
    frame(0x267, 0xE1,0xFD,0x07,0x00,0xDE,0x01,0,0);

    printf("энкодер: первый кадр (тихо), затем +2, затем -1, затем переполнение:\n");
    frame(0x264, 0xE1,0xFD,0x01,0x00,0x10,0x1E,0,0);
    frame(0x264, 0xE1,0xFD,0x02,0x02,0x10,0x1E,0,0);
    frame(0x264, 0xE1,0xFD,0x03,0x01,0x10,0x1E,0,0);
    frame(0x264, 0xE1,0xFD,0x04,0xFF,0xFF,0x1E,0,0);   /* -2 от 0x1001 */
    frame(0x264, 0xE1,0xFD,0x05,0x00,0x00,0x1E,0,0);   /* +1 через переполнение */

    printf("0x5E7 — тишина:\n");
    frame(0x5E7, 0x00,0x00,0x00,0x00,0x00,0x00,0,0);

    printf("--- lifecycle: heartbeat и wake ---\n");
    g_ncaps = 0;
    joy_periodic();
    { int hb = 0; for (int i=0;i<g_ncaps;i++) if (g_caps[i].id == 0x563) hb++;
      expect(hb == 1 && g_caps[0].data[0] == 0x63, "heartbeat 0x563 63"); }
    g_ncaps = 0;
    dbg_now_us_advance(3000);
    joy_periodic();
    { int wake = 0; for (int i=0;i<g_ncaps;i++) if (g_caps[i].id == 0x273) wake++;
      expect(wake == 1, "wake после 3 с тишины"); }
    printf(fails ? "\nПРОВАЛОВ: %d\n" : "\nвсе проверки пройдены\n", fails);
    return fails != 0;
}
