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
    }

    // Загружаем сохранённые значения при старте приложения
    Component.onCompleted: {
        speedFactor = appSettings.savedSpeedFactor
        rpmFactor = appSettings.savedRpmFactor
        fuelFactor = appSettings.savedFuelFactor
        tempFactor = appSettings.savedTempFactor
        funEnabled = appSettings.savedFunEnabled
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

        appSettings.savedSpeedFactor = speedFactor
        appSettings.savedRpmFactor = rpmFactor
        appSettings.savedFuelFactor = fuelFactor
        appSettings.savedTempFactor = tempFactor
        appSettings.savedFunEnabled = funEnabled

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
        height: 560
        anchors.centerIn: parent
        radius: 18
        color: "#1A1A1A"
        border.color: "#444"
        border.width: 2

        Column {
            anchors.centerIn: parent
            spacing: 14

            Text {
                text: "Настройки приборки"
                anchors.horizontalCenter: parent.horizontalCenter
                color: settingsOverlay.valueColor
                font.pixelSize: 34
                font.bold: true
                font.family: settingsOverlay.uiFont
            }

            Text {
                text: "Коэффициенты подгоняют показания под конкретную машину"
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#8A8A8A"
                font.pixelSize: 18
            }

            Item { width: 1; height: 8 }

            SettingsRow {
                id: speedRow
                label: "Скорость"
                hint: "множитель, 1.00 — как есть"
                anchors.horizontalCenter: parent.horizontalCenter
                field.validator: DoubleValidator { bottom: 0.1; top: 10.0 }
            }

            SettingsRow {
                id: rpmRow
                label: "Обороты"
                hint: "множитель, 1.00 — как есть"
                anchors.horizontalCenter: parent.horizontalCenter
                field.validator: DoubleValidator { bottom: 0.1; top: 10.0 }
            }

            SettingsRow {
                id: fuelRow
                label: "Топливо"
                hint: "множитель, 1.00 — как есть"
                anchors.horizontalCenter: parent.horizontalCenter
                field.validator: DoubleValidator { bottom: 0.1; top: 10.0 }
            }

            SettingsRow {
                id: tempRow
                label: "Температура"
                hint: "множитель, 1.00 — как есть"
                anchors.horizontalCenter: parent.horizontalCenter
                field.validator: DoubleValidator { bottom: 0.1; top: 10.0 }
            }

            Item { width: 1; height: 6 }

            Rectangle {
                width: panel.width - 120
                height: 2
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#333"
            }

            Item { width: 1; height: 6 }

            SettingsRow {
                id: odometerRow
                label: "Пробег, км"
                hint: "показание старой приборки при замене"
                anchors.horizontalCenter: parent.horizontalCenter
                field.validator: DoubleValidator { bottom: 0.0; top: 9999999.0 }
            }

            // Объём бака нужен для расчёта запаса хода: уровень топлива приходит
            // в процентах, запас считается через литры, поэтому без объёма бака
            // километры не посчитать.
            SettingsRow {
                id: tankRow
                label: "Объём бака, л"
                hint: "для расчёта запаса хода"
                anchors.horizontalCenter: parent.horizontalCenter
                field.validator: DoubleValidator { bottom: 1.0; top: 500.0 }
            }

            Item { width: 1; height: 8 }

            Rectangle {
                width: panel.width - 120
                height: 2
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#333"
            }

            Item { width: 1; height: 8 }

            // «Приколы»: анимация в правом верхнем углу — монетки в кошелёк на
            // газу и кочегар с пачками денег выше 5000 об/мин. Выключатель
            // отдельной строкой, состояние хранится в настройках.
            Row {
                spacing: 18
                anchors.horizontalCenter: parent.horizontalCenter

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

            Item { width: 1; height: 6 }

            Row {
                spacing: 24
                anchors.horizontalCenter: parent.horizontalCenter

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
    }

    // Клавиши: Esc — отмена, Enter — сохранить. На столе разработчика удобно,
    // и это же понадобится, когда появятся кнопки на руле.
    focus: visible
    Keys.onEscapePressed: settingsOverlay.revert()
    Keys.onReturnPressed: settingsOverlay.apply()
    Keys.onEnterPressed: settingsOverlay.apply()
}
