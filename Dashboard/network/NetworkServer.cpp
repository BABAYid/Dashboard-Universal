#include "NetworkServer.h"

#include "can/CanBackend.h"

#include <QDateTime>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickImageProvider>
#include <QTcpServer>
#include <QTimer>
#include <QUrlQuery>
#include <QWebSocket>
#include <QtHttpServer/QHttpServer>
#include <QtHttpServer/QHttpServerRequest>
#include <QtHttpServer/QHttpServerResponse>
#include <QtHttpServer/QHttpServerWebSocketUpgradeResponse>

namespace {

// Контракт: docs/integration.md. Порт один на всё — HTTP и WebSocket upgrade.
constexpr int kDefaultPort = 8080;

// Кадры карты: 3 с без кадра — карта гаснет. Это не про точность, а про
// честность: показывать водителю карту минуту назад хуже, чем не показывать.
constexpr qint64 kMapFrameStaleMs = 3000;
// Подсказки навигации живут 3 с по контракту.
constexpr int kNavStaleMs = 3000;
// Ограничение размера кадра (400 КБ из контракта).
constexpr int kMaxMapFrameBytes = 400 * 1024;
// Длина служебного заголовка двоичного кадра карты.
constexpr int kMapHeaderLen = 12;

QString stateName(int result)
{
    switch (result) {
    case CanBackend::ClimateAccepted:      return QStringLiteral("accepted");
    case CanBackend::ClimateDone:          return QStringLiteral("done");
    case CanBackend::ClimateNoChange:      return QStringLiteral("no_change");
    case CanBackend::ClimateBusy:          return QStringLiteral("busy");
    case CanBackend::ClimateUnknownAction: return QStringLiteral("unknown_action");
    case CanBackend::ClimateNoPanel:       return QStringLiteral("no_panel");
    case CanBackend::ClimateNotSent:       return QStringLiteral("not_sent");
    case CanBackend::ClimateTimeout:       return QStringLiteral("timeout");
    default:                               return QStringLiteral("unknown");
    }
}

QString actionName(int action)
{
    switch (action) {
    case CanBackend::ClimateTempUp:         return QStringLiteral("temp_up");
    case CanBackend::ClimateTempDown:       return QStringLiteral("temp_down");
    case CanBackend::ClimateFanUp:          return QStringLiteral("fan_up");
    case CanBackend::ClimateFanDown:        return QStringLiteral("fan_down");
    case CanBackend::ClimateAuto:           return QStringLiteral("auto");
    case CanBackend::ClimateAc:             return QStringLiteral("ac");
    case CanBackend::ClimateRecirculation:  return QStringLiteral("recirculation");
    case CanBackend::ClimateDefrostFront:   return QStringLiteral("defrost_front");
    case CanBackend::ClimateDefrostRear:    return QStringLiteral("defrost_rear");
    case CanBackend::ClimateModeFace:       return QStringLiteral("mode_face");
    case CanBackend::ClimateModeFeet:       return QStringLiteral("mode_feet");
    case CanBackend::ClimateModeFaceFeet:   return QStringLiteral("mode_face_feet");
    case CanBackend::ClimateTempUpRight:    return QStringLiteral("temp_up_right");
    case CanBackend::ClimateTempDownRight:  return QStringLiteral("temp_down_right");
    default:                                return QString();
    }
}

int actionCode(const QString &name)
{
    if (name == QStringLiteral("temp_up"))         return CanBackend::ClimateTempUp;
    if (name == QStringLiteral("temp_down"))       return CanBackend::ClimateTempDown;
    if (name == QStringLiteral("fan_up"))          return CanBackend::ClimateFanUp;
    if (name == QStringLiteral("fan_down"))        return CanBackend::ClimateFanDown;
    if (name == QStringLiteral("auto"))            return CanBackend::ClimateAuto;
    if (name == QStringLiteral("ac"))              return CanBackend::ClimateAc;
    if (name == QStringLiteral("recirculation"))   return CanBackend::ClimateRecirculation;
    if (name == QStringLiteral("defrost_front"))   return CanBackend::ClimateDefrostFront;
    if (name == QStringLiteral("defrost_rear"))    return CanBackend::ClimateDefrostRear;
    if (name == QStringLiteral("mode_face"))       return CanBackend::ClimateModeFace;
    if (name == QStringLiteral("mode_feet"))       return CanBackend::ClimateModeFeet;
    if (name == QStringLiteral("mode_face_feet"))  return CanBackend::ClimateModeFaceFeet;
    if (name == QStringLiteral("temp_up_right"))   return CanBackend::ClimateTempUpRight;
    if (name == QStringLiteral("temp_down_right")) return CanBackend::ClimateTempDownRight;
    return 0;
}

// null вместо выдуманного нуля: в контракте «нет данных» — это null.
QJsonValue num(double value, bool valid = true)
{
    return valid && std::isfinite(value) ? QJsonValue(value) : QJsonValue();
}

} // namespace

