#include "GpsBackend.h"

#include <QCoreApplication>
#include <QDebug>
#include <QElapsedTimer>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTcpSocket>
#include <QTimer>

namespace {

// "host:port" из DASHBOARD_GPSD; по умолчанию — локальный gpsd.
bool parseGpsdAddress(const QByteArray &raw, QString *host, quint16 *port)
{
    if (raw.isEmpty())
        return false;
    const QString text = QString::fromLocal8Bit(raw).trimmed();
    const int colon = text.lastIndexOf(QLatin1Char(':'));
    if (colon <= 0 || colon >= text.size() - 1)
        return false;
    const QString h = text.left(colon);
    bool ok = false;
    const int p = text.mid(colon + 1).toInt(&ok);
    if (!ok || p <= 0 || p > 65535)
        return false;
    *host = h;
    *port = static_cast<quint16>(p);
    return true;
}

} // namespace

GpsBackend::GpsBackend(QObject *parent)
    : QObject(parent)
    , m_socket(new QTcpSocket(this))
    , m_tick(new QTimer(this))
    , m_retry(new QTimer(this))
{
    parseGpsdAddress(qgetenv("DASHBOARD_GPSD"), &m_host, &m_port);

    // Раз в секунду обновляем возраст координат и валидность: контракт
    // разрешает держать последнюю позицию не дольше 5 секунд.
    m_tick->setInterval(1000);
    connect(m_tick, &QTimer::timeout, this, &GpsBackend::checkStaleness);

    // gpsd на плате может подняться позже приборки — пробуем снова.
    m_retry->setInterval(2000);
    m_retry->setSingleShot(true);
    connect(m_retry, &QTimer::timeout, this, &GpsBackend::tryReconnect);

    connect(m_socket, &QTcpSocket::connected, this, &GpsBackend::onConnected);
    connect(m_socket, &QTcpSocket::readyRead, this, &GpsBackend::onReadyRead);
    connect(m_socket, &QTcpSocket::disconnected, this, &GpsBackend::onDisconnected);
#if QT_VERSION >= QT_VERSION_CHECK(5, 15, 0)
    connect(m_socket, &QTcpSocket::errorOccurred, this, &GpsBackend::onSocketError);
#else
    connect(m_socket, QOverload<QAbstractSocket::SocketError>::of(&QTcpSocket::error),
            this, &GpsBackend::onSocketError);
#endif
}

GpsBackend::~GpsBackend() = default;

GpsBackend *GpsBackend::instance()
{
    // Как у CanBackend: объект принадлежит приложению, деструктор не должен
    // работать после разрушения QGuiApplication.
    static GpsBackend *backend = nullptr;
    if (!backend)
        backend = new GpsBackend(qApp);
    return backend;
}

void GpsBackend::start()
{
    m_tick->start();
    openConnection();
}

void GpsBackend::openConnection()
{
    if (m_socket->state() == QAbstractSocket::ConnectedState
        || m_socket->state() == QAbstractSocket::ConnectingState)
        return;
    qInfo().noquote() << "GPS: подключаюсь к gpsd" << m_host << m_port;
    m_socket->connectToHost(m_host, m_port);
}

void GpsBackend::tryReconnect()
{
    if (m_socket->state() == QAbstractSocket::UnconnectedState)
        openConnection();
}

void GpsBackend::onConnected()
{
    m_source = QStringLiteral("gpsd:%1:%2").arg(m_host).arg(m_port);
    emit sourceNameChanged();
    qInfo().noquote() << "GPS: связь с gpsd есть, жду фикс";

    // Включаем поток JSON-сообщений (TPV/SKY/GSA и т.д.). gpsd отвечает
    // на строку-команду кадрами, поэтому просить нужно именно так.
    m_socket->write("?WATCH={\"enable\":true,\"json\":true}\r\n");
}

void GpsBackend::onDisconnected()
{
    if (m_source != QStringLiteral("нет связи")) {
        m_source = QStringLiteral("нет связи");
        emit sourceNameChanged();
    }
    setValid(false);
    qInfo().noquote() << "GPS: gpsd отключился, повтор через 2 с";
    m_retry->start();
}

void GpsBackend::onSocketError()
{
    // Соединение не поднялось (или оборвалось) — ждём и пробуем снова.
    // Логируем только при переходе «был/нет», чтобы не спамить каждые 2 с.
    if (m_socket->state() == QAbstractSocket::UnconnectedState) {
        if (m_source != QStringLiteral("нет связи")) {
            m_source = QStringLiteral("нет связи");
            emit sourceNameChanged();
        }
        m_retry->start();
    }
}

void GpsBackend::onReadyRead()
{
    // gpsd шлёт по строке на кадр; буферизуем до '\n' и разбираем.
    static QByteArray buffer;
    buffer += m_socket->readAll();
    int nl = buffer.indexOf('\n');
    while (nl >= 0) {
        const QByteArray line = buffer.left(nl).trimmed();
        buffer.remove(0, nl + 1);
        if (!line.isEmpty() && line.startsWith('{'))
            parseLine(line);
        nl = buffer.indexOf('\n');
    }
}

