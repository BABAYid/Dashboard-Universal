// ============================================================================
//  can_bus.c — отправка и приём кадров через TWAI.
//
//  Про режим работы: шина многоузловая, и если на ней некому подтверждать
//  кадры (джойстик отключён, приборка выключена, стенд без второго узла),
//  контроллер набирает ошибки и уходит в bus-off. Это не авария: can_bus_poll()
//  поднимает шину заново, а счётчик ошибок попадает в строку состояния — по
//  нему на столе сразу видно, что дело в проводке, а не в логике.
// ============================================================================
#include "can_bus.h"

#include "driver/twai.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

#include "config.h"

static const char *TAG = "can";

static QueueHandle_t s_tx_queue;      // очередь кадров на отправку
static bool          s_installed;     // драйвер TWAI установлен
static bool          s_recovering;    // мы сами отправили его в восстановление

static uint32_t s_sent;               // отправлено в контроллер
static uint32_t s_rx;                 // принято с шины
static uint32_t s_dropped;            // не ушло: очередь или шина заняты
static uint32_t s_errors;             // ошибок шины (насыщается на 65535)

// ---------------------------------------------------------------------------
//  Подготовка сообщения TWAI. Отдельная функция, чтобы оба пути отправки
//  (немедленный и через очередь) собирали кадр одинаково: классический CAN,
//  11-битный ID, ровно 8 байт.
// ---------------------------------------------------------------------------
static void fill_message(twai_message_t *msg, uint32_t id,
                         const uint8_t data[CAN_FRAME_BYTES])
{
    msg->identifier = id;
    msg->data_length_code = CAN_FRAME_BYTES;
    msg->extd = 0;          // 11-битный ID: приборка разбирает только такие
    msg->rtr = 0;           // кадр данных, не запрос
    msg->ss = 0;
    msg->self = 0;
    msg->dlc_non_comp = 0;
    for (int i = 0; i < CAN_FRAME_BYTES; ++i)
        msg->data[i] = data[i];
}

esp_err_t can_bus_init(void)
{
    // Очередь создаётся один раз: can_bus_init() вызывается повторно, когда
    // шина не поднялась с первого раза, и второй xQueueCreate() утёк бы.
    if (s_tx_queue == NULL) {
        s_tx_queue = xQueueCreate(CAN_TX_QUEUE_LEN, sizeof(can_frame_t));
        if (s_tx_queue == NULL) {
            ESP_LOGE(TAG, "не хватило памяти на очередь отправки (%d кадров)",
                     CAN_TX_QUEUE_LEN);
            return ESP_ERR_NO_MEM;
        }
    }

    if (s_installed) {
        // Шина уже поднята — повторный вызов ничего не меняет. Так задача
        // передачи спокойно вызывает init() раз в цикл, не проверяя флаги.
        return ESP_OK;
    }

    twai_general_config_t general = TWAI_GENERAL_CONFIG_DEFAULT(
        PIN_CAN_TX, PIN_CAN_RX, TWAI_MODE_NORMAL);
    // Очереди внутри драйвера: передача идёт из одной задачи, поэтому
    // очередь TX небольшая; RX с запасом — на шине живёт ещё блок сбора
    // (~90 кадров в секунду), и кадры не должны теряться, пока задача приёма
    // печатает лог.
    general.tx_queue_len = 8;
    general.rx_queue_len = 32;

    twai_timing_config_t timing = TWAI_TIMING_CONFIG_500KBITS();
    // Фильтр «принимать всё»: на шине висят и кадры блока сбора, из которых
    // нам нужен только 0x200. Отсекать их аппаратно незачем — разбор дешевле
    // сопровождения таблицы фильтров, а лишний принятый кадр ничего не ломает.
    twai_filter_config_t filter = TWAI_FILTER_CONFIG_ACCEPT_ALL();

    esp_err_t err = twai_driver_install(&general, &timing, &filter);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "драйвер TWAI не установился: %s", esp_err_to_name(err));
        return err;
    }

    err = twai_start();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "шина CAN не запустилась: %s", esp_err_to_name(err));
        twai_driver_uninstall();
        return err;
    }

    s_installed = true;
    s_recovering = false;
    ESP_LOGI(TAG, "CAN поднят: %d кбит/с, 11-бит ID, 8 байт, TX=GPIO%d, RX=GPIO%d",
             CAN_BITRATE_KBPS, PIN_CAN_TX, PIN_CAN_RX);
    return ESP_OK;
}

bool can_bus_is_ready(void)
{
    return s_installed;
}

