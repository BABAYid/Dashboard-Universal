#include "WeatherProvider.h"

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QUrl>
#include <QUrlQuery>

// ============================================================================
//  Загрузка и разбор погоды Open-Meteo. Все запросы — асинхронные, ошибки
//  не фатальны: просто остаётся прежнее состояние (по умолчанию unknown).
// ============================================================================

namespace {

constexpr int kPollIntervalMs = 10 * 60 * 1000;   // 10 минут
constexpr int kMockIntervalMs = 8 * 1000;         // 8 секунд (демо)

} // namespace

WeatherProvider::WeatherProvider(QObject *parent)
    : QObject(parent)
{
    m_pollTimer.setInterval(kPollIntervalMs);
    m_pollTimer.setSingleShot(false);
    connect(&m_pollTimer, &QTimer::timeout, this, &WeatherProvider::fetchWeather);

    m_mockTimer.setInterval(kMockIntervalMs);
    m_mockTimer.setSingleShot(false);
    connect(&m_mockTimer, &QTimer::timeout, this, &WeatherProvider::updateMock);
}

WeatherProvider *WeatherProvider::instance()
{
    static WeatherProvider *provider = nullptr;
    if (!provider)
        provider = new WeatherProvider(qApp);
    return provider;
}

void WeatherProvider::setLocation(double latitude, double longitude)
{
    m_latitude = latitude;
    m_longitude = longitude;
}

void WeatherProvider::setMockMode(bool mock)
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

void WeatherProvider::start()
{
    if (m_started)
        return;
    m_started = true;

    // Координаты можно переопределить в QSettings (weather/latitude,
    // weather/longitude) — на устройстве без интерфейса удобно задать
    // город один раз. По умолчанию — Москва.
    {
        QSettings settings;
        m_latitude = settings
                         .value(QStringLiteral("weather/latitude"), m_latitude)
                         .toDouble();
        m_longitude = settings
                          .value(QStringLiteral("weather/longitude"), m_longitude)
                          .toDouble();
    }

    // Первый запрос — чуть позже старта окна, чтобы не конкурировать
    // с загрузкой QML и CAN.
    if (!m_mockTimer.isActive()) {
        m_pollTimer.start();
        QTimer::singleShot(2000, this, &WeatherProvider::fetchWeather);
    }
}

// --------------------------------------------------------------------- опрос

void WeatherProvider::fetchWeather()
{
    if (m_network == nullptr) {
        m_network = new QNetworkAccessManager(this);
        connect(m_network, &QNetworkAccessManager::finished,
                this, &WeatherProvider::handleReply);
    }

    QUrl url(QStringLiteral("https://api.open-meteo.com/v1/forecast"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("latitude"),
                       QString::number(m_latitude, 'f', 4));
    query.addQueryItem(QStringLiteral("longitude"),
                       QString::number(m_longitude, 'f', 4));
    query.addQueryItem(QStringLiteral("current"),
                       QStringLiteral("weather_code,temperature_2m"));
    url.setQuery(query);

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("appDashboard/1.0"));
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);
    m_network->get(request);
}

void WeatherProvider::handleReply(QNetworkReply *reply)
{
    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError) {
        // Сеть недоступна — тихо остаёмся в unknown; в лог одна строка.
        qInfo() << "Погода: запрос не удался —" << reply->errorString();
        return;
    }

    const QByteArray data = reply->readAll();
    const QJsonDocument document = QJsonDocument::fromJson(data);
    if (!document.isObject()) {
        qWarning() << "Погода: ответ не JSON";
        return;
    }

    const QJsonObject current =
        document.object().value(QStringLiteral("current")).toObject();
    if (!current.contains(QStringLiteral("weather_code"))) {
        qWarning() << "Погода: в ответе нет weather_code";
        return;
    }

    const int code = current.value(QStringLiteral("weather_code")).toInt();
    const double temperature =
        current.value(QStringLiteral("temperature_2m")).toDouble();

    apply(code, temperature, descriptionFromCode(code));
}

void WeatherProvider::apply(int weatherCode, double temperature,
                            const QString &description)
{
    m_temperature = temperature;
    setState(stateFromCode(weatherCode), description);
}

void WeatherProvider::setState(const QString &state, const QString &description)
{
    if (m_state == state && m_description == description)
        return;
    m_state = state;
    m_description = description;
    qInfo() << "Погода:" << m_description << "| состояние:" << m_state;
    emit stateChanged();
}

// --------------------------------------------------------------------- демо

void WeatherProvider::updateMock()
{
    // Круг состояний: дождь → снег → ясно. Первым делом — дождь, чтобы
    // эффект было видно сразу после запуска с --mock.
    static const QStringList states{
        QStringLiteral("rain"),
        QStringLiteral("snow"),
        QStringLiteral("clear"),
    };
    static const QStringList descriptions{
        QStringLiteral("Дождь"),
        QStringLiteral("Снег"),
        QStringLiteral("Ясно"),
    };

    m_mockIndex = (m_mockIndex + 1) % states.size();
    m_temperature = m_mockIndex == 1 ? -4.0 : 8.0;
    setState(states.at(m_mockIndex), descriptions.at(m_mockIndex));
}

// ---------------------------------------------------------------- WMO-коды

QString WeatherProvider::stateFromCode(int weatherCode)
{
    // Диапазоны WMO: 0 — ясно; 1-3 — облачно; 45,48 — туман;
    // 51-57 — морось; 61-67 — дождь; 71-77 — снег; 80-82 — ливни;
    // 85,86 — снегопады; 95+ — грозы (в интерфейсе рисуем как дождь).
    if (weatherCode == 0)
        return QStringLiteral("clear");
    if (weatherCode >= 1 && weatherCode <= 3)
        return QStringLiteral("cloudy");
    if (weatherCode == 45 || weatherCode == 48)
        return QStringLiteral("fog");
    if ((weatherCode >= 51 && weatherCode <= 57)
        || (weatherCode >= 61 && weatherCode <= 67)
        || (weatherCode >= 80 && weatherCode <= 82)
        || weatherCode >= 95)
        return QStringLiteral("rain");
    if ((weatherCode >= 71 && weatherCode <= 77)
        || (weatherCode >= 85 && weatherCode <= 86))
        return QStringLiteral("snow");
    return QStringLiteral("unknown");
}

QString WeatherProvider::descriptionFromCode(int weatherCode)
{
    if (weatherCode == 0)
        return QStringLiteral("Ясно");
    if (weatherCode >= 1 && weatherCode <= 3)
        return QStringLiteral("Облачно");
    if (weatherCode == 45 || weatherCode == 48)
        return QStringLiteral("Туман");
    if ((weatherCode >= 51 && weatherCode <= 57)
        || (weatherCode >= 80 && weatherCode <= 82))
        return QStringLiteral("Морось");
    if ((weatherCode >= 61 && weatherCode <= 67)
        || weatherCode >= 95)
        return QStringLiteral("Дождь");
    if ((weatherCode >= 71 && weatherCode <= 77)
        || (weatherCode >= 85 && weatherCode <= 86))
        return QStringLiteral("Снег");
    return QStringLiteral("Неизвестно");
}
