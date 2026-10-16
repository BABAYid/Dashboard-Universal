// ============================================================================
//  test_signals.c — проверка таблицы проводов (main/vehicle_signals.c).
//
//  Таблицу заполняет человек, и одна опечатка там обходится дорого: два
//  сигнала на одном входе или номер канала вне диапазона проявятся не сразу,
//  а «странным» поведением ламп на приборке. Поэтому таблица проверяется
//  на компьютере — до прошивки.
//
//  Собирается и запускается так же, как test_frames (см. firmware/README.md).
// ============================================================================
#include "vehicle_signals.h"

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

int main(void)
{
    printf("Таблица проводов: целостность\n");

    // 1. Каждому смыслу — ровно одна строка в таблице.
    int missing = 0;
    for (int id = SIG_NONE + 1; id < SIG_COUNT; ++id) {
        const vehicle_signal_t *s = vehicle_signal((vehicle_signal_id_t)id);
        if ((int)s->id != id) {
            printf("  ОШИБКА: для сигнала %d нет строки в таблице\n", id);
            ++missing;
        }
    }
    check(missing == 0, "у каждого сигнала есть строка в таблице");

    // 2. Нет двух строк с одним и тем же смыслом.
    const vehicle_signal_t *list = vehicle_signals();
    const size_t count = vehicle_signals_count();
    int duplicates = 0;
    for (size_t i = 0; i < count; ++i) {
        for (size_t j = i + 1; j < count; ++j) {
            if (list[i].id == list[j].id) {
                printf("  ОШИБКА: сигнал %d встречается дважды («%s» и «%s»)\n",
                       (int)list[i].id, list[i].name, list[j].name);
                ++duplicates;
            }
        }
    }
    check(duplicates == 0, "нет повторяющихся сигналов");

    // 3. Диапазоны каналов и уникальность входов.
    int bad_channel = 0;
    int busy_din[24] = {0};
    int busy_ain[4] = {0};
    int collisions = 0;

    for (size_t i = 0; i < count; ++i) {
        const vehicle_signal_t *s = &list[i];
        switch (s->source) {
        case SRC_NONE:
            break;
        case SRC_DIN:
        case SRC_PCF:
        case SRC_FREQ:
            if (s->channel < 1 || s->channel > 23) {
                printf("  ОШИБКА: «%s»: DIN_%u — такого входа нет\n",
                       s->name, (unsigned)s->channel);
                ++bad_channel;
            } else if (s->source == SRC_DIN && s->channel > 15) {
                printf("  ОШИБКА: «%s»: вход DIN_%u идёт через PCF8574, нужен SRC_PCF\n",
                       s->name, (unsigned)s->channel);
                ++bad_channel;
            } else if (s->source == SRC_PCF && s->channel <= 15) {
                printf("  ОШИБКА: «%s»: вход DIN_%u подключён напрямую, нужен SRC_DIN\n",
                       s->name, (unsigned)s->channel);
                ++bad_channel;
            }
            // Частотный вход занимает тот же вывод, что и дискретный:
            // это разные способы читать один и тот же провод.
            if (s->source != SRC_FREQ) {
                if (s->channel >= 1 && s->channel <= 23) {
                    if (busy_din[s->channel]++) {
                        printf("  ОШИБКА: «%s»: вход DIN_%u уже занят другим сигналом\n",
                               s->name, (unsigned)s->channel);
                        ++collisions;
                    }
                }
            } else if (s->channel >= 1 && s->channel <= 23) {
                // Частотный вход тоже должен быть единственным на выводе.
                if (busy_din[s->channel]++) {
                    printf("  ОШИБКА: «%s»: вход DIN_%u уже занят другим сигналом\n",
                           s->name, (unsigned)s->channel);
                    ++collisions;
                }
            }
            break;
        case SRC_AIN:
            if (s->channel >= 4) {
                printf("  ОШИБКА: «%s»: AIN%u — такого входа нет (есть 0…3)\n",
                       s->name, (unsigned)s->channel);
                ++bad_channel;
            } else if (busy_ain[s->channel]++) {
                printf("  ОШИБКА: «%s»: вход AIN%u уже занят другим сигналом\n",
                       s->name, (unsigned)s->channel);
                ++collisions;
            }
            break;
        default:
            printf("  ОШИБКА: «%s»: неизвестный источник %u\n",
                   s->name, (unsigned)s->source);
            ++bad_channel;
            break;
        }
    }
    check(bad_channel == 0, "номера входов в допустимых диапазонах");
    check(collisions == 0, "один вход — один сигнал");

    // 4. Сводка: сколько сигналов назначено (пока таблица пуста — ноль,
    //    это нормальное состояние до получения списка проводов).
    int assigned = 0, ground_switched = 0;
    for (size_t i = 0; i < count; ++i) {
        if (list[i].source != SRC_NONE) ++assigned;
        if (list[i].flags & SIG_FLAG_GROUND_SWITCHED) ++ground_switched;
    }
    printf("\n  назначено сигналов: %d из %u\n", assigned, (unsigned)count);
    printf("  проводов «на массу» (нужна подтяжка 4.7 кОм на +12 В): %d\n", ground_switched);
    if (assigned == 0)
        printf("  таблица ещё не заполнена — блок отправит нули и заглушки\n");

    printf("\n");
    if (g_failures == 0)
        printf("Все проверки пройдены.\n");
    else
        printf("Провалено проверок: %d\n", g_failures);

    return g_failures == 0 ? 0 : 1;
}
