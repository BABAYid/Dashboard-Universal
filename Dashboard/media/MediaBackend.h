#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QTimer>

class QNetworkAccessManager;
class QNetworkReply;
class QJsonObject;
class QQmlEngine;
class QJSEngine;

// ============================================================================
//  Что играет в мультимедиа-центре — для виджета на приборке.
//
//  Владелец медиа — Android-блок (RK3568), приборка только спрашивает. Поэтому
//  данные идут НЕ по CAN (8 байт на кадр для названия трека мало, а кириллица
//  и обложки туда не влезут), а по сети: маленький JSON.
//
//  Контракт (см. ARCHITECTURE.md, раздел «Протоколы»):
//      GET http://<медиацентр>:8080/api/media
//      { "source": "fm", "station": "Русское Радио",
//        "title": "Название", "artist": "Исполнитель",
//        "playing": true, "position": 42, "duration": 210,
//        "art": "http://..." }
//
//  Опрос раз в секунду: медиа меняется медленнее приборов, а лишний трафик
//  в машине ни к чему. Если сети нет или сервис молчит дольше 4 секунд,
//  available = false и виджет честно пишет «нет данных», а не показывает
//  вчерашний трек.
//
//  Адрес задаётся в QSettings (media/url) — на устройстве удобно прописать
//  IP медиацентра один раз.
//
//  В режиме --mock данные выдумываются и меняются раз в 5 секунд, чтобы
//  виджет можно было верстать без Android-блока.
//
//  Класс зарегистрирован как синглтон QML: в QML доступен как MediaBackend.
// ============================================================================
class MediaBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(QString title READ title NOTIFY changed)
    Q_PROPERTY(QString artist READ artist NOTIFY changed)
    Q_PROPERTY(QString station READ station NOTIFY changed)
    Q_PROPERTY(QString source READ source NOTIFY changed)          // fm/bt/usb/stream
    Q_PROPERTY(QString sourceLabel READ sourceLabel NOTIFY changed) // «FM», «Bluetooth»…
    Q_PROPERTY(bool playing READ playing NOTIFY changed)
    Q_PROPERTY(int positionSec READ positionSec NOTIFY changed)
    Q_PROPERTY(int durationSec READ durationSec NOTIFY changed)
    Q_PROPERTY(QString artUrl READ artUrl NOTIFY changed)

public:
    // Без аргумента по умолчанию — иначе QML создаст ВТОРОЙ экземпляр
    // (как в CanBackend и WeatherProvider).
    explicit MediaBackend(QObject *parent);

    static MediaBackend *instance();
    static MediaBackend *create(QQmlEngine *, QJSEngine *) { return instance(); }

    void setMockMode(bool mock);
    void start();

    bool available() const { return m_available; }
    QString title() const { return m_title; }
    QString artist() const { return m_artist; }
    QString station() const { return m_station; }
    QString source() const { return m_source; }
    QString sourceLabel() const;
    bool playing() const { return m_playing; }
    int positionSec() const { return m_positionSec; }
    int durationSec() const { return m_durationSec; }
    QString artUrl() const { return m_artUrl; }

    // Время в виде «1:23» — одинаково для позиции и длительности.
    Q_INVOKABLE QString formatTime(int seconds) const;

signals:
    void changed();

private:
    void poll();
    void handleReply(QNetworkReply *reply);
    void applyJson(const QJsonObject &object);
    void updateMock();
    void setUnavailable();

    QNetworkAccessManager *m_network = nullptr;
    QTimer m_pollTimer;       // реальный режим: раз в секунду
    QTimer m_mockTimer;       // демо-режим: раз в 5 секунд
    QString m_url;            // адрес сервиса медиацентра

    bool m_available = false;
    QString m_title;
    QString m_artist;
    QString m_station;
    QString m_source;
    bool m_playing = false;
    int m_positionSec = 0;
    int m_durationSec = 0;
    QString m_artUrl;
    int m_missedPolls = 0;    // сколько опросов подряд не дали ответа
    int m_mockIndex = -1;
    bool m_started = false;
};