// ============================================================================
//  Провайдер картинки: кадр карты, который прислал Android.
// ============================================================================
// QML не умеет показывать QImage напрямую, а писать JPEG на диск ради Image
// — лишняя работа и мусор в /tmp. Поэтому провайдер отдаёт из памяти, а
// смена кадра сигнализируется номером в URL (`image://mapframe/17`).
class MapFrameImageProvider : public QQuickImageProvider
{
public:
    MapFrameImageProvider()
        : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size, const QSize &) override
    {
        Q_UNUSED(id);
        const QImage frame = NetworkServer::instance()->mapFrame();
        if (size)
            *size = frame.size();
        return frame;
    }
};

QQuickImageProvider *NetworkServer::createImageProvider()
{
    return new MapFrameImageProvider;
}

// ============================================================================
//  Жизненный цикл
// ============================================================================

NetworkServer::NetworkServer(QObject *parent)
    : QObject(parent)
{
}

NetworkServer::~NetworkServer() = default;

NetworkServer *NetworkServer::instance()
{
    // Синглтон-экземпляр создаёт QML (см. main.cpp/CanBackend — та же схема).
    static NetworkServer *self = nullptr;
    if (!self) {
        self = new NetworkServer(nullptr);
        self->setObjectName(QStringLiteral("NetworkServer"));
    }
    return self;
}

