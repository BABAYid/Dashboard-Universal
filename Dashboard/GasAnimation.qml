import QtQuick 2.15

// ============================================================================
//  Приколка по просьбе заказчика — индикация газа в правом верхнем углу.
//
//  Монетки в кошелёк: машина едет на газу — газ дешевле бензина, вот и
//  «экономим»: монетки сыплются в кошелёк тем быстрее, чем выше обороты.
//
//  Кочегар выше 5000 об/мин: на таких оборотах топливо летит в трубу, поэтому
//  в углу появляется топка, а кочегар бросает в неё пачки денег.
//
//  Почему примитивами: у дизайнера спрайтов кошелька и кочегара нет, а тащить
//  картинки ради шутки не хочется. Всё нарисовано прямоугольниками и кругами,
//  поэтому весь блок убирается одной строкой в Main.qml.
//
//  Монетки и банкноты сделаны инлайновыми компонентами с явными экземплярами,
//  а не Repeater'ом: делегат Repeater — отдельная область видимости, и
//  обращения к id корня из него qmllint считает неявными (unqualified access),
//  а так все значения задаются на месте и файл остаётся чистым по qmllint.
//
//  Видимостью управляет Main.qml: gasOn — едем на газу, highBurn — обороты выше
//  5000 (тогда монетки сменяются топкой). В навигации весь блок скрыт: там
//  в этом углу кнопка закрытия.
// ============================================================================
Item {
    id: fun

    property bool gasOn: false
    property bool highBurn: false
    property real rpm: 0

    // Чем выше обороты, тем быстрее сыплются монетки (но в разумных пределах)
    readonly property int coinDuration: Math.max(240, 1000 - Math.round(rpm / 8))

    // Раскладка сцен внутри блока: кошелёк и топка — в правом нижнем углу,
    // кочегар — слева от топки.
    readonly property real walletX: width - 96
    readonly property real walletY: height - 62
    readonly property real stokerX: width - 152
    readonly property real stokerY: height - 84
    readonly property real furnaceX: width - 92
    readonly property real furnaceY: height - 96

    readonly property bool coinsRunning: gasOn && !highBurn

    // ==================== МОНЕТКА ====================
    component Coin: Rectangle {
        id: coin

        property real fallTo: 0
        property int fallDuration: 600
        property int startDelay: 0
        property bool falling: false

        y: -20
        width: 14
        height: 14
        radius: 7
        color: "#FFC64A"
        border.color: "#B8860B"
        border.width: 2

        SequentialAnimation {
            running: coin.falling
            loops: Animation.Infinite
            PauseAnimation { duration: coin.startDelay }
            NumberAnimation {
                target: coin
                property: "y"
                from: -20
                to: coin.fallTo
                duration: coin.fallDuration
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: coin
                property: "opacity"
                from: 1.0
                to: 0.0
                duration: 140
            }
            PauseAnimation { duration: 120 }
            ScriptAction { script: coin.opacity = 1.0 }
        }
    }

    // ==================== ПАЧКА ДЕНЕГ ====================
    component Banknote: Rectangle {
        id: note

        property real fromX: 0
        property real fromY: 0
        property real flyToX: 0
        property real flyToY: 0
        property int startDelay: 0
        property bool flying: false

        x: note.fromX
        y: note.fromY
        width: 26
        height: 13
        radius: 2
        color: "#9CC46A"
        border.color: "#5E8A3A"
        border.width: 1
        opacity: 0

        // Полоска, чтобы читалось как банкнота
        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 8
            height: 3
            color: "#5E8A3A"
            opacity: 0.7
        }

        SequentialAnimation {
            running: note.flying
            loops: Animation.Infinite
            PauseAnimation { duration: note.startDelay }
            ScriptAction { script: note.opacity = 1.0 }
            NumberAnimation {
                target: note
                property: "x"
                from: note.fromX
                to: note.flyToX
                duration: 520
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                target: note
                property: "y"
                from: note.fromY
                to: note.flyToY
                duration: 520
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: note
                property: "opacity"
                from: 1.0
                to: 0.0
                duration: 180
            }
        }
    }

    visible: gasOn || highBurn

    // ==================== МОНЕТКИ В КОШЕЛЁК ====================
    Item {
        anchors.fill: parent
        visible: fun.coinsRunning

        // Кошелёк: тёмная кожа с откинутой крышкой
        Rectangle {
            x: fun.walletX
            y: fun.walletY
            width: 88
            height: 54
            radius: 10
            color: "#5A3A1E"
            border.color: "#8A5A2E"
            border.width: 2

            // Крышка кошелька
            Rectangle {
                x: -4
                y: -10
                width: parent.width + 8
                height: 22
                radius: 8
                color: "#7A4E28"
                border.color: "#A9763C"
                border.width: 2
            }

            // Застёжка
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 14
                width: 16
                height: 12
                radius: 3
                color: "#C8A24A"
            }
        }

        // Монетки сыплются с разной задержкой, чтобы шёл поток, а не ряд
        Coin { x: fun.walletX + 10; fallTo: fun.walletY + 14; fallDuration: fun.coinDuration; startDelay: 0;   falling: fun.coinsRunning }
        Coin { x: fun.walletX + 26; fallTo: fun.walletY + 22; fallDuration: fun.coinDuration; startDelay: 210; falling: fun.coinsRunning }
        Coin { x: fun.walletX + 42; fallTo: fun.walletY + 12; fallDuration: fun.coinDuration; startDelay: 90;  falling: fun.coinsRunning }
        Coin { x: fun.walletX + 58; fallTo: fun.walletY + 24; fallDuration: fun.coinDuration; startDelay: 330; falling: fun.coinsRunning }
        Coin { x: fun.walletX + 70; fallTo: fun.walletY + 16; fallDuration: fun.coinDuration; startDelay: 470; falling: fun.coinsRunning }
    }

    // ==================== КОЧЕГАР И ТОПКА (ВЫШЕ 5000 ОБ/МИН) ====================
    Item {
        anchors.fill: parent
        visible: fun.highBurn

        // Топка
        Item {
            x: fun.furnaceX
            y: fun.furnaceY
            width: 84
            height: 96

            // Труба
            Rectangle {
                x: 18
                y: 0
                width: 16
                height: 22
                color: "#3A2A22"
                border.color: "#5A463A"
            }

            // Корпус
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 78
                radius: 8
                color: "#33261F"
                border.color: "#5A463A"
                border.width: 2
            }

            // Топка светится и подрагивает, как настоящее пламя
            Rectangle {
                id: fireDoor
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                width: 52
                height: 34
                radius: 5
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#FFD24A" }
                    GradientStop { position: 0.6; color: "#F07A16" }
                    GradientStop { position: 1.0; color: "#A82A06" }
                }

                SequentialAnimation on opacity {
                    running: fun.highBurn
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.72; duration: 220 }
                    NumberAnimation { from: 0.72; to: 1.0; duration: 260 }
                }
            }
        }

        // Кочегар: силуэт, который замахивается и бросает пачку
        Item {
            x: fun.stokerX
            y: fun.stokerY
            width: 40
            height: 84

            // Голова
            Rectangle {
                x: 12
                y: 0
                width: 16
                height: 16
                radius: 8
                color: "#E8E8E8"
            }

            // Туловище
            Rectangle {
                x: 10
                y: 18
                width: 22
                height: 36
                radius: 5
                color: "#E8E8E8"
            }

            // Ноги
            Rectangle { x: 11; y: 56; width: 8; height: 26; radius: 3; color: "#C8C8C8" }
            Rectangle { x: 23; y: 56; width: 8; height: 26; radius: 3; color: "#C8C8C8" }

            // Рука: машет — значит, бросает
            Rectangle {
                id: arm
                x: 20
                y: 26
                width: 34
                height: 7
                radius: 3
                color: "#E8E8E8"
                transformOrigin: Item.Left
                rotation: 40

                SequentialAnimation on rotation {
                    running: fun.highBurn
                    loops: Animation.Infinite
                    NumberAnimation { from: 55; to: -25; duration: 420; easing.type: Easing.OutQuad }
                    NumberAnimation { from: -25; to: 55; duration: 320; easing.type: Easing.InQuad }
                    PauseAnimation { duration: 160 }
                }
            }
        }

        // Пачки денег летят от кочегара в топку
        Banknote {
            fromX: fun.stokerX + 30; fromY: fun.stokerY + 16
            flyToX: fun.furnaceX + 24; flyToY: fun.furnaceY + 58
            startDelay: 0; flying: fun.highBurn
        }
        Banknote {
            fromX: fun.stokerX + 30; fromY: fun.stokerY + 16
            flyToX: fun.furnaceX + 24; flyToY: fun.furnaceY + 58
            startDelay: 260; flying: fun.highBurn
        }
        Banknote {
            fromX: fun.stokerX + 30; fromY: fun.stokerY + 16
            flyToX: fun.furnaceX + 24; flyToY: fun.furnaceY + 58
            startDelay: 520; flying: fun.highBurn
        }
        Banknote {
            fromX: fun.stokerX + 30; fromY: fun.stokerY + 16
            flyToX: fun.furnaceX + 24; flyToY: fun.furnaceY + 58
            startDelay: 780; flying: fun.highBurn
        }
    }
}
