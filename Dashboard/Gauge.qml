import QtQuick 2.15
import Qt5Compat.GraphicalEffects

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
    // Поправка угла шлейфа: арт стрелки нарисован с наклоном −79.3°
    // (замерено по кадру: при needleAngle = −22.7° стрелка смотрит
    // на −102°), а маска-сектор нарисована от «3 часов» (−25°..0°),
    // поэтому сверх наклона нужно ещё −90°: −79.3 − 90 = −169.3.
    property real trailRotationOffset: -169.3

    // ======================= ОТРИСОВКА =======================

    // Шкала прибора
    Image {
        anchors.fill: parent
        source: gauge.dialSource
        fillMode: Image.PreserveAspectFit
    }

    // --- НАЧАЛО ШЛЕЙФА ---
    // Canvas больше не рисует градиент: createConicGradient в этой сборке
    // Qt не работает (заливает сплошным цветом). Теперь Canvas — только
    // МАСКА формы (сектор 25° позади стрелки), а плавное затухание даёт
    // аппаратный ConicalGradient, наложенный через OpacityMask.
    // Объявлен ДО стрелок и центрального круга — они рисуются поверх.
    Item {
        id: needleTrail
        anchors.fill: parent
        // Весь контейнер вращается вместе со стрелкой.
        rotation: (gauge.startup ? gauge.sweepAngle : gauge.needleAngle) + gauge.trailRotationOffset
        visible: gauge.showTrail && !gauge.startup

        // 1. Маска формы: сектор 25° позади стрелки (от −25° до 0°).
        Canvas {
            id: trailMask
            anchors.fill: parent
            visible: false            // используется только как маска
            antialiasing: true
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var cx = width / 2;
                var cy = height / 2;
                var radius = width / 2 - 10;
                // Маска — только радиальное затухание к краю диска.
                // Угловую форму (веер с плавными краями) задаёт сам
                // ConicalGradient, поэтому сектор в маске не нужен:
                // у него были видимые жёсткие лучи от ступицы к краю.
                ctx.beginPath();
                ctx.arc(cx, cy, radius, 0, Math.PI * 2, false);
                ctx.fillStyle = (function () {
                    var rg = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius);
                    rg.addColorStop(0.0, "rgba(255,255,255,1)");
                    rg.addColorStop(0.80, "rgba(255,255,255,1)");
                    rg.addColorStop(1.0, "rgba(255,255,255,0)");
                    return rg;
                })();
                ctx.fill();
            }
        }

        // 2. Источник градиента: плавно затухает от стрелки к хвосту.
        // ВАЖНО: не Rectangle, а Item — у Rectangle цвет по умолчанию
        // белый, и он заливал маску сплошным белым (та самая «серая
        // заливка» вместо градиента).
        Item {
            id: trailGradientSource
            anchors.fill: parent
            visible: false
            ConicalGradient {
                anchors.fill: parent
                // position 0.0 у ConicalGradient — «на 12 часов» локально,
                // а позиции растут по часовой. Маска-сектор занимает
                // 65°…90° (от «3 часов» −25°…0°), поэтому градиент стартует
                // с 65°: прозрачный у хвоста → 0.7 белого у стрелки.
                angle: 65
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.0694; color: "#99FFFFFF" }
                    GradientStop { position: 0.08; color: "transparent" }
                }
            }
        }

        // 3. Градиент, обрезанный по маске.
        OpacityMask {
            anchors.fill: parent
            source: trailGradientSource
            maskSource: trailMask
        }
    }
    // --- КОНЕЦ ШЛЕЙФА ---

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