int NetworkServer::start()
{
    if (m_http)
        return m_tcp ? m_tcp->serverPort() : 0;

    // Сначала слушаем порт, потом связываем: QHttpServer::bind() в Qt 6.8+
    // рассчитан на уже слушающий QTcpServer (сам он больше не слушает).
    bool ok = false;
    const int port = qEnvironmentVariableIntValue("DASHBOARD_NET_PORT", &ok);
    const quint16 listenPort = static_cast<quint16>(ok && port > 0 ? port : kDefaultPort);

    m_tcp = new QTcpServer(this);
    if (!m_tcp->listen(QHostAddress::Any, listenPort)) {
        qWarning() << "Сеть: не удалось занять порт" << listenPort << m_tcp->errorString();
        return 0;
    }

    m_http = new QHttpServer(this);
    if (!m_http->bind(m_tcp)) {
        qWarning() << "Сеть: не удалось связать QHttpServer с TCP-сервером";
        return 0;
    }

    installRoutes();

    m_http->addWebSocketUpgradeVerifier(this, [](const QHttpServerRequest &request) {
        if (request.url().path() == QLatin1String("/ws"))
            return QHttpServerWebSocketUpgradeResponse::accept();
        return QHttpServerWebSocketUpgradeResponse::passToNext();
    });
    connect(m_http, &QAbstractHttpServer::newWebSocketConnection,
            this, &NetworkServer::acceptWebSockets);
    qInfo() << "Сеть: HTTP+WS на порту" << m_tcp->serverPort()
            << "(10.0.0.1 по проекту)";

    // Телеметрия и статус для Android. Шлём только когда есть кому.
    m_carTimer = new QTimer(this);
    m_carTimer->setInterval(1000);
    connect(m_carTimer, &QTimer::timeout, this, &NetworkServer::pushCarSnapshot);
    m_carTimer->start();

    m_statusTimer = new QTimer(this);
    m_statusTimer->setInterval(5000);
    connect(m_statusTimer, &QTimer::timeout, this, &NetworkServer::pushStatus);
    m_statusTimer->start();

    m_navStaleTimer = new QTimer(this);
    m_navStaleTimer->setSingleShot(true);
    m_navStaleTimer->setInterval(kNavStaleMs);
    connect(m_navStaleTimer, &QTimer::timeout, this, &NetworkServer::checkNavStale);

    // События джойстика — в мультимедиа (правило фокуса решает Main.qml:
    // пока он сам в навигации или в настройках, он эти коды не шлёт).
    auto *can = CanBackend::instance();
    connect(can, &CanBackend::buttonEvent, this, [this](int code, bool pressed) {
        if (!pressed || m_clients.isEmpty() || !m_forwardInput)
            return;
        // NAV/BACK/OPTION/MENU остаются за приборкой всегда (правило фокуса
        // из ARCHITECTURE.md §6): это переключение видов самой приборки,
        // а не мультимедиа.
        if (code == 1 || code == 2 || code == 3 || code == 6)
            return;
        QJsonObject message;
        message.insert(QStringLiteral("type"), QStringLiteral("input"));
        message.insert(QStringLiteral("code"), inputName(code));
        message.insert(QStringLiteral("state"), QStringLiteral("press"));
        message.insert(QStringLiteral("ts"), QDateTime::currentMSecsSinceEpoch());
        sendToClients(message);
    });
    connect(can, &CanBackend::encoderTurned, this, [this](int delta) {
        if (delta == 0 || m_clients.isEmpty() || !m_forwardInput)
            return;
        QJsonObject message;
        message.insert(QStringLiteral("type"), QStringLiteral("input"));
        message.insert(QStringLiteral("code"),
                       delta > 0 ? QStringLiteral("next") : QStringLiteral("prev"));
        message.insert(QStringLiteral("state"), QStringLiteral("press"));
        message.insert(QStringLiteral("ts"), QDateTime::currentMSecsSinceEpoch());
        sendToClients(message);
    });
    connect(can, &CanBackend::climateCommandResult,
            this, &NetworkServer::onClimateResult);

    return m_tcp->serverPort();
}

QString NetworkServer::inputName(int code)
{
    switch (code) {
    case 1:  return QStringLiteral("menu");
    case 2:  return QStringLiteral("back");
    case 3:  return QStringLiteral("option");
    case 4:  return QStringLiteral("radio");
    case 5:  return QStringLiteral("media");
    case 6:  return QStringLiteral("nav");
    case 7:  return QStringLiteral("tel");
    case 8:  return QStringLiteral("up");
    case 9:  return QStringLiteral("down");
    case 10: return QStringLiteral("left");
    case 11: return QStringLiteral("right");
    case 12: return QStringLiteral("press");
    default: return QString();
    }
}

// ============================================================================
//  HTTP
// ============================================================================

