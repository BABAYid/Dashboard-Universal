import QtQuick 2.15

// Тахометр: шкала 8000 об/мин, указатель температуры двигателя и лампы.
// Общая часть приборов (циферблат, стрелки, цифры, самопроверка) — Gauge.qml.

Gauge {
    id: root

    property real rpm: 0
    property real maxRpm: 8000

    // Углы основной стрелки (needls_tho.svg).
    // Стрелка при rotation = 0 смотрит не вверх, а влево — примерно на 191°.
    // Поэтому углы ниже посчитаны как (угол цифры на шкале минус 191°).
    // Цифры шкалы в taho.png стоят так: 0 → 134.5°, 4 → 269.8° (ровно вверху),
    // 8 → 46.1°; шаг между цифрами 33.5°.
    //   rpm = 0    → стрелка на 134.5° → rotation = 134.5 - 191.2 = -56.7
    //   rpm = 8000 → стрелка на  46.1° → rotation = (46.1 - 191.2) + 360 = 214.9
    // Размах шкалы 271.6°. При этих значениях стрелка ложится на цифры с
    // расхождением не более 2°.
    startAngle: -56.7
    endAngle: 214.9

    // Что именно показывает прибор
    value: rpm
    maxValue: maxRpm

    // Малая стрелка — температура двигателя. Её сектор внизу циферблата:
    // стрелка температуры нарисована тем же длинным рисунком, что и тахометр.
    property real temp: 0
    property real maxTemp: 120
    secondaryValue: temp
    secondaryMaxValue: maxTemp
    secondaryStartAngle: -80
    secondaryEndAngle: -103

    // Картинки: у тахометра свои. Центральный круг — ровно как в исходниках
    // дизайнера: файл «Внутрний круг» 445x445 при циферблате 714, то есть
    // 445/714 = 0.623. Этот файл ОДИН И ТОТ ЖЕ у обоих приборов
    // (Тахометр/Внутрний круг.svg и Спидометр/Внутрний круг.svg совпадают
    // побайтово), поэтому и коэффициент у них теперь одинаковый.
    // Было 0.638 — круг 456 px вместо 445, и на эти 5 px радиуса он заходил на
    // надпись «rpm*1000» (она лежит на радиусе 206…226 px от центра): замер по
    // картинке давал 148 заметно перекрытых пикселей надписи, при 0.623 — ноль.
    dialSource: "images/taho.png"
    needleSource: "images/needls_tho.svg"
    secondaryNeedleSource: "images/needls_temp.svg"
    centerCircleRatio: 0.623

    // Состояние ламп (приходит из Main.qml, источник — CanBackend)
    property bool absWarning: false
    property bool checkEngineWarning: false
    property bool oilPressureWarning: false
    property bool tempWarning: false

    // ======================= ЛАМПЫ ТАХОМЕТРА =======================
    // Всё, что объявлено ниже, попадает в слой gaugeContent базового Gauge.qml
    // и рисуется поверх стрелок и цифр.

    // Значок шкалы температуры — это часть разметки прибора, он виден ВСЕГДА.
    // Мигает только при перегреве.
    property bool tempWarnBlink: false

    Timer {
        interval: 500
        repeat: true
        running: root.tempWarning
        onRunningChanged: if (!running) root.tempWarnBlink = false
        onTriggered: root.tempWarnBlink = !root.tempWarnBlink
    }

    Image {
        source: "images/temp_dvs.png"
        width: parent.width * 0.08
        height: parent.width * 0.08
        x: parent.width * 0.65
        y: parent.height * 0.77
        fillMode: Image.PreserveAspectFit
        opacity: (root.tempWarning && root.tempWarnBlink) ? 0.3 : 1.0
    }

    // ABS
    Image {
        source: "images/ABS.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.55
        y: parent.height * 0.58
        fillMode: Image.PreserveAspectFit
        opacity: root.absWarning ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Check Engine
    Image {
        source: "images/check.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.45
        y: parent.height * 0.58
        fillMode: Image.PreserveAspectFit
        opacity: root.checkEngineWarning ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Давление масла (авария)
    Image {
        source: "images/oil_press.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.35
        y: parent.height * 0.58
        fillMode: Image.PreserveAspectFit
        opacity: root.oilPressureWarning ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }
}
