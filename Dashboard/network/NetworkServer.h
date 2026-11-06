#pragma once

#include <QHash>
#include <QImage>
#include <QJsonObject>
#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QVector>

class CanBackend;
class QHttpServer;
class QTcpServer;
class QWebSocket;
class QTimer;
class QQuickImageProvider;

// ============================================================================
//  СЕТЕВОЙ СЛОЙ ПРИБОРКИ (docs/integration.md)
// ============================================================================
//
// Приборка — сервер: раздаёт данные машины и климат по HTTP, держит
// WebSocket для событий в обе стороны и принимает от мультимедиа подсказки
// навигации и кадры карты.
//
// Почему отдельный класс, а не метод в CanBackend: CanBackend про шину и
// ничего не знает про HTTP, а здесь — сеть и протокол интеграции. Связь
// односторонняя: сеть спрашивает у CanBackend, шина про сеть не знает.
//
// HTTP и WebSocket живут на одном порту (8080): QHttpServer умеет принимать
// upgrade на /ws, поэтому второй порт не нужен.
class NetworkServer : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // --- состояние связи с мультимедиа ---
    Q_PROPERTY(bool clientConnected READ clientConnected NOTIFY clientChanged)
    Q_PROPERTY(QString clientApi READ clientApi NOTIFY clientChanged)
    Q_PROPERTY(bool mapSupported READ mapSupported NOTIFY clientChanged)

    // --- навигация от Android ---
    Q_PROPERTY(bool navActive READ navActive NOTIFY navChanged)
    Q_PROPERTY(QString navManeuver READ navManeuver NOTIFY navChanged)
    Q_PROPERTY(int navDistanceM READ navDistanceM NOTIFY navChanged)
    Q_PROPERTY(QString navStreet READ navStreet NOTIFY navChanged)
    Q_PROPERTY(int navSpeedLimitKmh READ navSpeedLimitKmh NOTIFY navChanged)
    Q_PROPERTY(int navEtaSec READ navEtaSec NOTIFY navChanged)
    Q_PROPERTY(int navRemainingM READ navRemainingM NOTIFY navChanged)
    // Подсказки устарели (3 с без сообщений) — показывать нельзя
    Q_PROPERTY(bool navStale READ navStale NOTIFY navChanged)

    // --- кадры карты от Android ---
    Q_PROPERTY(int mapFrameSeq READ mapFrameSeq NOTIFY mapFrameChanged)
    // Кадр есть, он свежий и навигация активна — только тогда рисуем карту
    Q_PROPERTY(bool mapVisible READ mapVisible NOTIFY mapFrameChanged)

public:
    explicit NetworkServer(QObject *parent = nullptr);
    ~NetworkServer() override;

    static NetworkServer *instance();
    static NetworkServer *create(QQmlEngine *, QJSEngine *) { return instance(); }

    // Поднять HTTP+WS. Вызывается из main.cpp после создания CanBackend.
    // Возвращает номер порта (0 — не удалось).
    Q_INVOKABLE int start();

    // Приборка вошла/вышла из навигационного режима. Отсюда же уходит
    // подписка на кадры карты: в обычном режиме картинка не нужна.
    Q_INVOKABLE void setNavigationActive(bool on);

    // Текущий кадр карты для QQuickImageProvider (`image://mapframe/<seq>`).
    QImage mapFrame() const;

    // Провайдер картинки для QML: engine.addImageProvider("mapframe", …).
    // Вынесено в фабрику, чтобы main.cpp не знал про внутренний класс.
    static QQuickImageProvider *createImageProvider();

    bool clientConnected() const { return !m_clients.isEmpty(); }
    QString clientApi() const { return m_clientApi; }
    bool mapSupported() const { return m_mapSupported; }

    bool navActive() const { return m_navActive; }
    QString navManeuver() const { return m_navManeuver; }
    int navDistanceM() const { return m_navDistanceM; }
    QString navStreet() const { return m_navStreet; }
    int navSpeedLimitKmh() const { return m_navSpeedLimitKmh; }
    int navEtaSec() const { return m_navEtaSec; }
    int navRemainingM() const { return m_navRemainingM; }
    bool navStale() const { return m_navStale; }
    int mapFrameSeq() const { return m_mapFrameSeq; }
    bool mapVisible() const;

signals:
    void clientChanged();
    void navChanged();
    void mapFrameChanged();

private slots:
    void onTextMessage(const QString &text);
    void onBinaryMessage(const QByteArray &data);
    void onClimateResult(int id, int action, int result);
    void pushCarSnapshot();
    void pushStatus();
    void checkNavStale();

private:
    void installRoutes();
    void acceptWebSockets();
    void onClientDisconnected();
    void sendToClients(const QJsonObject &message);
    void sendBinaryToClients(const QByteArray &payload);
    void requestMapFrames(bool on);

    QJsonObject carJson() const;
    QJsonObject climateJson() const;
    QJsonObject climateResultJson(qint64 id) const;

    // Имя действия из InputController.qml → тот же код для Android.
    static QString inputName(int code);

    QHttpServer *m_http = nullptr;
    QTcpServer *m_tcp = nullptr;
    QVector<QWebSocket *> m_clients;

    QTimer *m_carTimer = nullptr;
    QTimer *m_statusTimer = nullptr;
    QTimer *m_navStaleTimer = nullptr;

    QString m_clientApi;
    bool m_mapSupported = false;
    bool m_navigationActive = false;   // приборка в навигационном режиме

    bool m_navActive = false;
    QString m_navManeuver;
    int m_navDistanceM = -1;
    QString m_navStreet;
    int m_navSpeedLimitKmh = -1;
    int m_navEtaSec = -1;
    int m_navRemainingM = -1;
    bool m_navStale = false;

    QImage m_mapFrame;
    int m_mapFrameSeq = 0;
    qint64 m_mapFrameMs = 0;          // локальное время последнего кадра

    // Команды климату: id → результат (последние 32, старые вытесняются)
    struct CommandRecord {
        QString action;
        QString state;                // pending/accepted/done/…
        qint64 ts = 0;
    };
    QHash<qint64, CommandRecord> m_commands;
    QVector<qint64> m_commandOrder;
};