void NetworkServer::installRoutes()
{
    m_http->route(QStringLiteral("/api/v1/health"), [this](const QHttpServerRequest &) {
        const auto *can = CanBackend::instance();
        QJsonObject reply;
        reply.insert(QStringLiteral("ok"), true);
        reply.insert(QStringLiteral("role"), QStringLiteral("dashboard"));
        reply.insert(QStringLiteral("version"), QStringLiteral("1.0"));
        QJsonObject bus;
        bus.insert(QStringLiteral("interface"), can->sourceName());
        bus.insert(QStringLiteral("connected"), can->connected());
        bus.insert(QStringLiteral("frames"), can->framesReceived());
        reply.insert(QStringLiteral("can"), bus);
        reply.insert(QStringLiteral("clients"), m_clients.size());
        return QHttpServerResponse(reply);
    });

    m_http->route(QStringLiteral("/api/v1/car"), [this](const QHttpServerRequest &) {
        return QHttpServerResponse(carJson());
    });

    m_http->route(QStringLiteral("/api/v1/climate"), [this](const QHttpServerRequest &) {
        return QHttpServerResponse(climateJson());
    });

    m_http->route(QStringLiteral("/api/v1/climate/command"),
                  QHttpServerRequest::Method::Post,
                  [this](const QHttpServerRequest &request) {
        const QJsonObject body = QJsonDocument::fromJson(request.body()).object();
        const QString action = body.value(QStringLiteral("action")).toString();
        const int code = actionCode(action);
        if (code == 0) {
            QJsonObject error;
            error.insert(QStringLiteral("ok"), false);
            error.insert(QStringLiteral("error"), QStringLiteral("bad_request"));
            return QHttpServerResponse(error, QHttpServerResponse::StatusCode::BadRequest);
        }
        const int hold = body.value(QStringLiteral("hold_ms")).toInt(100);
        if (hold < 50 || hold > 1000) {
            QJsonObject error;
            error.insert(QStringLiteral("ok"), false);
            error.insert(QStringLiteral("error"), QStringLiteral("bad_request"));
            return QHttpServerResponse(error, QHttpServerResponse::StatusCode::BadRequest);
        }

        const int id = CanBackend::instance()->pressClimateButton(code);
        QJsonObject reply;
        if (id >= 0) {
            // 202 Accepted: нажатие принято, исход придёт событием или в result.
            m_commands.insert(id, { action, QStringLiteral("pending"),
                                    QDateTime::currentMSecsSinceEpoch() });
            m_commandOrder.append(id);
            while (m_commandOrder.size() > 32) {
                const qint64 old = m_commandOrder.takeFirst();
                m_commands.remove(old);
            }
            reply.insert(QStringLiteral("ok"), true);
            reply.insert(QStringLiteral("id"), id);
            return QHttpServerResponse(reply, QHttpServerResponse::StatusCode::Accepted);
        }
        if (id == -2)
            reply.insert(QStringLiteral("error"), QStringLiteral("busy"));
        else if (id == -3)
            reply.insert(QStringLiteral("error"), QStringLiteral("bad_request"));
        else
            reply.insert(QStringLiteral("error"), QStringLiteral("can_unavailable"));
        reply.insert(QStringLiteral("ok"), false);
        const auto status = id == -2 ? QHttpServerResponse::StatusCode::Conflict
                                     : QHttpServerResponse::StatusCode::ServiceUnavailable;
        return QHttpServerResponse(reply, id == -3 ? QHttpServerResponse::StatusCode::BadRequest
                                                   : status);
    });

    m_http->route(QStringLiteral("/api/v1/climate/result/<arg>"),
                  [this](qint64 id) {
        const QJsonObject reply = climateResultJson(id);
        if (reply.isEmpty())
            return QHttpServerResponse(QHttpServerResponse::StatusCode::NotFound);
        return QHttpServerResponse(reply);
    });
}