void GpsBackend::parseLine(const QByteArray &line)
{
    const QJsonDocument doc = QJsonDocument::fromJson(line);
    if (!doc.isObject())
        return;
    const QJsonObject obj = doc.object();
    const QString cls = obj.value(QStringLiteral("class")).toString();

    if (cls == QLatin1String("TPV"))
        applyTpv(obj);
    else if (cls == QLatin1String("SKY"))
        applySky(obj);
    // VERSION/DEVICE/GST/WATCH/ERROR — для карты не нужны.
}

void GpsBackend::applyTpv(const QJsonObject &tpv)
{
    // QJsonValue::toInt() принимает только значение по умолчанию; если
    // поля "mode" нет — считаем, что фикса нет.
    const int mode = tpv.value(QStringLiteral("mode")).toInt(0);

    // 0 — нет данных, 1 — нет фикса, 2 — 2D, 3 — 3D. Координаты без фикса
    // отдавать нельзя: навигатор уведёт машину по пустому полю.
    const double lat = tpv.value(QStringLiteral("lat")).toDouble(qQNaN());
    const double lon = tpv.value(QStringLiteral("lon")).toDouble(qQNaN());
    const bool fixed = mode >= 2 && std::isfinite(lat) && std::isfinite(lon);

    const double track = tpv.value(QStringLiteral("track")).toDouble(qQNaN());
    // gpsd отдаёт скорость в м/с, у нас в приборке — км/ч.
    const double speedMs = tpv.value(QStringLiteral("speed")).toDouble(qQNaN());
    const double speedKmh = std::isfinite(speedMs) ? speedMs * 3.6 : qQNaN();

    const QString utc = tpv.value(QStringLiteral("time")).toString();

    if (utc != m_utc) {
        m_utc = utc;
        emit utcTimeChanged();
    }
    if (mode != m_fixType) {
        m_fixType = mode;
        emit fixTypeChanged();
    }
    if (std::isfinite(track) != std::isfinite(m_course)
        || (std::isfinite(track) && qAbs(track - m_course) > 0.01)) {
        m_course = track;
        emit courseChanged();
    }
    if (std::isfinite(speedKmh) != std::isfinite(m_speedKmh)
        || (std::isfinite(speedKmh) && qAbs(speedKmh - m_speedKmh) > 0.01)) {
        m_speedKmh = speedKmh;
        emit speedKmhChanged();
    }

    if (!fixed) {
        setValid(false);
        return;
    }

    if (!m_hasFix || lat != m_lat) {
        m_lat = lat;
        emit latitudeChanged();
    }
    if (!m_hasFix || lon != m_lon) {
        m_lon = lon;
        emit longitudeChanged();
    }

    m_hasFix = true;
    m_lastFix.restart();
    m_ageMs = 0;
    emit ageMsChanged();
    setValid(true);
    emit positionUpdated(m_lat, m_lon, m_course, m_speedKmh);
}

void GpsBackend::applySky(const QJsonObject &sky)
{
    const QJsonArray sats = sky.value(QStringLiteral("satellites")).toArray();
    int used = 0;
    for (const QJsonValue &v : sats) {
        const QJsonObject s = v.toObject();
        if (s.value(QStringLiteral("used")).toBool())
            ++used;
    }
    // gpsd в части сборок кладёт просто число спутников в "nSat"/"uSat".
    int n = sats.size();
    if (sky.contains(QStringLiteral("uSat")))
        n = sky.value(QStringLiteral("uSat")).toInt(n);
    if (used == 0)
        used = n; // кто-то из них всё равно используется для фикса

    if (used != m_satellites) {
        m_satellites = used;
        emit satellitesChanged();
    }

    const double hdop = sky.value(QStringLiteral("hdop")).toDouble(qQNaN());
    if (std::isfinite(hdop) != std::isfinite(m_hdop)
        || (std::isfinite(hdop) && qAbs(hdop - m_hdop) > 0.001)) {
        m_hdop = hdop;
        emit hdopChanged();
    }
}

void GpsBackend::checkStaleness()
{
    if (!m_hasFix) {
        m_ageMs = -1;
        emit ageMsChanged();
        setValid(false);
        return;
    }
    m_ageMs = static_cast<int>(m_lastFix.elapsed());
    emit ageMsChanged();
    // Контракт: дольше 5 с старую позицию держать нельзя.
    if (m_ageMs > 5000)
        setValid(false);
}

void GpsBackend::setValid(bool on)
{
    if (m_valid == on)
        return;
    m_valid = on;
    if (on)
        qInfo().noquote() << "GPS: фикс" << (m_fixType == 3 ? "3D" : "2D");
    emit validChanged();
}
