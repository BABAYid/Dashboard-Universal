import QtQuick 2.15
import QtQuick.Shapes

// ============================================================================
//  Gauge.qml — общая основа круглого прибора: спидометра и тахометра.
//
//  Оба прибора устроены одинаково и различались только картинками, диапазоном
//  шкалы и лампами, поэтому общая часть живёт здесь, а Speedometer.qml и
//  Tachometer.qml задают значения и добавляют свои лампы.
//
//  Что здесь:
//    - циферблат (картинка-шкала);
//    - малая стрелка (топливо у спидометра, температура у тахометра);
//    - центральный круг поверх малой стрелки;
//    - основная стрелка с анимацией самопроверки (sweepAngle);
//    - цифровое значение в свободной полосе над ступицей;
//    - слой gaugeContent для содержимого наследника (лампы, значки шкал).
//
//  Порядок отрисовки важен и менять его нельзя:
//    циферблат → малая стрелка → центральный круг → основная стрелка → цифры
//    → содержимое наследника.
//
//  Геометрия стрелок и меток — раздел «Геометрия стрелок и шкал» в
//  PROJECT_STATE.md: стрелка при rotation = 0 смотрит не вверх, а влево
//  (примерно на 191°), поэтому угол поворота = угол метки на шкале − 191.2.
// ============================================================================
Item {
    id: gauge

    width: 714
    height: 714

    // ======================= КАРТИНКИ И ГЕОМЕТРИЯ =======================
    property url dialSource                // шкала прибора
    property url needleSource              // основная стрелка
    property url secondaryNeedleSource     // малая стрелка (топливо / температура)

    // Диаметр центрального круга относительно прибора — у спидометра и
    // тахометра он разный, потому что различаются сами картинки шкал.
    property real centerCircleRatio: 0.63

    // Все четыре стрелки — один рисунок, и он длиннее циферблата ровно на
    // столько: так стрелка достаёт до меток, нарисованных по краю картинки.
    property real needleScale: 1.05

    // ======================= ОСНОВНАЯ ВЕЛИЧИНА =======================
    property real value: 0
    property real maxValue: 100
    property real startAngle: 0
    property real endAngle: 0

    readonly property real needleAngle: startAngle + (value / maxValue) * (endAngle - startAngle)

    // ======================= МАЛАЯ ВЕЛИЧИНА =======================
    // Топливо у спидометра и температура у тахометра: своя стрелка, свой сектор
    // внизу циферблата, без анимации самопроверки.
    property real secondaryValue: 0
    property real secondaryMaxValue: 100
    property real secondaryStartAngle: 0
    property real secondaryEndAngle: 0

    // ======================= СОСТОЯНИЕ =======================
    property bool startup: false     // идёт самопроверка: стрелку ведёт анимация
    // Цифровое значение на циферблате (в 1-м виде центра оно дублируется)
    property bool showDigital: true
    property bool nightMode: false

    // Угол основной стрелки во время самопроверки. Отдельное свойство, а не
    // rotation: запись в привязанное свойство разрушает привязку, и стрелка
    // «застывает» (ловили это раньше, см. «Грабли» в PROJECT_STATE.md).
    property real sweepAngle: 0

    // Включён ли шлейф-«хвост» за стрелкой (настройка «Внешний вид»).
    // false — компоненты шлейфа невидимы и не тратят ресурсы.
    property bool showTrail: true

    // Длина шлейфа (градусы сектора за стрелкой). Требование 20–30°.
    property real trailAngleSpan: 25

    // Фактический угол основной стрелки (с учётом пружины) — от него
    // считается скорость/направление для шлейфа.
    readonly property real mainNeedleRotation: mainNeedle.rotation

    // Шлейф-«след»: одна плавная текстура-клин, поворачивается вместе со
    // стрелкой; видна только при движении — прозрачность от скорости.
    // Направление: d>0 — по часовой (клин сзади-против часовой).
    // Чувствительность шлейфа: скорость стрелки (град/кадр), при которой
    // шлейф выходит на полную. У спидометра ход плавный, у тахометра —
    // резкий, поэтому у каждого своё значение.
    property real trailSensitivity: 0.8
    // Поправка угла для шлейфа: арт стрелки (SVG) нарисован под углом к
    // вертикали — кончик при rotation=0 смотрит на ≈ −79°. Клин доворачиваем
    // на те же −79°, иначе он уезжает относительно стрелки на ~80°.
    property real trailRotationOffset: -79.0

    property real trailCwOpacity: 0.0
    property real trailCcwOpacity: 0.0
    property real trailLastRotation: 0.0
    // Сглаженные скорость и направление: без них прозрачность «дёргается»
    // на каждом кадре пружины (мерцание).
    property real trailSmoothVel: 0.0
    property real trailSmoothDir: 0.0

    Timer {
        interval: 16
        repeat: true
        running: gauge.showTrail && !gauge.startup
        onTriggered: {
            const d = gauge.mainNeedleRotation - gauge.trailLastRotation
            gauge.trailLastRotation = gauge.mainNeedleRotation
            // |d| — градусы за 16 мс; нормируем на чувствительность прибора.
            // Направление: клин без отражения лежит в углах [-38..0] от
            // стрелки (против часовой) — он «за стрелкой» при движении
            // ПРОТИВ часовой (d < 0), зеркальный — при движении по часовой.
            const raw = Math.max(-1.0, Math.min(1.0,
                d / Math.max(0.05, gauge.trailSensitivity)))
            // Низкочастотный фильтр: плавно «набираем» скорость и плавно
            // гасим — никакого мерцания от кадровых колебаний пружины.
            gauge.trailSmoothVel = gauge.trailSmoothVel * 0.82 + Math.abs(raw) * 0.18
            gauge.trailSmoothDir = gauge.trailSmoothDir * 0.85 + raw * 0.15
            const o = Math.min(1.0, gauge.trailSmoothVel * 1.15)
            gauge.trailCwOpacity = gauge.trailSmoothDir > 0.05 ? o : gauge.trailCwOpacity * 0.85
            gauge.trailCcwOpacity = gauge.trailSmoothDir < -0.05 ? o : gauge.trailCcwOpacity * 0.85
        }
    }

    // ======================= ОТРИСОВКА =======================

    // Шкала прибора
    Image {
        anchors.fill: parent
        source: gauge.dialSource
        fillMode: Image.PreserveAspectFit
    }

    // Малая стрелка (под центральным кругом)
    Image {
        source: gauge.secondaryNeedleSource
        width: parent.width * gauge.needleScale
        height: parent.height * gauge.needleScale
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        fillMode: Image.PreserveAspectFit
        transformOrigin: Item.Center
        // Ход ограничен дугой шкалы жёстко: коэффициент из настроек (или
        // датчик) может дать >100 % — без клампа стрелка уезжала за сектор,
        // в шкалу спидометра.
        rotation: {
            const k = Math.max(0.0, Math.min(1.0,
                gauge.secondaryValue / gauge.secondaryMaxValue))
            return gauge.secondaryStartAngle
                   + k * (gauge.secondaryEndAngle - gauge.secondaryStartAngle)
        }
        // Пружина: у топлива/температуры ход медленный — мягкая, без
        // раскачки (damping 0.45 = почти критическое затухание).
        Behavior on rotation {
            SpringAnimation {
                spring: 2.0
                damping: 0.45
                mass: 1.0
                epsilon: 0.1
            }
        }
    }

    // Центральный круг (поверх малой стрелки)
    Image {
        source: "images/around_in.png"
        width: parent.width * gauge.centerCircleRatio
        height: parent.height * gauge.centerCircleRatio
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        fillMode: Image.PreserveAspectFit
    }

    // ===== ШЛЕЙФ: статичная геометрия из узких секторов =====
    // ConicalGradient в QtQuick.Shapes рисует сектор грубой нарезкой (полосы),
    // а шейдеры недоступны (нет qsb). Поэтому шлейф собран из 24 статичных
    // треугольников с плавным шагом альфы (~1° на шаг): геометрия строится
    // один раз, а поворот/зеркало — только трансформ item.
    Shape {
        id: trailShape
        width: 714
        height: 714
        transformOrigin: Item.Center
        visible: gauge.showTrail && !gauge.startup && gauge.trailSmoothVel > 0.02
        opacity: Math.min(1.0, gauge.trailSmoothVel * 1.15)
        rotation: gauge.mainNeedleRotation + gauge.trailRotationOffset
        // По часовой (d>0): хвост позади = против часовой стороны —
        // зеркалим сектор; против часовой — без зеркала.
        transform: Scale {
            origin.x: trailShape.width / 2
            origin.y: trailShape.height / 2
            xScale: gauge.trailSmoothDir > 0 ? -1 : 1
            yScale: 1
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.783)
            startX: 357.0; startY: 357.0
            PathLine { x: 357.0; y: 17.9 }
            PathLine { x: 363.2; y: 17.9 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.750)
            startX: 357.0; startY: 357.0
            PathLine { x: 363.2; y: 17.9 }
            PathLine { x: 369.3; y: 18.1 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.717)
            startX: 357.0; startY: 357.0
            PathLine { x: 369.3; y: 18.1 }
            PathLine { x: 375.5; y: 18.4 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.683)
            startX: 357.0; startY: 357.0
            PathLine { x: 375.5; y: 18.4 }
            PathLine { x: 381.6; y: 18.7 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.650)
            startX: 357.0; startY: 357.0
            PathLine { x: 381.6; y: 18.7 }
            PathLine { x: 387.8; y: 19.3 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.617)
            startX: 357.0; startY: 357.0
            PathLine { x: 387.8; y: 19.3 }
            PathLine { x: 393.9; y: 19.9 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.583)
            startX: 357.0; startY: 357.0
            PathLine { x: 393.9; y: 19.9 }
            PathLine { x: 400.0; y: 20.6 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.550)
            startX: 357.0; startY: 357.0
            PathLine { x: 400.0; y: 20.6 }
            PathLine { x: 406.2; y: 21.4 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.517)
            startX: 357.0; startY: 357.0
            PathLine { x: 406.2; y: 21.4 }
            PathLine { x: 412.2; y: 22.4 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.483)
            startX: 357.0; startY: 357.0
            PathLine { x: 412.2; y: 22.4 }
            PathLine { x: 418.3; y: 23.4 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.450)
            startX: 357.0; startY: 357.0
            PathLine { x: 418.3; y: 23.4 }
            PathLine { x: 424.4; y: 24.6 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.417)
            startX: 357.0; startY: 357.0
            PathLine { x: 424.4; y: 24.6 }
            PathLine { x: 430.4; y: 25.9 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.383)
            startX: 357.0; startY: 357.0
            PathLine { x: 430.4; y: 25.9 }
            PathLine { x: 436.4; y: 27.3 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.350)
            startX: 357.0; startY: 357.0
            PathLine { x: 436.4; y: 27.3 }
            PathLine { x: 442.4; y: 28.8 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.317)
            startX: 357.0; startY: 357.0
            PathLine { x: 442.4; y: 28.8 }
            PathLine { x: 448.3; y: 30.4 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.283)
            startX: 357.0; startY: 357.0
            PathLine { x: 448.3; y: 30.4 }
            PathLine { x: 454.3; y: 32.1 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.250)
            startX: 357.0; startY: 357.0
            PathLine { x: 454.3; y: 32.1 }
            PathLine { x: 460.2; y: 33.9 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.217)
            startX: 357.0; startY: 357.0
            PathLine { x: 460.2; y: 33.9 }
            PathLine { x: 466.0; y: 35.8 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.183)
            startX: 357.0; startY: 357.0
            PathLine { x: 466.0; y: 35.8 }
            PathLine { x: 471.8; y: 37.9 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.150)
            startX: 357.0; startY: 357.0
            PathLine { x: 471.8; y: 37.9 }
            PathLine { x: 477.6; y: 40.0 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.117)
            startX: 357.0; startY: 357.0
            PathLine { x: 477.6; y: 40.0 }
            PathLine { x: 483.4; y: 42.3 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.083)
            startX: 357.0; startY: 357.0
            PathLine { x: 483.4; y: 42.3 }
            PathLine { x: 489.1; y: 44.6 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.050)
            startX: 357.0; startY: 357.0
            PathLine { x: 489.1; y: 44.6 }
            PathLine { x: 494.7; y: 47.1 }
            PathLine { x: 357.0; y: 357.0 }
        }
        ShapePath {
            fillColor: Qt.rgba(1.0, 1.0, 1.0, 0.020)
            startX: 357.0; startY: 357.0
            PathLine { x: 494.7; y: 47.1 }
            PathLine { x: 500.3; y: 49.6 }
            PathLine { x: 357.0; y: 357.0 }
        }
    }


    // ======================= ОСНОВНАЯ СТРЕЛКА =======================
    // Шлейф рисуется ПОД ней (объявлен выше), по ней же считаются
    // скорость/направление для шлейфа (id: mainNeedle).
    Image {
        id: mainNeedle
        source: gauge.needleSource
        width: parent.width * gauge.needleScale
        height: parent.height * gauge.needleScale
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        fillMode: Image.PreserveAspectFit
        transformOrigin: Item.Center
        rotation: gauge.startup ? gauge.sweepAngle : gauge.needleAngle
        // Пружина: при резком изменении значения стрелка перелетает на 2–3 %
        // и возвращается за ~0.5 с.
        Behavior on rotation {
            enabled: !gauge.startup
            SpringAnimation {
                spring: 2.0
                damping: 0.2
                mass: 1.0
                epsilon: 0.1
            }
        }
    }

    // ======================= ЦИФРОВОЕ ЗНАЧЕНИЕ =======================
    // Место: полоса прямо над ступицей. Она зажата между иконкой ремня
    // (заканчивается на y=228) и иконкой передачи (начинается с y=307),
    // поэтому высота ровно 79 px — это проверено замером.
    // Выше ставить нельзя: там ходят обе стрелки — и основная, и малая
    // (стрелка топлива той же длины, её сектор 61°…116°, то есть низ циферблата).
    // Подложки нет, поэтому цифры отделены от стрелки тонким контуром: стрелка
    // тахометра проходит через цифры на ~4000 об/мин.
    Column {
        x: parent.width * 0.39
        // 0.317, а не середина полосы: у шрифта большой верхний просвет,
        // и без сдвига цифры садятся ниже центра свободного места
        y: parent.height * 0.317
        width: parent.width * 0.22

        // Появляются после самопроверки приборов, как в серийных панелях;
    // в виде «стандарт» (1-й) цифры скрываются — они уже есть в центре.
        opacity: (gauge.startup || !gauge.showDigital) ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 400 } }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Math.round(gauge.value)
            color: gauge.nightMode ? "#FF8800" : "white"
            font.pixelSize: 54
            font.bold: true
            font.family: "Kdam Thmor Pro"
            style: Text.Outline
            styleColor: "#000000"
        }
    }

    // ======================= СОДЕРЖИМОЕ НАСЛЕДНИКА =======================
    // Слой объявлен последним, поэтому рисуется поверх стрелок и цифр, а
    // размеры у него те же, что у прибора: лампы в наследниках по-прежнему
    // считают координаты от parent.width / parent.height.
    Item {
        id: contentLayer
        anchors.fill: parent
    }

    default property alias gaugeContent: contentLayer.data

    // ======================= САМОПРОВЕРКА =======================
    // Стрелка проходит всю шкалу и возвращается на текущее значение.
    // Флагом startup управляет Main.qml.
    SequentialAnimation {
        running: gauge.startup

        NumberAnimation {
            target: gauge
            property: "sweepAngle"
            from: gauge.startAngle
            to: gauge.endAngle
            duration: 800
            easing.type: Easing.OutCubic
        }
        // Возврат к текущему значению — пружиной: стрелка «доезжает»
        // с лёгким перелётом, как живая (первый проход по шкале оставляем
        // линейным — так самопроверка читается чётче).
        SpringAnimation {
            target: gauge
            property: "sweepAngle"
            from: gauge.endAngle
            to: gauge.needleAngle
            spring: 2.0
            damping: 0.25
            mass: 1.0
            epsilon: 0.1
        }
    }
}
