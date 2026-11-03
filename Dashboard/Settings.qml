pragma ComponentBehavior: Bound
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtCore as Core
import Dashboard

// ============================================================================
//  Настройки приборки.
//
//  Это НЕ отдельное окно, а оверлей внутри главного окна — сознательно:
//  на устройстве приборка запускается через EGLFS, а этот платформенный плагин
//  поддерживает только одно окно, поэтому второе (как было раньше) там просто
//  не появится. Оверлею всё равно, сколько окон на экране, и его удобно
//  вызывать откуда угодно: кнопкой на панели сейчас, кнопкой на руле — потом.
//
//  Открывается кнопкой «Настройки» на панели или двойным кликом по центральной
//  области. Закрывается «Отменой», клавишей Esc или повторным вызовом.
//
//  Что настраивается сейчас:
//    * коэффициенты показаний (скорость, обороты, топливо, температура) —
//      подгоняют приборку под конкретную машину;
//    * пробег на одометре — при замене панели владелец вводит показание
//      старой приборки. Хранит и применяет его CanBackend (QSettings),
//      потому что одометр считает именно он.
//
//  Коэффициенты хранит Core.Settings (QtCore.Settings, тот же QSettings).
//  Тип указан через псевдоним импорта, иначе имя Settings разрешилось бы
//  в одноимённый компонент этого же файла.
//
//  Ввод сейчас — с клавиатуры (мышь/клавиатура на столе разработчика).
//  На устройстве клавиатуры нет: чтобы настраивать панель кнопками на руле,
//  понадобится экранная цифровая клавиатура — см. backlog в PROJECT_STATE.md.
// ============================================================================
Item {
    id: settingsOverlay

    anchors.fill: parent
    visible: false
    z: 300

    // Коэффициенты (передаются из Main.qml и возвращаются сигналом)
    property real speedFactor: 1.0
    property real rpmFactor: 1.0
    property real fuelFactor: 1.0
    property real tempFactor: 1.0
    property bool nightMode: false

    // «Приколы» — анимация в правом верхнем углу (монетки в кошелёк на газу и
    // кочегар с пачками денег выше 5000 об/мин). Выключатель отдельной строкой:
    // в серийной приборке шутку можно погасить, не трогая код.
    property bool funEnabled: true

    // «Погода» — дождь/снег на панели, когда за окном непогода (Open-Meteo).
    property bool weatherEnabled: true

    // «Камеры» — предупреждения Smart Driver: «КАМЕРА: 60 км/ч» и «ДО КАМЕРЫ».
    // Выключатель на случай, когда база сомнительная или не нужна.
    property bool cameraWarningEnabled: true

    // Калибровка шкал малых стрелок (поворот item, градусы):
    // топливо — при пустом (E) и полном (F) баке, температура — при 40 и 120 °C.
    property real fuelAngleE: -82
    property real fuelAngleF: -121
    property real tempAngleStart: -82
    property real tempAngleEnd: -119

    // Тесты 3D-модели: двери, капот, багажник (когда модель загружена).
    property bool doorsOpen: false
    property bool capotOpen: false
    property bool trunkOpen: false

    // Сигнал при применении коэффициентов
    signal settingsApplied(real sf, real rf, real ff, real tf)

    readonly property color valueColor: nightMode ? "#FF8800" : "white"
    readonly property color labelColor: nightMode ? "#C46A00" : "#9A9A9A"
    readonly property string uiFont: "Kdam Thmor Pro"

    Core.Settings {
        id: appSettings
        property real savedSpeedFactor: 1.0
        property real savedRpmFactor: 1.0
        property real savedFuelFactor: 1.0
        property real savedTempFactor: 1.0
        property bool savedFunEnabled: true
        property bool savedWeatherEnabled: true
        property bool savedCameraWarningEnabled: true
        property bool savedNeedleTrailEnabled: true
        // Калибровка стрелок топлива/температуры (углы поворота)
        property real savedFuelAngleE: -82
        property real savedFuelAngleF: -121
        property real savedTempAngleStart: -82.0
        property real savedTempAngleEnd: -119.0
    }

    // Загружаем сохранённые значения при старте приложения
    Component.onCompleted: {
        speedFactor = appSettings.savedSpeedFactor
        rpmFactor = appSettings.savedRpmFactor
        fuelFactor = appSettings.savedFuelFactor
        tempFactor = appSettings.savedTempFactor
        funEnabled = appSettings.savedFunEnabled
        weatherEnabled = appSettings.savedWeatherEnabled
        cameraWarningEnabled = appSettings.savedCameraWarningEnabled
        fuelAngleE = appSettings.savedFuelAngleE
        fuelAngleF = appSettings.savedFuelAngleF
        tempAngleStart = appSettings.savedTempAngleStart
        tempAngleEnd = appSettings.savedTempAngleEnd
    }

    function open() {
        updateInputs()
        visible = true
    }

    function updateInputs() {
        speedRow.field.text = speedFactor.toFixed(2)
        rpmRow.field.text = rpmFactor.toFixed(2)
        fuelRow.field.text = fuelFactor.toFixed(2)
        tempRow.field.text = tempFactor.toFixed(2)
        odometerRow.field.text = CanBackend.odometer.toFixed(1)
        tankRow.field.text = CanBackend.tankCapacity.toFixed(0)
        fuelAngleERow.field.text = fuelAngleE.toFixed(1)
        fuelAngleFRow.field.text = fuelAngleF.toFixed(1)
        tempAngleStartRow.field.text = tempAngleStart.toFixed(1)
        tempAngleEndRow.field.text = tempAngleEnd.toFixed(1)
    }

    // Применить и закрыть: коэффициенты уходят сигналом в Main.qml,
    // пробег сразу отдаём в CanBackend — он его хранит и показывает.
    function apply() {
        const sf = parseFloat(speedRow.field.text)
        const rf = parseFloat(rpmRow.field.text)
        const ff = parseFloat(fuelRow.field.text)
        const tf = parseFloat(tempRow.field.text)
        const km = parseFloat(odometerRow.field.text)

        // Пустое или битое поле не должно обнулять коэффициент — оставляем как было
        if (isFinite(sf)) speedFactor = sf
        if (isFinite(rf)) rpmFactor = rf
        if (isFinite(ff)) fuelFactor = ff
        if (isFinite(tf)) tempFactor = tf

        // Калибровка углов стрелок топлива/температуры
        const fuelE = parseFloat(fuelAngleERow.field.text)
        const fuelF = parseFloat(fuelAngleFRow.field.text)
        const tempS = parseFloat(tempAngleStartRow.field.text)
        const tempE = parseFloat(tempAngleEndRow.field.text)
        if (isFinite(fuelE)) fuelAngleE = fuelE
        if (isFinite(fuelF)) fuelAngleF = fuelF
        if (isFinite(tempS)) tempAngleStart = tempS
        if (isFinite(tempE)) tempAngleEnd = tempE
        appSettings.savedFuelAngleE = fuelAngleE
        appSettings.savedFuelAngleF = fuelAngleF
        appSettings.savedTempAngleStart = tempAngleStart
        appSettings.savedTempAngleEnd = tempAngleEnd

        appSettings.savedSpeedFactor = speedFactor
        appSettings.savedRpmFactor = rpmFactor
        appSettings.savedFuelFactor = fuelFactor
        appSettings.savedTempFactor = tempFactor
        appSettings.savedFunEnabled = funEnabled
        appSettings.savedWeatherEnabled = weatherEnabled
        appSettings.savedCameraWarningEnabled = cameraWarningEnabled

        settingsApplied(speedFactor, rpmFactor, fuelFactor, tempFactor)

        // Пробег и объём бака проверяет сам бэкенд: отрицательное, NaN и
        // неправдоподобные значения он игнорирует
        if (isFinite(km) && km >= 0) {
            CanBackend.setOdometer(km)
            odometerRow.field.text = CanBackend.odometer.toFixed(1)
        }

        const tank = parseFloat(tankRow.field.text)
        if (isFinite(tank) && tank >= 1 && tank <= 500) {
            CanBackend.tankCapacity = tank
            tankRow.field.text = CanBackend.tankCapacity.toFixed(0)
        }

        visible = false
    }

    // Отмена: возвращаем сохранённые значения, введённое забываем
    function revert() {
        speedFactor = appSettings.savedSpeedFactor
        rpmFactor = appSettings.savedRpmFactor
        fuelFactor = appSettings.savedFuelFactor
        tempFactor = appSettings.savedTempFactor
        funEnabled = appSettings.savedFunEnabled
        weatherEnabled = appSettings.savedWeatherEnabled
        cameraWarningEnabled = appSettings.savedCameraWarningEnabled
        settingsApplied(speedFactor, rpmFactor, fuelFactor, tempFactor)
        updateInputs()
        visible = false
    }

    // Строка настройки: подпись — поле ввода — пояснение
    component SettingsRow: Row {
        property string label
        property alias field: input
        property string hint

        spacing: 18

        Text {
            text: parent.label
            width: 320
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
            color: settingsOverlay.labelColor
            font.pixelSize: 24
        }

        TextField {
            id: input
            width: 220
            anchors.verticalCenter: parent.verticalCenter
            color: settingsOverlay.valueColor
            font.pixelSize: 24
            font.family: settingsOverlay.uiFont
            horizontalAlignment: Text.AlignRight
            selectByMouse: true
            background: Rectangle {
                color: "#2A2A2A"
                radius: 6
                border.color: "#555"
            }
        }

        Text {
            text: parent.hint
            width: 160
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
            color: "#8A8A8A"
            font.pixelSize: 18
        }
    }

    // Затемнение всего экрана и перехват нажатий: пока настройки открыты,
    // клики не должны попадать на панель под ними
    Rectangle {
        anchors.fill: parent
        color: "#CC000000"

        MouseArea {
            anchors.fill: parent
            onClicked: {}   // гасим нажатие, но окно не закрываем
        }
    }

    // Само окно настроек
    Rectangle {
        id: panel
        width: 1000
        // Фиксированная высота: шапка сверху, строки прокручиваются в
        // середине, кнопки прижаты к низу и не перекрывают строки.
        height: 664
        anchors.centerIn: parent
        radius: 18
        color: "#1A1A1A"
        border.color: "#444"
        border.width: 2

        Text {
            id: panelTitle
            anchors.top: parent.top
            anchors.topMargin: 22
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Настройки приборки"
            color: settingsOverlay.valueColor
            font.pixelSize: 34
            font.bold: true
            font.family: settingsOverlay.uiFont
        }

        Text {
            id: panelSubtitle
            anchors.top: panelTitle.bottom
            anchors.topMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Коэффициенты подгоняют показания под конкретную машину"
            color: "#8A8A8A"
            font.pixelSize: 18
        }

        Flickable {
            id: settingsFlick
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: panelSubtitle.bottom
            anchors.bottom: settingsButtons.top
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 12
            anchors.bottomMargin: 12
            contentWidth: width
            contentHeight: settingsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: settingsColumn
                width: parent.width
                spacing: 12



            Item { width: 1; height: 8 }

            SettingsRow {
                id: speedRow
                label: "Скорость"
                hint: "множитель, 1.00 — как есть"
                x: (parent.width - 736) / 2
                field.validator: DoubleValidator { bottom: 0.1; top: 10.0 }
            }

            SettingsRow {
                id: rpmRow
                label: "Обороты"
                hint: "множитель, 1.00 — как есть"
                x: (parent.width - 736) / 2
                field.validator: DoubleValidator { bottom: 0.1; top: 10.0 }
            }

            SettingsRow {
                id: fuelRow
                label: "Топливо"
                hint: "множитель, 1.00 — как есть"
                x: (parent.width - 736) / 2
                field.validator: DoubleValidator { bottom: 0.1; top: 10.0 }
            }

            SettingsRow {
                id: tempRow
                label: "Температура"
                hint: "множитель, 1.00 — как есть"
                x: (parent.width - 736) / 2
                field.validator: DoubleValidator { bottom: 0.1; top: 10.0 }
            }

            Item { width: 1; height: 6 }

            Rectangle {
                width: 736
                height: 2
                x: (parent.width - 736) / 2
                color: "#333"
            }

            Item { width: 1; height: 6 }

            Text {
                text: "Калибровка стрелок: топливо и температура (° поворота)"
                x: (parent.width - 736) / 2
                color: "#8A8A8A"
                font.pixelSize: 18
            }

            Item { width: 1; height: 4 }

            SettingsRow {
                id: fuelAngleERow
                label: "Топливо: при E"
                hint: "пустой бак"
                x: (parent.width - 736) / 2
                field.validator: DoubleValidator { bottom: -360.0; top: 360.0 }
            }

            SettingsRow {
                id: fuelAngleFRow
                label: "Топливо: при F"
                hint: "полный бак"
                x: (parent.width - 736) / 2
                field.validator: DoubleValidator { bottom: -360.0; top: 360.0 }
            }

            SettingsRow {
                id: tempAngleStartRow
                label: "Темп.: при 40 °C"
                hint: "начало шкалы"
                x: (parent.width - 736) / 2
                field.validator: DoubleValidator { bottom: -360.0; top: 360.0 }
            }

            SettingsRow {
                id: tempAngleEndRow
                label: "Темп.: при 120 °C"
                hint: "максимум"
                x: (parent.width - 736) / 2
                field.validator: DoubleValidator { bottom: -360.0; top: 360.0 }
            }

            Item { width: 1; height: 6 }

            Rectangle {
                width: 736
                height: 2
                x: (parent.width - 736) / 2
                color: "#333"
            }

            Item { width: 1; height: 6 }

            SettingsRow {
                id: odometerRow
                label: "Пробег, км"
                hint: "показание старой приборки при замене"
                x: (parent.width - 736) / 2
                field.validator: DoubleValidator { bottom: 0.0; top: 9999999.0 }
            }

            // Объём бака нужен для расчёта запаса хода: уровень топлива приходит
            // в процентах, запас считается через литры, поэтому без объёма бака
            // километры не посчитать.
            SettingsRow {
                id: tankRow
                label: "Объём бака, л"
                hint: "для расчёта запаса хода"
                x: (parent.width - 736) / 2
                field.validator: DoubleValidator { bottom: 1.0; top: 500.0 }
            }

            Item { width: 1; height: 8 }

            Rectangle {
                width: 736
                height: 2
                x: (parent.width - 736) / 2
                color: "#333"
            }

            Item { width: 1; height: 8 }

            // «Приколы»: анимация в правом верхнем углу — монетки в кошелёк на
            // газу и кочегар с пачками денег выше 5000 об/мин. Выключатель
            // отдельной строкой, состояние хранится в настройках.
            Row {
                spacing: 18
                x: (parent.width - 736) / 2

                Text {
                    text: "Приколы"
                    width: 320
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                    color: settingsOverlay.labelColor
                    font.pixelSize: 24
                }

                Switch {
                    id: funSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    checked: settingsOverlay.funEnabled
                    onToggled: settingsOverlay.funEnabled = checked

                    indicator: Rectangle {
                        implicitWidth: 78
                        implicitHeight: 36
                        radius: 18
                        color: funSwitch.checked ? "#2A7A3A" : "#3A3A3A"
                        border.color: funSwitch.checked ? "#3FBF57" : "#5A5A5A"
                        border.width: 2

                        Rectangle {
                            y: 4
                            x: funSwitch.checked ? parent.width - width - 4 : 4
                            width: 28
                            height: 28
                            radius: 14
                            color: funSwitch.checked ? "#E8FFE8" : "#9A9A9A"
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                    }

                    // Свой текст не нужен: подпись есть слева
                    contentItem: Item {}
                }

                Text {
                    text: settingsOverlay.funEnabled ? "включены" : "выключены"
                    anchors.verticalCenter: parent.verticalCenter
                    color: settingsOverlay.funEnabled ? "#3FBF57" : "#8A8A8A"
                    font.pixelSize: 20
                    font.family: settingsOverlay.uiFont
                }
            }
            Item { width: 1; height: 8 }

            // «Двери (тест)»: проверка анимации дверей на 3D-модели.
            Row {
                spacing: 18
                x: (parent.width - 736) / 2

                Text {
                    text: "Двери (тест)"
                    width: 320
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                    color: settingsOverlay.labelColor
                    font.pixelSize: 24
                }

                Switch {
                    id: doorsSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    checked: settingsOverlay.doorsOpen
                    onToggled: settingsOverlay.doorsOpen = checked

                    indicator: Rectangle {
                        implicitWidth: 78
                        implicitHeight: 36
                        radius: 18
                        color: doorsSwitch.checked ? "#2A7A3A" : "#3A3A3A"
                        border.color: doorsSwitch.checked ? "#3FBF57" : "#5A5A5A"
                        border.width: 2

                        Rectangle {
                            y: 4
                            x: doorsSwitch.checked ? parent.width - width - 4 : 4
                            width: 28
                            height: 28
                            radius: 14
                            color: doorsSwitch.checked ? "#E8FFE8" : "#9A9A9A"
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                    }

                    contentItem: Item {}
                }

                Text {
                    text: settingsOverlay.doorsOpen ? "открыты" : "закрыты"
                    anchors.verticalCenter: parent.verticalCenter
                    color: settingsOverlay.doorsOpen ? "#3FBF57" : "#8A8A8A"
                    font.pixelSize: 20
                    font.family: settingsOverlay.uiFont
                }
            }
            Item { width: 1; height: 8 }

            // «Капот (тест)»: проверка анимации на 3D-модели.
            Row {
                spacing: 18
                x: (parent.width - 736) / 2

                Text {
                    text: "Капот (тест)"
                    width: 320
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                    color: settingsOverlay.labelColor
                    font.pixelSize: 24
                }

                Switch {
                    id: capotSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    checked: settingsOverlay.capotOpen
                    onToggled: settingsOverlay.capotOpen = checked

                    indicator: Rectangle {
                        implicitWidth: 78
                        implicitHeight: 36
                        radius: 18
                        color: capotSwitch.checked ? "#2A7A3A" : "#3A3A3A"
                        border.color: capotSwitch.checked ? "#3FBF57" : "#5A5A5A"
                        border.width: 2

                        Rectangle {
                            y: 4
                            x: capotSwitch.checked ? parent.width - width - 4 : 4
                            width: 28
                            height: 28
                            radius: 14
                            color: capotSwitch.checked ? "#E8FFE8" : "#9A9A9A"
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                    }

                    contentItem: Item {}
                }

                Text {
                    text: settingsOverlay.capotOpen ? "открыт" : "закрыт"
                    anchors.verticalCenter: parent.verticalCenter
                    color: settingsOverlay.capotOpen ? "#3FBF57" : "#8A8A8A"
                    font.pixelSize: 20
                    font.family: settingsOverlay.uiFont
                }
            }
            Item { width: 1; height: 8 }

            // «Багажник (тест)»: проверка анимации на 3D-модели.
            Row {
                spacing: 18
                x: (parent.width - 736) / 2

                Text {
                    text: "Багажник (тест)"
                    width: 320
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                    color: settingsOverlay.labelColor
                    font.pixelSize: 24
                }

                Switch {
                    id: trunkSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    checked: settingsOverlay.trunkOpen
                    onToggled: settingsOverlay.trunkOpen = checked

                    indicator: Rectangle {
                        implicitWidth: 78
                        implicitHeight: 36
                        radius: 18
                        color: trunkSwitch.checked ? "#2A7A3A" : "#3A3A3A"
                        border.color: trunkSwitch.checked ? "#3FBF57" : "#5A5A5A"
                        border.width: 2

                        Rectangle {
                            y: 4
                            x: trunkSwitch.checked ? parent.width - width - 4 : 4
                            width: 28
                            height: 28
                            radius: 14
                            color: trunkSwitch.checked ? "#E8FFE8" : "#9A9A9A"
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                    }

                    contentItem: Item {}
                }

                Text {
                    text: settingsOverlay.trunkOpen ? "открыт" : "закрыт"
                    anchors.verticalCenter: parent.verticalCenter
                    color: settingsOverlay.trunkOpen ? "#3FBF57" : "#8A8A8A"
                    font.pixelSize: 20
                    font.family: settingsOverlay.uiFont
                }
            }
            Item { width: 1; height: 8 }

            // «Симулировать заправку»: тест — mock поднимает уровень топлива
            // 3 %/с на 8 секунд; приборка ловит заправку и показывает пистолет.
            Row {
                spacing: 18
                x: (parent.width - 736) / 2

                Button {
                    id: fuelingButton
                    width: 320
                    height: 56
                    text: "Симулировать заправку"
                    background: Rectangle {
                        color: fuelingButton.pressed ? "#3FBF57" : "#2A7A3A"
                        radius: 8
                    }
                    contentItem: Text {
                        text: fuelingButton.text
                        color: "white"
                        font.pixelSize: 20
                        font.bold: true
                        font.family: settingsOverlay.uiFont
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: CanBackend.simulateFueling()
                }
            }
            Item { width: 1; height: 8 }

            // «Камеры»: предупреждения Smart Driver (SpeedCamManager).
            // Ниже — состояние базы (сколько точек и когда обновлена) и кнопка
            // демо-камеры: без реальной базы предупреждение иначе не увидеть.
            Row {
                spacing: 18
                x: (parent.width - 736) / 2

                Text {
                    text: "Камеры"
                    width: 320
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                    color: settingsOverlay.labelColor
                    font.pixelSize: 24
                }

                Switch {
                    id: cameraSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    checked: settingsOverlay.cameraWarningEnabled
                    onToggled: settingsOverlay.cameraWarningEnabled = checked

                    indicator: Rectangle {
                        implicitWidth: 78
                        implicitHeight: 36
                        radius: 18
                        color: cameraSwitch.checked ? "#2A7A3A" : "#3A3A3A"
                        border.color: cameraSwitch.checked ? "#3FBF57" : "#5A5A5A"
                        border.width: 2

                        Rectangle {
                            y: 4
                            x: cameraSwitch.checked ? parent.width - width - 4 : 4
                            width: 28
                            height: 28
                            radius: 14
                            color: cameraSwitch.checked ? "#E8FFE8" : "#9A9A9A"
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                    }

                    contentItem: Item {}
                }

                Text {
                    text: settingsOverlay.cameraWarningEnabled ? "включены" : "выключены"
                    anchors.verticalCenter: parent.verticalCenter
                    color: settingsOverlay.cameraWarningEnabled ? "#3FBF57" : "#8A8A8A"
                    font.pixelSize: 20
                    font.family: settingsOverlay.uiFont
                }
            }
            Item { width: 1; height: 8 }

            // Состояние базы камер: точек и дата обновления (обновляет
            // update_speedcam.sh по systemd-таймеру, см. docs/speedcam.md).
            Text {
                x: (parent.width - 736) / 2
                width: 736
                text: SpeedCamManager.statusText
                color: "#7A828E"
                font.pixelSize: 18
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
            Item { width: 1; height: 8 }

            // «Симулировать камеру»: тест — ставит камеру в 420 м впереди
            // машины по её курсу (или на север, если курса нет) и сразу
            // показывает предупреждение. Повторное нажатие убирает камеру.
            Row {
                spacing: 18
                x: (parent.width - 736) / 2

                Button {
                    id: cameraButton
                    width: 320
                    height: 56
                    text: SpeedCamManager.demoCameraActive ? "Убрать демо-камеру" : "Симулировать камеру"
                    background: Rectangle {
                        color: cameraButton.pressed ? "#C08A18" : "#8A6410"
                        radius: 8
                    }
                    contentItem: Text {
                        text: cameraButton.text
                        color: "white"
                        font.pixelSize: 20
                        font.bold: true
                        font.family: settingsOverlay.uiFont
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        if (SpeedCamManager.demoCameraActive)
                            SpeedCamManager.clearSimulated()
                        else
                            SpeedCamManager.simulateCameraAhead(60, 420)
                    }
                }
            }
            Item { width: 1; height: 8 }

            // «Погода»: дождь/снег на панели, когда за окном непогода
            // (WeatherProvider, Open-Meteo). Выключатель отдельной строкой.
            Row {
                spacing: 18
                x: (parent.width - 736) / 2

                Text {
                    text: "Погода"
                    width: 320
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                    color: settingsOverlay.labelColor
                    font.pixelSize: 24
                }

                Switch {
                    id: weatherSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    checked: settingsOverlay.weatherEnabled
                    onToggled: settingsOverlay.weatherEnabled = checked

                    indicator: Rectangle {
                        implicitWidth: 78
                        implicitHeight: 36
                        radius: 18
                        color: weatherSwitch.checked ? "#2A7A3A" : "#3A3A3A"
                        border.color: weatherSwitch.checked ? "#3FBF57" : "#5A5A5A"
                        border.width: 2

                        Rectangle {
                            y: 4
                            x: weatherSwitch.checked ? parent.width - width - 4 : 4
                            width: 28
                            height: 28
                            radius: 14
                            color: weatherSwitch.checked ? "#E8FFE8" : "#9A9A9A"
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                    }

                    contentItem: Item {}
                }

                Text {
                    text: settingsOverlay.weatherEnabled ? "включена" : "выключена"
                    anchors.verticalCenter: parent.verticalCenter
                    color: settingsOverlay.weatherEnabled ? "#3FBF57" : "#8A8A8A"
                    font.pixelSize: 20
                    font.family: settingsOverlay.uiFont
                }
            }

        }
        }

    // Кнопки «Сохранить/Отмена» всегда на виду: вынесены из прокручиваемой
    // области — иначе при большом числе строк их уносило за нижний край.
    Row {
        id: settingsButtons
        spacing: 24
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16

                Button {
                    id: saveButton
                    text: "Сохранить"
                    width: 220
                    height: 56
                    background: Rectangle {
                        color: "#2A7A3A"
                        radius: 8
                    }
                    contentItem: Text {
                        text: saveButton.text
                        color: "white"
                        font.pixelSize: 22
                        font.bold: true
                        font.family: settingsOverlay.uiFont
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: settingsOverlay.apply()
                }

                Button {
                    id: cancelButton
                    text: "Отмена"
                    width: 220
                    height: 56
                    background: Rectangle {
                        color: "#4A4A4A"
                        radius: 8
                    }
                    contentItem: Text {
                        text: cancelButton.text
                        color: "white"
                        font.pixelSize: 22
                        font.bold: true
                        font.family: settingsOverlay.uiFont
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: settingsOverlay.revert()
                }
    }
    }

    // Клавиши: Esc — отмена, Enter — сохранить. На столе разработчика удобно,
    // и это же понадобится, когда появятся кнопки на руле.
    focus: visible
    Keys.onEscapePressed: settingsOverlay.revert()
    Keys.onReturnPressed: settingsOverlay.apply()
    Keys.onEnterPressed: settingsOverlay.apply()
}