QJsonObject NetworkServer::carJson() const
{
    const auto *can = CanBackend::instance();
    QJsonObject root;
    root.insert(QStringLiteral("ok"), true);
    root.insert(QStringLiteral("ts"), QDateTime::currentMSecsSinceEpoch());
    root.insert(QStringLiteral("connected"), can->connected());
    root.insert(QStringLiteral("data_valid"), can->dataValid());

    root.insert(QStringLiteral("speed_kmh"), num(can->speed()));
    root.insert(QStringLiteral("rpm"), can->rpm());
    root.insert(QStringLiteral("gear"), can->gearMode());
    root.insert(QStringLiteral("gear_lock"), can->gearLock());
    root.insert(QStringLiteral("fuel_percent"), num(can->fuelLevel()));
    root.insert(QStringLiteral("engine_temp_c"), num(can->engineTemp()));
    root.insert(QStringLiteral("outside_temp_c"), num(can->outsideTemp()));
    root.insert(QStringLiteral("voltage_v"), num(can->voltage()));
    root.insert(QStringLiteral("fuel_rate_lph"), num(can->fuelRate()));
    root.insert(QStringLiteral("oil_pressure_alarm"), can->oilPressureAlarm());

    QJsonObject lights;
    lights.insert(QStringLiteral("left_turn"), can->leftTurn());
    lights.insert(QStringLiteral("right_turn"), can->rightTurn());
    lights.insert(QStringLiteral("high_beam"), can->highBeam());
    lights.insert(QStringLiteral("low_beam"), can->lowBeam());
    lights.insert(QStringLiteral("position"), can->positionLights());
    lights.insert(QStringLiteral("fog"), can->fogLights());
    lights.insert(QStringLiteral("reverse"), can->reverseLights());
    lights.insert(QStringLiteral("brake"), can->brakeLights());
    root.insert(QStringLiteral("lights"), lights);

    QJsonObject indicators;
    indicators.insert(QStringLiteral("check_engine"), can->checkEngine());
    indicators.insert(QStringLiteral("abs"), can->absWarning());
    indicators.insert(QStringLiteral("hand_brake"), can->handBrake());
    indicators.insert(QStringLiteral("seat_belt"), can->seatBeltUnfastened());
    root.insert(QStringLiteral("indicators"), indicators);

    QJsonObject trip;
    trip.insert(QStringLiteral("distance_km"), num(can->journeyKm()));
    trip.insert(QStringLiteral("fuel_used_l"), num(can->fuelUsed()));
    trip.insert(QStringLiteral("avg_lph"), num(can->avgConsumption()));
    trip.insert(QStringLiteral("avg_speed_kmh"), num(can->avgSpeed()));
    trip.insert(QStringLiteral("range_km"), num(can->rangeKm(), can->rangeKmValid()));
    trip.insert(QStringLiteral("seconds"), can->journeySeconds());
    root.insert(QStringLiteral("trip"), trip);

    root.insert(QStringLiteral("odometer_km"), num(can->odometer()));

    QJsonObject gps;
    gps.insert(QStringLiteral("valid"), can->gpsValid());
    gps.insert(QStringLiteral("lat"), num(can->gpsLatitude(), can->gpsValid()));
    gps.insert(QStringLiteral("lon"), num(can->gpsLongitude(), can->gpsValid()));
    gps.insert(QStringLiteral("course_deg"), num(can->gpsCourse(), can->gpsValid()));
    gps.insert(QStringLiteral("speed_kmh"), can->gpsSpeed() >= 0 ? can->gpsSpeed() : -1);
    root.insert(QStringLiteral("gps"), gps);

    QJsonObject device;
    device.insert(QStringLiteral("alive"), can->deviceAlive());
    device.insert(QStringLiteral("firmware"), can->deviceFirmware());
    device.insert(QStringLiteral("uptime_s"), static_cast<qint64>(can->deviceUptimeSec()));
    device.insert(QStringLiteral("restarts"), can->deviceRestarts());
    device.insert(QStringLiteral("bus_errors"), can->deviceBusErrors());
    root.insert(QStringLiteral("device"), device);

    return root;
}

QJsonObject NetworkServer::climateJson() const
{
    const auto *can = CanBackend::instance();
    QJsonObject root;
    root.insert(QStringLiteral("ok"), true);
    root.insert(QStringLiteral("ts"), QDateTime::currentMSecsSinceEpoch());
    root.insert(QStringLiteral("valid"), can->climateValid());
    root.insert(QStringLiteral("ac"), can->climateAc());
    root.insert(QStringLiteral("auto"), can->climateAuto());
    root.insert(QStringLiteral("recirculation"), can->climateRecirculation());
    root.insert(QStringLiteral("defrost_front"), can->climateDefrost());
    root.insert(QStringLiteral("fan_auto"), can->climateFanAuto());
    root.insert(QStringLiteral("setpoint_c"), num(can->climateSetpoint()));
    root.insert(QStringLiteral("fan_level"), can->climateFanLevel());
    root.insert(QStringLiteral("airflow"), can->climateAirflow());
    root.insert(QStringLiteral("cabin_temp_c"), num(can->climateCabinTemp()));
    root.insert(QStringLiteral("evaporator_temp_c"), num(can->climateEvaporatorTemp()));
    root.insert(QStringLiteral("setpoint_right_c"), num(can->climateSetpointRight()));
    return root;
}

