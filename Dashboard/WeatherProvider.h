#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QTimer>

class QNetworkAccessManager;
class QNetworkReply;
class QQmlEngine;
class QJSEngine;

// ============================================================================
//  Погода за окном — для фона приборки (дождь/снег на панели).
//
//  Источник — Open-Meteo (https://open-meteo.com), бесплатный, без ключа
//  и регистрации:  GET /v1/forecast?latitude=..&longitude=..&current=weather_code
//  Запрос раз в 10 минут; сеть может отсутствовать — тогда state остаётся
//  "unknown", дождь/снег просто не рисуется, приборка работает как обычно.
//
//  Коды WMO (weather_code) сводятся к четырём категориям, которые нужны
//  интерфейсу: clear | cloudy | fog | rain | snow.
//
//  В режиме --mock (без сети): состояние меняется по кругу раз в 8 секунд
//  rain → snow → clear → ..., чтобы эффект было видно на столе.
//
//  Класс зарегистрирован как синглтон QML: в QML доступен как WeatherProvider
//  (см. WeatherFx.qml).
// ============================================================================
class WeatherProvider : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString description READ description NOTIFY stateChanged)
    Q_PROPERTY(bool available READ available NOTIFY stateChanged)
    Q_PROPERTY(double temperature READ temperature NOTIFY stateChanged)

public:
    // Без аргумента по умолчанию — иначе QML создаст ВТОРОЙ экземпляр
    // (как в CanBackend); с create() без default-конструктора QML берёт
    // именно тот объект, что настроил main.cpp.
    explicit WeatherProvider(QObject *parent);

    static WeatherProvider *instance();
    static WeatherProvider *create(QQmlEngine *, QJSEngine *) { return instance(); }

    // Координаты, для которых запрашивается погода (по умолчанию Москва).
    void setLocation(double latitude, double longitude);

    // --mock: без сети, состояния меняются по кругу (для демонстрации).
    void setMockMode(bool mock);

    void start();

    QString state() const { return m_state; }
    QString description() const { return m_description; }
    bool available() const { return !m_state.isEmpty() && m_state != QStringLiteral("unknown"); }
    double temperature() const { return m_temperature; }

    // Сведение WMO-кода к категории (public static — удобно тестировать).
    static QString stateFromCode(int weatherCode);
    static QString descriptionFromCode(int weatherCode);

signals:
    void stateChanged();

private:
    void fetchWeather();
    void handleReply(QNetworkReply *reply);
    void apply(int weatherCode, double temperature, const QString &description);
    void updateMock();
    void setState(const QString &state, const QString &description);

    QNetworkAccessManager *m_network = nullptr;
    QTimer m_pollTimer;      // реальный режим: раз в 10 минут
    QTimer m_mockTimer;      // демо-режим: раз в 8 секунд

    double m_latitude = 55.7558;
    double m_longitude = 37.6173;
    QString m_state = QStringLiteral("unknown");
    QString m_description;
    double m_temperature = 0.0;
    int m_mockIndex = -1;
    bool m_started = false;
};
