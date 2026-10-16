import QtQuick 2.15

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
    property bool nightMode: false

    // Угол основной стрелки во время самопроверки. Отдельное свойство, а не
    // rotation: запись в привязанное свойство разрушает привязку, и стрелка
    // «застывает» (ловили это раньше, см. «Грабли» в PROJECT_STATE.md).
    property real sweepAngle: 0

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
        rotation: gauge.secondaryStartAngle
                  + (gauge.secondaryValue / gauge.secondaryMaxValue)
                    * (gauge.secondaryEndAngle - gauge.secondaryStartAngle)
        Behavior on rotation {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
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

    // Основная стрелка (поверх всего, кроме цифр и ламп)
    Image {
        source: gauge.needleSource
        width: parent.width * gauge.needleScale
        height: parent.height * gauge.needleScale
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        fillMode: Image.PreserveAspectFit
        transformOrigin: Item.Center
        rotation: gauge.startup ? gauge.sweepAngle : gauge.needleAngle
        Behavior on rotation {
            enabled: !gauge.startup
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
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

        // Появляются после самопроверки приборов, как в серийных панелях
        opacity: gauge.startup ? 0.0 : 1.0
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
        NumberAnimation {
            target: gauge
            property: "sweepAngle"
            from: gauge.endAngle
            to: gauge.needleAngle
            duration: 400
            easing.type: Easing.InOutQuad
        }
    }
}
