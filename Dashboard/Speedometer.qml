import QtQuick 2.15

// Спидометр: шкала 220 км/ч, указатель топлива, лампы и индикатор АКПП.
// Общая часть приборов (циферблат, стрелки, цифры, самопроверка) — Gauge.qml.

Gauge {
    id: root

    // Свойства для данных
    property real speed: 0
    property real maxSpeed: 220

    // Углы основной стрелки (needls_spd.svg).
    // Стрелка при rotation = 0 смотрит не вверх, а влево — примерно на 191°,
    // поэтому углы посчитаны как (угол метки на шкале минус 191°).
    // Метки шкалы в Speedometr.png стоят через 22.29° (по 20 км/ч): «0» на
    // 135.1°, «220» на 20.3°.
    //   speed = 0   → стрелка на 135.1° → rotation = 135.1 - 191.2 = -56.1
    //   speed = 220 → стрелка на  20.3° → rotation = (20.3 - 191.2) + 360 = 189.1
    // Раньше стояло -60…220 (размах 280° вместо 245°), из-за чего у нуля ошибка
    // была 4°, а на 220 км/ч стрелка уходила на 31° за метку.
    startAngle: -56.1
    endAngle: 189.1

    // Что именно показывает прибор
    value: speed
    maxValue: maxSpeed

    // Малая стрелка — топливо. Стрелка нарисована тем же длинным рисунком, что
    // и стрелка спидометра, поэтому её ход ограничен дугой шкалы топлива:
    // в макете дизайнера эта дуга идёт от ~222° (у значка бензоколонки) до ~192°
    // (нижний конец), а сам значок нарисован там же, где «E» на исходной шкале
    // «Шкала топлива.png» — она устроена как «E · бензоколонка · риски · F».
    // Значит пустой бак — у значка (222°), полный — у нижнего конца (192°).
    //
    // Замер по рендеру (стенд с кадром 0x300: 20 % топлива → кончик стрелки на
    // 194°, 78 % → на 164°) дал ход 52° на весь диапазон со сдвигом вниз — то
    // есть стрелка уходила в шкалу спидометра, на метки 100–140 км/ч. Отсюда
    // новые углы: ход 31.6° внутри дуги (222° → 192°), 1:1 к повороту.
    // Если на машине пустой бак окажется у нижнего конца — поменять два числа.
    property real fuelLevel: 0
    property real maxFuel: 100
    secondaryValue: fuelLevel
    secondaryMaxValue: maxFuel
    secondaryStartAngle: -56.6
    secondaryEndAngle: -88.2

    // Картинки: у спидометра свои. Центральный круг — тот же, что у тахометра:
    // в исходниках дизайнера это один и тот же файл 445x445 при циферблате 714,
    // то есть 445/714 = 0.623 (подробный комментарий — в Tachometer.qml).
    // Было 0.622 — на пиксель меньше натурального, разницы не видно, но пусть
    // у обоих приборов значение будет одно.
    dialSource: "images/Speedometr.png"
    needleSource: "images/needls_spd.svg"
    secondaryNeedleSource: "images/needls_fuel.svg"
    centerCircleRatio: 0.623

    property string gearMode: "P"
    // LOCK (SL) — блокировка гидротрансформатора, приходит из Main.qml
    property bool gearLock: false
    property bool showGear: true

    // Состояние ламп (приходит из Main.qml, источник — CanBackend)
    property bool seatBeltWarning: false
    property bool batteryWarning: false
    property bool fuelWarning: false
    property bool handBrakeWarning: false

    // ======================= ЛАМПЫ СПИДОМЕТРА =======================
    // Всё, что объявлено ниже, попадает в слой gaugeContent базового Gauge.qml
    // и рисуется поверх стрелок и цифр.
    // Каждая лампа загорается по своему сигналу; гаснет — opacity 0.
    // Длительность перехода небольшая, чтобы включение читалось мягко.

    // Ремень безопасности
    Image {
        source: "images/belt.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.47
        y: parent.height * 0.25
        fillMode: Image.PreserveAspectFit
        opacity: root.seatBeltWarning ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Зарядка АКБ
    Image {
        source: "images/batt.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.35
        y: parent.height * 0.58
        fillMode: Image.PreserveAspectFit
        opacity: root.batteryWarning ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Значок шкалы топлива — это часть разметки прибора, он виден ВСЕГДА.
    // Мигает только при низком уровне топлива.
    property bool fuelWarnBlink: false

    // Машина двухтопливная: на газу тот же значок бензоколонки показывается
    // зелёным. Картинка fuel_tank_gas.png — та же иконка, перекрашенная в
    // зелёный (альфа исходника сохранена), поэтому геометрия не меняется.
    property bool gasMode: false

    Timer {
        interval: 500
        repeat: true
        running: root.fuelWarning
        onRunningChanged: if (!running) root.fuelWarnBlink = false
        onTriggered: root.fuelWarnBlink = !root.fuelWarnBlink
    }

    Image {
        source: root.gasMode ? "images/fuel_tank_gas.png" : "images/fuel_tank.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.28
        y: parent.height * 0.77
        fillMode: Image.PreserveAspectFit
        opacity: (root.fuelWarning && root.fuelWarnBlink) ? 0.3 : 1.0
    }

    // Ручник
    Image {
        source: "images/H_brake.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.45
        y: parent.height * 0.58
        fillMode: Image.PreserveAspectFit
        opacity: root.handBrakeWarning ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    // Пониженная передача (режим L)
    Image {
        source: "images/low_L.png"
        width: parent.width * 0.07
        height: parent.width * 0.07
        x: parent.width * 0.55
        y: parent.height * 0.58
        fillMode: Image.PreserveAspectFit
        opacity: (root.showGear && root.gearMode === "L") ? 1.0 : 0.0
        visible: opacity > 0
    }

    // === ИНДИКАТОР АКПП (P/R/N/D1..D4/L) ===
    Image {
        id: gearIndicator
        source: "images/gear_" + root.gearMode + ".png"
        width: parent.width * 0.12
        height: parent.width * 0.12
        x: parent.width * 0.6
        y: parent.height * 0.43
        fillMode: Image.PreserveAspectFit
        opacity: root.showGear ? 1.0 : 0.0
    }

    // LOCK (SL) — блокировка гидротрансформатора. Надпись ровно под
    // значком передачи и той же ширины, что и он.
    Text {
        text: "LOCK"
        x: gearIndicator.x - 2
        // Ближе к значку: картинка gear_*.png имеет прозрачные поля,
        // поэтому по низу картинки надпись висела далеко.
        y: gearIndicator.y + gearIndicator.height * 0.65 + 10
        width: gearIndicator.width
        horizontalAlignment: Text.AlignHCenter
        // Цвет как у стрелок поворотника (left_turn/right_turn.png — #00CB00)
        color: "#00CB00"
        font.pixelSize: gearIndicator.width * 0.32
        font.family: "Kdam Thmor Pro"
        font.bold: true
        opacity: (root.showGear && root.gearLock) ? 1.0 : 0.0
        visible: opacity > 0
    }
}