bool can_bus_transmit(uint32_t id, const uint8_t data[CAN_FRAME_BYTES])
{
    if (!s_installed)
        return false;

    twai_message_t msg;
    fill_message(&msg, id, data);

    // 5 мс — не «ждать любой ценой», а просто не отдавать кадр в момент,
    // когда контроллер ещё не освободил очередь. Если и за 5 мс не вышло,
    // кадр бесполезен: события джойстика стареют быстрее.
    esp_err_t err = twai_transmit(&msg, pdMS_TO_TICKS(5));
    if (err != ESP_OK) {
        ++s_dropped;
        return false;
    }
    ++s_sent;
    return true;
}

bool can_bus_send(uint32_t id, const uint8_t data[CAN_FRAME_BYTES])
{
    if (s_tx_queue == NULL) {
        ++s_dropped;
        return false;
    }

    can_frame_t frame;
    frame.id = id;
    for (int i = 0; i < CAN_FRAME_BYTES; ++i)
        frame.data[i] = data[i];

    // Не ждём: задача приёма не имеет права стоять из-за занятой шины —
    // пока она ждёт, джойстик продолжает присылать события.
    if (xQueueSend(s_tx_queue, &frame, 0) != pdTRUE) {
        ++s_dropped;
        return false;
    }
    return true;
}

bool can_bus_tx_wait(can_frame_t *frame, uint32_t timeout_ms)
{
    if (s_tx_queue == NULL)
        return false;
    return xQueueReceive(s_tx_queue, frame, pdMS_TO_TICKS(timeout_ms)) == pdTRUE;
}

bool can_bus_receive(uint32_t *id, uint8_t *dlc, uint8_t data[CAN_FRAME_BYTES],
                     uint32_t timeout_ms)
{
    if (!s_installed)
        return false;

    twai_message_t msg;
    if (twai_receive(&msg, pdMS_TO_TICKS(timeout_ms)) != ESP_OK)
        return false;

    *id = msg.identifier & 0x1FFFFFFFu;

    // Классический CAN обещает 8 байт, но DLC приходит из железа и доверять
    // ему вслепую нельзя: всё, что больше 8, — это уже CAN FD, которого у
    // нас нет. Обрезаем, чтобы не читать за границей буфера.
    uint8_t len = msg.data_length_code;
    if (len > CAN_FRAME_BYTES)
        len = CAN_FRAME_BYTES;
    *dlc = len;
    for (uint8_t i = 0; i < len; ++i)
        data[i] = msg.data[i];
    for (uint8_t i = len; i < CAN_FRAME_BYTES; ++i)
        data[i] = 0;

    ++s_rx;
    return true;
}

void can_bus_poll(void)
{
    if (!s_installed)
        return;

    twai_status_info_t info;
    if (twai_get_status_info(&info) != ESP_OK)
        return;

    // Ошибки шины — это счётчик железа: он и показывается в строке
    // состояния. Свой счётчик не ведём, чтобы не удваивать одно и то же.
    s_errors = info.bus_error_count;

    if (info.state == TWAI_STATE_BUS_OFF) {
        // Нет подтверждения кадров: джойстик не подключён, приборка выключена
        // или оборван провод. Запускаем восстановление — контроллер сам
        // отсидит 128×11 рецессивных бит и перейдёт в STOPPED.
        ESP_LOGW(TAG, "шина ушла в bus-off (кадры не подтверждаются) — поднимаю заново");
        if (twai_initiate_recovery() == ESP_OK)
            s_recovering = true;
    } else if (info.state == TWAI_STATE_STOPPED && s_recovering) {
        // Восстановление закончилось — снова в работу. Состояние STOPPED
        // бывает и до первого запуска, но этот случай закрыт флагом: шину
        // здесь запускает только восстановление.
        if (twai_start() == ESP_OK) {
            ESP_LOGI(TAG, "шина снова в работе");
            s_recovering = false;
        }
    }
}

uint32_t can_bus_frames_sent(void)
{
    return s_sent;
}

uint32_t can_bus_frames_received(void)
{
    return s_rx;
}

uint32_t can_bus_frames_dropped(void)
{
    return s_dropped;
}

uint32_t can_bus_error_count(void)
{
    return s_errors;
}

const char *can_bus_state_name(void)
{
    if (!s_installed)
        return "не поднята";

    twai_status_info_t info;
    if (twai_get_status_info(&info) != ESP_OK)
        return "нет данных";
    switch (info.state) {
    case TWAI_STATE_STOPPED: return "остановлена";
    case TWAI_STATE_RUNNING: return "работает";
    case TWAI_STATE_BUS_OFF: return "bus-off";
    case TWAI_STATE_RECOVERING: return "восстановление";
    default: return "неизвестно";
    }
}
