#include "MediaBackend.h"

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QUrl>

// ============================================================================
//  Опрос сервиса медиацентра. Запросы асинхронные, ошибки не фатальны:
//  нет сети — виджет просто показывает «нет данных».
// ============================================================================

namespace {

constexpr int kPollIntervalMs = 1000;     // раз в секунду
constexpr int kMockIntervalMs = 5000;     // демо: раз в 5 секунд
constexpr int kMaxMissedPolls = 4;        // 4 секунды без ответа — «нет данных»
const char *kDefaultUrl = "http://127.0.0.1:8080/api/media";

} // namespace

MediaBackend::MediaBackend(QObject *parent)
    : QObject(parent)
{
    m_url = QString::fromLatin1(kDefaultUrl);

    m_pollTimer.setInterval(kPollIntervalMs);
    m_pollTimer.setSingleShot(false);
    connect(&m_pollTimer, &QTimer::timeout, this, &MediaBackend::poll);

    m_mockTimer.setInterval(kMockIntervalMs);
    m_mockTimer.setSingleShot(false);
    connect(&m_mockTimer, &QTimer::timeout, this, &MediaBackend::updateMock);
}

MediaBackend *MediaBackend::instance()
{
    static MediaBackend *backend = nullptr;
    if (!backend)
        backend = new MediaBackend(qApp);
    return backend;
}

void MediaBackend::setMockMode(bool mock)
{
    if (mock) {
        m_pollTimer.stop();
        m_mockTimer.start();
        updateMock();
    } else {
        m_mockTimer.stop();
        m_pollTimer.start();
    }
}

void MediaBackend::start()
{
    if (m_started)
        return;
    m_started = true;

    // Адрес медиацентра можно прописать в QSettings (media/url): на устройстве
    // это удобнее, чем пересобирать. По умолчанию — локальный сервис.
    {
        QSettings settings;
        m_url = settings.value(QStringLiteral("media/url"), m_url).toString();
    }

    if (!m_mockTimer.isActive()) {
        m_pollTimer.start();
        QTimer::singleShot(1500, this, &MediaBackend::poll);   // не мешаем старту QML
    }
}

QString MediaBackend::sourceLabel() const
{
    if (m_source == QLatin1String("fm"))
        return QStringLiteral("FM");
    if (m_source == QLatin1String("bt"))
        return QStringLiteral("Bluetooth");
    if (m_source == QLatin1String("usb"))
        return QStringLiteral("USB");
    if (m_source == QLatin1String("stream"))
        return QStringLiteral("Стрим");
    return m_source.isEmpty() ? QString() : m_source;
}

QString MediaBackend::formatTime(int seconds) const
{
    if (seconds <= 0)
        return QStringLiteral("0:00");
    const int minutes = seconds / 60;
    const int rest = seconds % 60;
    return QStringLiteral("%1:%2")
        .arg(minutes)
        .arg(rest, 2, 10, QLatin1Char('0'));
}

// --------------------------------------------------------------------- опрос

void MediaBackend::poll()
{
    if (m_network == nullptr) {
        m_network = new QNetworkAccessManager(this);
        connect(m_network, &QNetworkAccessManager::finished,
                this, &MediaBackend::handleReply);
    }

    // Фигурные скобки: с обычными здесь получается «самый неприятный разбор»
    // (most vexing parse) — компилятор считает это объявлением функции.
    QNetworkRequest request{QUrl(m_url)};
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("appDashboard/1.0"));
    m_network->get(request);
}

void MediaBackend::handleReply(QNetworkReply *reply)
{
    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError) {
        // Медиацентра может не быть вовсе (стол, отладка) — это штатно.
        // Пишем только переход в «нет данных», чтобы не забивать лог каждую секунду.
        if (m_available)
            qInfo() << "Медиа: нет связи —" << reply->errorString();
        if (++m_missedPolls >= kMaxMissedPolls)
            setUnavailable();
        return;
    }

    const QByteArray data = reply->readAll();
    const QJsonDocument document = QJsonDocument::fromJson(data);
    if (!document.isObject()) {
        if (++m_missedPolls >= kMaxMissedPolls)
            setUnavailable();
        return;
    }

    m_missedPolls = 0;
    applyJson(document.object());
}

void MediaBackend::applyJson(const QJsonObject &object)
{
    const QString title = object.value(QStringLiteral("title")).toString();
    const QString artist = object.value(QStringLiteral("artist")).toString();
    const QString station = object.value(QStringLiteral("station")).toString();
    const QString source = object.value(QStringLiteral("source")).toString();
    const bool playing = object.value(QStringLiteral("playing")).toBool();
    const int position = object.value(QStringLiteral("position")).toInt();
    const int duration = object.value(QStringLiteral("duration")).toInt();
    const QString art = object.value(QStringLiteral("art")).toString();

    const bool trackChanged = !m_available
        || m_title != title || m_artist != artist
        || m_station != station || m_source != source;
    const bool changedFlag = trackChanged
        || m_playing != playing || m_positionSec != position
        || m_durationSec != duration || m_artUrl != art;

    m_available = true;
    m_title = title;
    m_artist = artist;
    m_station = station;
    m_source = source;
    m_playing = playing;
    m_positionSec = position;
    m_durationSec = duration;
    m_artUrl = art;

    if (trackChanged)
        qInfo() << "Медиа:" << sourceLabel() << station << "|" << title
                << "-" << artist << (playing ? "(играет)" : "(пауза)");

    if (changedFlag)
        emit changed();
}

void MediaBackend::setUnavailable()
{
    m_missedPolls = 0;
    if (!m_available && m_title.isEmpty())
        return;
    m_available = false;
    m_playing = false;
    m_title.clear();
    m_artist.clear();
    m_station.clear();
    m_source.clear();
    m_positionSec = 0;
    m_durationSec = 0;
    m_artUrl.clear();
    emit changed();
}

// --------------------------------------------------------------------- демо

void MediaBackend::updateMock()
{
    // Круг: радио → трек по Bluetooth → файл с USB. Так видно все три вида
    // источника, которые поддерживает медиацентр, и разные состояния.
    struct Demo {
        const char *source;
        const char *station;
        const char *title;
        const char *artist;
        bool playing;
        int position;
        int duration;
    };
    static const Demo demo[] = {
        {"fm",     "Русское Радио", "Кавер-версия", "The Hatters", true,  42, 210},
        {"bt",     "",              "Highway to Hell", "AC/DC",     true,  95, 208},
        {"usb",    "",              "Кино — Группа крови", "Кино",  false, 180, 260},
    };
    constexpr int demoCount = static_cast<int>(sizeof(demo) / sizeof(demo[0]));

    m_mockIndex = (m_mockIndex + 1) % demoCount;
    const Demo &d = demo[m_mockIndex];

    m_available = true;
    m_source = QString::fromUtf8(d.source);
    m_station = QString::fromUtf8(d.station);
    m_title = QString::fromUtf8(d.title);
    m_artist = QString::fromUtf8(d.artist);
    m_playing = d.playing;
    m_positionSec = d.position;
    m_durationSec = d.duration;
    m_artUrl.clear();
    emit changed();
}
