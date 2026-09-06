import QtQuick
import qs.Ui

BarWidget {
    id: root
    moduleName: "vornashev.remote-hosts"

    readonly property var panelItem: panelLoader.item
    readonly property bool opened: panelItem ? panelItem.opened === true : false
    readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false
    readonly property real openPanelIndicatorWidth: 0.01

    function injectPanel() {
        if (!panelItem) return
        panelItem.bar = root.bar
        panelItem.settings = root.settings
    }
    function open() { if (panelItem) panelItem.open() }
    function close() { if (panelItem) panelItem.close() }
    function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

    implicitWidth: panelItem ? panelItem.implicitWidth : barSize
    implicitHeight: panelItem ? panelItem.implicitHeight : barSize
    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Loader {
        id: panelLoader
        anchors.fill: parent
        active: true
        source: Qt.resolvedUrl("Widget.qml")
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
    }
}
