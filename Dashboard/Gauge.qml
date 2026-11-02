import QtQuick 2.15
import QtMultimedia

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
    // Поправка положения центрального круга, px (см. комментарий у Image)
    property real centerCircleOffsetX: 0
    property real centerCircleOffsetY: 0
    // Камера заднего вида в колодце (пока заглушка — вместо неё будет видео
    // с USB-захвата CVBS; показывается, пока горит поворотник).
    property bool cameraVisible: false
    property string cameraLabel: ""
    // Источник видео для колодца (промо-ролик или живая камера UVC).
    // Пока пусто — показывается заглушка.
    property string cameraVideoSource: ""

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

    // Центральный круг (поверх малой стрелки). В картинке taho.png
    // «вшитый» круг чуть не соосен диску — прибор может подправить
    // положение накладки пикселями (см. Tachometer.qml).
    Image {
        source: "images/around_in.png"
        width: parent.width * gauge.centerCircleRatio
        height: parent.height * gauge.centerCircleRatio
        x: (parent.width - width) / 2 + gauge.centerCircleOffsetX
        y: (parent.height - height) / 2 + gauge.centerCircleOffsetY
        fillMode: Image.PreserveAspectFit
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

    // Заглушка камеры: занимает ВЕСЬ колодец (круг прибора целиком),
    // показывается по поворотнику в любом режиме. Когда придут камеры —
    // вместо заглушки встанет VideoOutput (UVC), обрезанный по кругу,
    // с зеркалированием как в зеркалах.
    Item {
        id: cameraWell
        anchors.centerIn: parent
        width: parent.width
        height: width
        visible: gauge.cameraVisible
        z: 5

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#0E1218"
            border.color: "#4A505A"
            border.width: 3
        }

        // Тёмная рамка-колодец поверх, чтобы круг читался на циферблате
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: "#2A2F36"
            border.width: 6
            antialiasing: true
        }

        // Видео (промо-ролик / камера). Крутится по кругу, зеркально.
        Video {
            id: cameraVideo
            anchors.fill: parent
            visible: gauge.cameraVideoSource.length > 0
            source: gauge.cameraVideoSource
            fillMode: VideoOutput.PreserveAspectCrop
            loops: MediaPlayer.Infinite
            autoPlay: true
            muted: true
            transform: Scale { xScale: -1 }   // как в зеркалах
        }

        Text {
            anchors.centerIn: parent
            visible: gauge.cameraVideoSource.length === 0
            text: "КАМЕРА " + gauge.cameraLabel
            color: "#9AA4B2"
            font.pixelSize: parent.width * 0.11
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.18
            visible: gauge.cameraVideoSource.length === 0
            text: "(здесь будет видео с USB-камеры, зеркально)"
            color: "#5A626E"
            font.pixelSize: parent.width * 0.045
        }
    }

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