QJsonObject NetworkServer::climateResultJson(qint64 id) const
{
    const auto it = m_commands.constFind(id);
    if (it == m_commands.constEnd())
        return {};
    QJsonObject root;
    root.insert(QStringLiteral("ok"), true);
    root.insert(QStringLiteral("id"), id);
    root.insert(QStringLiteral("action"), it->action);
    root.insert(QStringLiteral("state"), it->state);
    return root;
}

void NetworkServer::onClimateResult(int id, int action, int result)
{
    const QString state = stateName(result);
    auto it = m_commands.find(id);
    if (it != m_commands.end())
        it->state = state;

    QJsonObject message;
    message.insert(QStringLiteral("type"), QStringLiteral("climate_result"));
    message.insert(QStringLiteral("id"), id);
    message.insert(QStringLiteral("action"), actionName(action));
    message.insert(QStringLiteral("state"), state);
    sendToClients(message);
}

// ============================================================================
//  WebSocket
// ============================================================================

void NetworkServer::acceptWebSockets()
{
    while (m_http->hasPendingWebSocketConnections()) {
        QWebSocket *socket = m_http->nextPendingWebSocketConnection().release();
        if (!socket)
            break;
        socket->setParent(this);
        m_clients.append(socket);

        connect(socket, &QWebSocket::textMessageReceived,
                this, &NetworkServer::onTextMessage);
        connect(socket, &QWebSocket::binaryMessageReceived,
                this, &NetworkServer::onBinaryMessage);
        connect(socket, &QWebSocket::disconnected,
                this, &NetworkServer::onClientDisconnected);

        qInfo() << "Сеть: клиент подключился" << socket->peerAddress().toString();
        emit clientChanged();

        // Если приборка уже в навигации — сразу просим кадры (клиент мог
        // переподключиться на ходу).
        if (m_navigationActive)
            requestMapFrames(true);
    }
}

void NetworkServer::onClientDisconnected()
{
    auto *socket = qobject_cast<QWebSocket *>(sender());
    if (socket)
        m_clients.removeAll(socket);
    if (socket)
        socket->deleteLater();

    if (m_clients.isEmpty()) {
        // Связи нет — подсказки навигации больше не обновятся.
        m_navStale = true;
        m_mapFrame = QImage();
        emit navChanged();
        emit mapFrameChanged();
    }
    emit clientChanged();
    qInfo() << "Сеть: клиент отключился, осталось" << m_clients.size();
}

void NetworkServer::sendToClients(const QJsonObject &message)
{
    if (m_clients.isEmpty())
        return;
    const QByteArray payload = QJsonDocument(message).toJson(QJsonDocument::Compact);
    for (QWebSocket *socket : std::as_const(m_clients))
        socket->sendTextMessage(QString::fromUtf8(payload));
}

void NetworkServer::sendBinaryToClients(const QByteArray &payload)
{
    for (QWebSocket *socket : std::as_const(m_clients))
        socket->sendBinaryMessage(payload);
}

void NetworkServer::requestMapFrames(bool on)
{
    QJsonObject message;
    message.insert(QStringLiteral("type"), QStringLiteral("map_subscribe"));
    message.insert(QStringLiteral("on"), on);
    if (on) {
        message.insert(QStringLiteral("max_width"), 1920);
        message.insert(QStringLiteral("max_height"), 720);
        message.insert(QStringLiteral("fps"), 1);
        message.insert(QStringLiteral("quality"), 70);
    }
    sendToClients(message);
}

void NetworkServer::onTextMessage(const QString &text)
{
    QJsonParseError error {};
    const QJsonDocument doc = QJsonDocument::fromJson(text.toUtf8(), &error);
    if (error.error != QJsonParseError::NoError)
        return;
    const QJsonObject object = doc.object();
    const QString type = object.value(QStringLiteral("type")).toString();

    if (type == QLatin1String("hello")) {
        m_clientApi = object.value(QStringLiteral("version")).toString();
        m_mapSupported = object.value(QStringLiteral("caps"))
                            .toObject()
                            .value(QStringLiteral("map_frames"))
                            .toBool(false);
        emit clientChanged();
        qInfo() << "Сеть: клиент представился, api" << m_clientApi
                << "кадры карты:" << m_mapSupported;
        return;
    }

    if (type == QLatin1String("nav")) {
        m_navActive = object.value(QStringLiteral("active")).toBool(false);
        m_navManeuver = object.value(QStringLiteral("maneuver")).toString();
        m_navDistanceM = object.value(QStringLiteral("distance_m")).toInt(-1);
        m_navStreet = object.value(QStringLiteral("street")).toString();
        m_navSpeedLimitKmh = object.value(QStringLiteral("speed_limit_kmh")).toInt(-1);
        m_navEtaSec = object.value(QStringLiteral("eta_s")).toInt(-1);
        m_navRemainingM = object.value(QStringLiteral("remaining_m")).toInt(-1);
        m_navStale = false;
        m_navStaleTimer->start();
        emit navChanged();
        return;
    }

    // Неизвестные типы игнорируем: так старый клиент не ломает новый сервер.
}

void NetworkServer::onBinaryMessage(const QByteArray &data)
{
    if (data.size() < kMapHeaderLen || data.size() > kMaxMapFrameBytes)
        return;
    if (data.at(0) != 'M' || data.at(1) != 'F')
        return;
    if (static_cast<quint8>(data.at(2)) != 1)
        return;                       // версия формата кадра

    const auto width = static_cast<quint16>((static_cast<quint8>(data.at(4)) << 8)
                                            | static_cast<quint8>(data.at(5)));
    const auto height = static_cast<quint16>((static_cast<quint8>(data.at(6)) << 8)
                                             | static_cast<quint8>(data.at(7)));
    Q_UNUSED(width);
    Q_UNUSED(height);

    const QImage frame = QImage::fromData(data.mid(kMapHeaderLen), "JPG");
    if (frame.isNull())
        return;                       // битый кадр — просто ждём следующий

    m_mapFrame = frame;
    m_mapFrameMs = QDateTime::currentMSecsSinceEpoch();
    ++m_mapFrameSeq;
    emit mapFrameChanged();
}

// ============================================================================
//  Периодика
// ============================================================================

void NetworkServer::pushCarSnapshot()
{
    if (m_clients.isEmpty())
        return;
    QJsonObject message;
    message.insert(QStringLiteral("type"), QStringLiteral("car"));
    message.insert(QStringLiteral("data"), carJson());
    sendToClients(message);
}

void NetworkServer::pushStatus()
{
    if (m_clients.isEmpty())
        return;
    const auto *can = CanBackend::instance();
    QJsonObject message;
    message.insert(QStringLiteral("type"), QStringLiteral("status"));
    message.insert(QStringLiteral("can"), can->connected());
    message.insert(QStringLiteral("clients"), m_clients.size());
    sendToClients(message);
}

void NetworkServer::checkNavStale()
{
    m_navStale = true;
    emit navChanged();
}

// ============================================================================
//  Навигация
// ============================================================================

void NetworkServer::setInputForwarding(bool on)
{
    // Правило фокуса: когда у приборки открыт свой интерактивный слой
    // (настройки или навигация), события джойстика принадлежат ей и в
    // мультимедиа не уходят. Иначе — уходят, чтобы джойстик листал
    // тач-интерфейс Android.
    m_forwardInput = on;
}

void NetworkServer::setNavigationActive(bool on)
{
    if (m_navigationActive == on)
        return;
    m_navigationActive = on;
    requestMapFrames(on);
    if (!on) {
        // Вышли из навигации — кадры больше не нужны, карту отпускаем.
        m_mapFrame = QImage();
        m_mapFrameSeq = 0;
        emit mapFrameChanged();
    }
    emit navChanged();
}

QImage NetworkServer::mapFrame() const
{
    return m_mapFrame;
}

bool NetworkServer::mapVisible() const
{
    if (!m_navigationActive || m_mapFrame.isNull())
        return false;
    return QDateTime::currentMSecsSinceEpoch() - m_mapFrameMs < kMapFrameStaleMs;
}
