pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui
import "state" as State

Ui.Panel {
    id: root
    moduleName: "tema.remote-devices"
    ipcTarget: "tema.remote-devices"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    property var profiles: ({version: 1, groups: [], devices: []})
    property var statuses: ({})
    property var sftpStates: ({})
    property var globalConfig: ({version: 1, defaultTerminal: "ghostty"})
    property var terminals: []
    property bool settingsLoaded: false
    readonly property bool terminalAvailable: terminals.some(function(t) { return t.value === terminalChoice.value && t.available })
    readonly property var agentLabels: ({
        pi: "Pi", codex: "Codex", claude: "Claude", opencode: "OpenCode",
        gemini: "Gemini CLI", aider: "Aider", goose: "Goose", amp: "Amp",
        copilot: "GitHub Copilot", qwen: "Qwen Code"
    })
    property double clockMs: Date.now()
    property string message: ""
    property bool error: false
    property bool loaded: false
    property bool refreshAfterLoad: false
    property string page: "list"
    property string editId: ""
    property string groupId: ""
    property string actionId: ""
    property string confirmKind: ""
    property string confirmId: ""
    property string importToken: ""
    property string importSummary: ""
    property string previewRows: ""
    property string hostKeyDeviceId: ""
    property string hostKeyEndpoint: ""
    property string hostKeyToken: ""
    property string hostKeyRows: ""
    property var hostKeyKeys: []
    property string hostKeyState: ""
    property string hostKeyMessage: ""
    property string pendingLaunchId: ""
    property string pendingLaunchClient: ""
    property string pendingLaunchAgent: ""
    property var draftStatus: null
    readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("helper.py").toString().replace(/^file:\/\//, ""))
    readonly property bool busy: request.running
    readonly property color surfaceColor: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
    readonly property color secondaryText: Qt.tint(surfaceColor, Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.72))
    property Item scrollFocusItem: null

    onPageChanged: {
        message = ""
        error = false
        Qt.callLater(function() {
            flick.contentY = 0
            if (root.page !== "device" && root.page !== "group" && root.page !== "hostkey")
                pageFrame.forceActiveFocus()
        })
    }
    onMessageChanged: {
        messageTimer.stop()
        if (message !== "" && !error) messageTimer.restart()
    }
    onErrorChanged: {
        if (error) messageTimer.stop()
        else if (message !== "") messageTimer.restart()
    }
    function ensureVisible(item) {
        if (!item || !item.visible || !item.activeFocus) return
        var ancestor = item.parent
        while (ancestor && ancestor !== content) ancestor = ancestor.parent
        if (!ancestor) return
        scrollFocusItem = item
        Qt.callLater(function() {
            if (!item || !item.visible || !item.activeFocus) return
            content.ensurePolished()
            var y = item.mapToItem(content, 0, 0).y
            var margin = Style.space(8)
            if (y < flick.contentY + margin) flick.contentY = Math.max(0, y - margin)
            else if (y + item.height > flick.contentY + flick.height - margin)
                flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, y + item.height - flick.height + margin))
        })
    }
    function navigateBack() {
        if (busy) return
        if (page === "device") requestDelete("discardDraft", "")
        else if (page === "group") page = "groups"
        else showList()
    }

    function call(payload) {
        if (busy) return
        error = false
        message = ""
        request.operation = payload.op
        request.payload = JSON.stringify(payload)
        request.running = true
        requestGuard.restart()
    }
    function refresh() {
        if (!loaded || checker.running) return
        checker.operation = "all"
        checker.deviceId = ""
        checker.payload = JSON.stringify({op: "check"})
        checker.running = true
        checkGuard.restart()
    }
    function refreshDevice(d) {
        if (!loaded || checker.running || !d) return
        checker.operation = "device"
        checker.deviceId = d.id
        checker.payload = JSON.stringify({op: "checkDevice", id: d.id})
        checker.running = true
        checkGuard.restart()
    }
    function openSettings() {
        if (busy) return
        page = "settings"
        settingsLoaded = false
        call({op: "getSettings"})
    }
    function clearPendingLaunch() {
        pendingLaunchId = ""
        pendingLaunchClient = ""
        pendingLaunchAgent = ""
    }
    function launchDevice(id, client) {
        if (busy) return
        pendingLaunchId = id
        pendingLaunchClient = client || ""
        pendingLaunchAgent = ""
        var payload = {op: "launch", id: id}
        if (client) payload.client = client
        call(payload)
    }
    function launchAgent(id, agent) {
        if (busy) return
        pendingLaunchId = id
        pendingLaunchClient = ""
        pendingLaunchAgent = agent
        call({op: "launchAgent", id: id, agent: agent})
    }
    function agentEnabled(agent) {
        return State.DraftState.agents.indexOf(agent) >= 0
    }
    function toggleAgent(agent) {
        var next = State.DraftState.agents.slice()
        var index = next.indexOf(agent)
        if (index >= 0) next.splice(index, 1); else next.push(agent)
        State.DraftState.agents = next
    }
    function agentLabel(agent) {
        return agentLabels[agent] || agent
    }
    function agentIcon(agent) {
        return agent === "pi" ? "π" : "󰚩"
    }
    function inspectHostKey(id) {
        if (busy) return
        clearPendingLaunch()
        call({op: "scanHostKey", id: id})
    }
    function requestDelete(kind, id) {
        if (busy) return
        confirmKind = kind
        confirmId = id
        deleteConfirm.selectedIndex = 0
        pageFrame.forceActiveFocus()
    }
    function showList() {
        clearPendingLaunch()
        page = "list"
        confirmKind = ""
        hostKeyDeviceId = ""
        hostKeyEndpoint = ""
        hostKeyToken = ""
        hostKeyRows = ""
        hostKeyKeys = []
        hostKeyState = ""
        hostKeyMessage = ""
    }
    function discardDeviceDraft() {
        State.DraftState.clear()
        passwordField.text = ""
        showList()
    }
    function finishDeviceSave() {
        State.DraftState.clear()
        passwordField.text = ""
        showList()
    }
    function focusItem(key) {
        if (key === "host") return hostField
        if (key === "port") return portField
        if (key === "login") return loginField
        if (key === "key") return keyField
        if (key === "password") return passwordField
        if (key === "agentFolder") return agentFolderField
        if (key === "folder") return folderField
        if (key === "note") return noteField
        return nameField
    }
    function rememberDraftFocus(key, item) {
        if (item.activeFocus && State.DraftState.active) {
            State.DraftState.focusKey = key
            ensureVisible(item)
        }
    }
    function restoreDraftFocus() {
        if (!opened || page !== "device") return
        if (State.DraftState.focusKey === "agentFolder") State.DraftState.aiExpanded = true
        if (State.DraftState.focusKey === "folder" || State.DraftState.focusKey === "note")
            State.DraftState.advancedExpanded = true
        var target = focusItem(State.DraftState.focusKey)
        if (!target || !target.visible) target = nameField
        Qt.callLater(function() {
            if (root.opened && root.page === "device" && target && target.visible) {
                target.forceActiveFocus()
                root.ensureVisible(target)
            }
        })
    }
    function loadDraft() {
        editId = State.DraftState.editId
        nameField.text = State.DraftState.name
        hostField.text = State.DraftState.host
        portField.text = State.DraftState.port
        loginField.text = State.DraftState.login
        groupChoice.value = State.DraftState.group
        noteField.text = State.DraftState.note
        authChoice.value = State.DraftState.auth
        keyField.text = State.DraftState.keyPath
        agentFolderField.text = State.DraftState.agentFolder
        folderField.text = State.DraftState.remoteFolder
        passwordField.text = State.DraftState.password
    }
    function editDevice(d) {
        State.DraftState.editId = d ? d.id : ""
        State.DraftState.name = d ? d.name : ""
        State.DraftState.host = d ? d.host : ""
        State.DraftState.port = d ? String(d.port) : "22"
        State.DraftState.login = d ? d.login : ""
        State.DraftState.group = d ? d.group : (profiles.groups.length ? profiles.groups[0].id : "")
        State.DraftState.note = d ? d.note : ""
        State.DraftState.auth = d ? d.auth : "agent"
        State.DraftState.keyPath = d ? d.keyPath : ""
        State.DraftState.client = d ? d.client : "ghostty"
        State.DraftState.agents = d && d.agents ? d.agents.slice() : []
        State.DraftState.agentFolder = d ? (d.agentFolder || "") : ""
        State.DraftState.remoteFolder = d ? d.remoteFolder : ""
        State.DraftState.password = ""
        State.DraftState.focusKey = "name"
        State.DraftState.aiExpanded = false
        State.DraftState.advancedExpanded = false
        draftStatus = null
        State.DraftState.active = true
        loadDraft()
        page = "device"
        restoreDraftFocus()
    }
    function checkDraftEndpoint() {
        if (!/^[0-9]{1,5}$/.test(portField.text) || Number(portField.text) < 1 || Number(portField.text) > 65535) {
            message = "SSH-порт: целое число 1–65535"; error = true; return
        }
        draftStatus = null
        call({op: "checkEndpoint", host: hostField.text, port: Number(portField.text)})
    }
    function draftStatusInfo() {
        if (busy && request.operation === "checkEndpoint")
            return {label: "Проверяем Ping и SSH-порт…", icon: "◌", color: Color.accent}
        if (!draftStatus) return {label: "Проверка ещё не выполнялась", icon: "○", color: secondaryText}
        if (draftStatus.ssh === "open") return {label: "Сервер доступен · SSH-порт открыт", icon: "●", color: Color.accent}
        if (draftStatus.ping === "ok") return {label: "Ping есть · SSH-порт недоступен", icon: "▲", color: Color.urgent}
        if (draftStatus.ssh === "dns-error") return {label: "Не удалось разрешить адрес", icon: "!", color: Color.urgent}
        return {label: "Сервер или SSH-порт недоступен", icon: "●", color: Color.urgent}
    }
    function draftStatusDetails() {
        if (!draftStatus) return ""
        var ping = draftStatus.ms !== null ? draftStatus.ms + " мс" : "нет ответа"
        var ssh = draftStatus.ssh === "open" ? "открыт" : draftStatus.ssh === "timeout" ? "тайм-аут" : "закрыт"
        return "Ping: " + ping + " · TCP SSH: " + ssh
    }
    function saveDevice() {
        if (!/^[0-9]{1,5}$/.test(portField.text)) {
            message = "SSH-порт: целое число 1–65535"; error = true; return
        }
        call({op: "saveDevice", device: {
            id: editId, name: nameField.text, host: hostField.text, port: Number(portField.text),
            login: loginField.text, group: groupChoice.value, note: noteField.text,
            auth: authChoice.value, keyPath: authChoice.value === "agent" ? keyField.text : "",
            client: State.DraftState.client || "ghostty", launchMode: "shell", customExecutable: "",
            agents: State.DraftState.agents, agentFolder: agentFolderField.text,
            remoteFolder: folderField.text
        }, password: authChoice.value === "password" ? passwordField.text : ""})
        passwordField.text = ""
    }
    function editGroup(g) {
        groupId = g ? g.id : ""
        groupName.text = g ? g.name : ""
        page = "group"
        Qt.callLater(function() { groupName.forceActiveFocus() })
    }
    function matchingStatus(d) {
        var s = statuses[d.id]
        return s && JSON.stringify(s.endpoint) === JSON.stringify([d.host, d.port, d.login]) ? s : null
    }
    function statusInfo(d) {
        if (checker.running && checker.deviceId === d.id)
            return {kind: "pending", label: "Проверка…", icon: "◌", color: Color.accent}
        var s = matchingStatus(d)
        if (!s) return checker.running
            ? {kind: "pending", label: "Проверка…", icon: "◌", color: Color.accent}
            : {kind: "unknown", label: "Не проверено", icon: "○", color: secondaryText}
        if (s.ssh === "open")
            return {kind: "online", label: "Доступен", icon: "●", color: Color.accent}
        if (s.ping === "ok")
            return {kind: "degraded", label: "SSH недоступен", icon: "▲", color: Color.urgent}
        if (s.ssh === "dns-error" || s.ssh === "error" || s.ping === "error")
            return {kind: "error", label: "Ошибка проверки", icon: "!", color: Color.urgent}
        return {kind: "offline", label: "Недоступен", icon: "●", color: Color.urgent}
    }
    function statusPing(d) {
        var s = matchingStatus(d)
        return s && s.ms !== null && s.ms !== undefined ? s.ms + " мс" : ""
    }
    function relativeCheckAge(checkedAt) {
        var checked = Date.parse(checkedAt)
        if (!isFinite(checked)) return "время проверки неизвестно"
        var seconds = Math.max(0, Math.floor((clockMs - checked) / 1000))
        if (seconds < 45) return "проверено только что"
        if (seconds < 3600) return "проверено " + Math.floor(seconds / 60) + " мин назад"
        if (seconds < 86400) return "проверено " + Math.floor(seconds / 3600) + " ч назад"
        return "проверено " + Math.floor(seconds / 86400) + " дн назад"
    }
    function statusDetails(d) {
        var s = matchingStatus(d)
        if (!s) return checker.running ? "Идёт проверка Ping и SSH-порта" : "Проверка ещё не выполнялась"
        var labels = {ok: "ответ", unreachable: "нет ответа", error: "ошибка", unavailable: "недоступен",
            timeout: "тайм-аут", open: "открыт", closed: "закрыт", "dns-error": "ошибка DNS"}
        var ping = s.ms !== null ? s.ms + " мс" : (labels[s.ping] || s.ping)
        return "Ping: " + ping + " · TCP SSH: " + (labels[s.ssh] || s.ssh) + " · " + relativeCheckAge(s.checkedAt)
    }
    function matchingSftpState(d) {
        var state = d ? sftpStates[d.id] : null
        return state && JSON.stringify(state.endpoint) === JSON.stringify([d.host, d.port, d.login, d.remoteFolder])
               ? state.state : "unmounted"
    }
    function onlineCount() {
        var count = 0
        for (var i = 0; i < profiles.devices.length; i++)
            if (statusInfo(profiles.devices[i]).kind === "online") count++
        return count
    }
    function summaryText() {
        if (!loaded) return "ЗАГРУЗКА…"
        if (checker.running) return "ОБНОВЛЯЕМ СТАТУСЫ…"
        return profiles.devices.length + " УСТРОЙСТВ · " + onlineCount() + " ДОСТУПНО"
    }
    function actionDevice() {
        for (var i = 0; i < profiles.devices.length; i++)
            if (profiles.devices[i].id === actionId) return profiles.devices[i]
        return null
    }
    // Match Yandex Music's lifecycle: closing never clears the active mode.
    // DraftState also restores the form if another widget instance opens.
    onOpenedChanged: if (opened) {
        clockMs = Date.now()
        if (State.DraftState.active) {
            // Editing is purely local until Save/Cancel. Do not let list or
            // network refreshes touch the form when the popup reopens.
            loadDraft()
            page = "device"
            restoreDraftFocus()
        } else if (!loaded) {
            refreshAfterLoad = true
            call({op: "list"})
        } else if (page === "list") {
            refresh()
        } else if (page === "settings") {
            openSettings()
        }
    }

    Process {
        id: request
        property string payload: ""
        property string operation: ""
        command: ["python3", root.helperPath]
        stdinEnabled: true
        onStarted: { write(payload + "\n"); payload = "" }
        stdout: StdioCollector {
            id: requestStdout
            waitForEnd: true
        }
        stderr: StdioCollector { waitForEnd: true } // Never forward helper stderr to the shell log.
        onExited: function(code) {
            requestGuard.stop()
            payload = ""
            var reply = requestStdout.text || ""
            try {
                var result = JSON.parse(reply)
                if (!result || typeof result !== "object" || typeof result.ok !== "boolean")
                    throw new Error("Некорректный ответ помощника")
                if (!result.ok) throw new Error(typeof result.error === "string" ? result.error : "Ошибка помощника")
                if (result.data) { root.profiles = result.data; root.loaded = true }
                if (result.globalSettings) {
                    root.globalConfig = result.globalSettings
                    terminalChoice.value = result.globalSettings.defaultTerminal
                    root.settingsLoaded = true
                }
                if (result.terminals) root.terminals = result.terminals
                if (result.sftpStates) {
                    if (operation === "list") root.sftpStates = result.sftpStates
                    else {
                        var mergedSftp = Object.assign({}, root.sftpStates)
                        for (var sftpId in result.sftpStates) mergedSftp[sftpId] = result.sftpStates[sftpId]
                        root.sftpStates = mergedSftp
                    }
                }
                if (result.draftStatus) root.draftStatus = result.draftStatus
                root.error = false
                if (result.preview) {
                    root.importToken = result.token
                    root.importSummary = "Добавить: " + result.preview.added + "; пропустить: " + result.preview.skipped + "; заменить: " + result.preview.replaced
                    root.previewRows = result.previewDevices.map(function(d) { return d.name + " — " + d.login + "@" + d.host + ":" + d.port + " · SSH · " + d.auth + (d.agents && d.agents.length ? "\nAI: " + d.agents.map(root.agentLabel).join(", ") : "") + (d.agentFolder ? "\nПапка AI: " + d.agentFolder : "") + (d.keyPath ? "\nКлюч: " + d.keyPath : "") + (d.remoteFolder ? "\nПапка VS Code/SFTP: " + d.remoteFolder : "") + (d.note ? "\nЗаметка: " + d.note : "") }).join("\n\n")
                }
                if (result.hostKeys) {
                    root.hostKeyDeviceId = result.hostKeys.deviceId
                    root.hostKeyEndpoint = result.hostKeys.endpoint
                    root.hostKeyToken = result.hostKeys.token
                    root.hostKeyKeys = result.hostKeys.keys
                    root.hostKeyRows = result.hostKeys.keys.map(function(k) { return k.algorithm + "\n" + k.fingerprint }).join("\n\n")
                    root.hostKeyState = result.hostKeys.state
                    root.hostKeyMessage = result.hostKeys.message
                    root.page = "hostkey"
                    flick.contentY = 0
                    Qt.callLater(function() {
                        if (root.hostKeyState === "new") trustHostKeyButton.forceActiveFocus()
                        else cancelHostKeyButton.forceActiveFocus()
                    })
                }
                if (operation === "saveDevice") root.finishDeviceSave()
                else if (operation === "trustHostKey") {
                    var retryId = root.pendingLaunchId
                    var retryClient = root.pendingLaunchClient
                    var retryAgent = root.pendingLaunchAgent
                    root.showList()
                    if (retryId !== "") Qt.callLater(function() {
                        if (retryAgent !== "") root.launchAgent(retryId, retryAgent)
                        else root.launchDevice(retryId, retryClient)
                    })
                } else if ((operation === "saveGroup" && root.page === "group") || operation === "deleteGroup") root.page = "groups"
                else if (operation === "deleteDevice" || operation === "import") root.showList()
                else if ((operation === "launch" || operation === "launchAgent") && !result.hostKeys) root.clearPendingLaunch()
                root.message = (operation === "launch" || operation === "launchAgent") && !result.hostKeys
                    ? "Клиент открыт. Результат входа — в его окне."
                    : (result.message || "")
                if (root.refreshAfterLoad) {
                    root.refreshAfterLoad = false
                    Qt.callLater(root.refresh)
                }
                root.restoreDraftFocus()
            } catch (e) {
                root.error = true
                root.message = reply === "" ? "Помощник не ответил; проверьте Python и права"
                                             : (String(e.message).indexOf("JSON") >= 0 ? "Некорректный ответ помощника" : String(e.message))
                if (operation === "launch" || operation === "launchAgent" || operation === "trustHostKey") root.clearPendingLaunch()
                root.refreshAfterLoad = false
            }
        }
    }
    Timer {
        id: requestGuard
        interval: 65000
        onTriggered: {
            request.signal(9); request.payload = ""
            if (request.operation === "launch" || request.operation === "launchAgent" || request.operation === "trustHostKey") root.clearPendingLaunch()
            root.error = true; root.message = "Операция превысила 65 секунд"
        }
    }
    Process {
        id: checker
        property string payload: ""
        property string operation: ""
        property string deviceId: ""
        command: ["python3", root.helperPath]
        stdinEnabled: true
        onStarted: { write(payload + "\n"); payload = "" }
        stdout: StdioCollector {
            id: checkerStdout
            waitForEnd: true
        }
        stderr: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            checkGuard.stop()
            var reply = checkerStdout.text || ""
            try {
                var result = JSON.parse(reply)
                if (!result || typeof result !== "object" || typeof result.ok !== "boolean")
                    throw new Error("Некорректный ответ")
                if (!result.ok) throw new Error(typeof result.error === "string" ? result.error : "Ошибка проверки")
                if (checker.operation === "device") {
                    var merged = Object.assign({}, root.statuses)
                    for (var id in result.statuses) merged[id] = result.statuses[id]
                    root.statuses = merged
                } else {
                    root.statuses = result.statuses
                }
            } catch (e) {
                var detail = reply === "" ? "помощник не ответил"
                                           : (String(e.message).indexOf("JSON") >= 0 ? "некорректный ответ помощника" : String(e.message))
                root.error = true; root.message = "Проверка не выполнена: " + detail
            }
        }
    }
    Timer {
        id: checkGuard
        interval: 90000
        onTriggered: checker.signal(9)
    }
    Timer {
        interval: 30000
        repeat: true
        running: root.opened
        onTriggered: root.clockMs = Date.now()
    }

    Timer {
        id: messageTimer
        interval: 5000
        onTriggered: if (!root.error) root.message = ""
    }

    Ui.BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "󰒋"
        tooltipText: "Удалённые хосты"
        onPressed: function(b) { if (b === Qt.MiddleButton) root.refresh(); else root.toggle() }
    }
    Ui.KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: root.page === "device" && State.DraftState.active
                     ? root.focusItem(State.DraftState.focusKey) : pageFrame
        contentWidth: panel.fittedContentWidth(Style.space(480))
        contentHeight: panel.fittedContentHeight(pageLayout.implicitHeight, Style.space(680))

        // Preserve the theme palette without showing windows behind the form.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -panel.padding
            color: root.surfaceColor
            radius: Style.cornerRadius
        }
        FocusScope {
            id: pageFrame
            anchors.fill: parent
            // Escape/outside click preserves the draft; leaving the editor is explicit.
            Keys.onPressed: function(event) {
                if (deleteConfirm.handleKey(event)) event.accepted = true
                else if (event.key === Qt.Key_Escape) {
                    root.close()
                    event.accepted = true
                }
            }
            ColumnLayout {
                id: pageLayout
                anchors.fill: parent
                enabled: root.confirmKind === ""
                spacing: Style.space(12)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(10)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(10)
                        Ui.PanelActionButton {
                            visible: root.page !== "list"
                            iconText: "󰅁"
                            fontSize: Style.space(20)
                            size: Style.space(34)
                            focusable: true
                            enabled: !root.busy
                            tooltipText: root.page === "group" ? "К группам" : "К устройствам"
                            onClicked: root.navigateBack()
                        }
                        Label {
                            font.bold: true
                            font.pixelSize: Style.font.heading
                            text: root.page === "list" ? "Удалённые хосты"
                                : root.page === "device" ? (root.editId ? "Изменить хост" : "Новый хост")
                                : root.page === "groups" ? "Группы"
                                : root.page === "group" ? (root.groupId ? "Изменить группу" : "Новая группа")
                                : root.page === "transfer" ? "Импорт / экспорт"
                                : root.page === "settings" ? "Настройки"
                                : root.page === "hostkey" ? "Проверка ключа сервера" : "Инструменты устройства"
                        }
                        Ui.PanelActionButton {
                            visible: root.page === "list"
                            iconText: "󰒓"
                            fontSize: Style.space(20)
                            size: Style.space(34)
                            focusable: true
                            enabled: !root.busy
                            tooltipText: "Глобальные настройки"
                            onClicked: root.openSettings()
                        }
                        Ui.PanelActionButton {
                            visible: root.page === "list"
                            iconText: "󰑐"
                            fontSize: Style.space(20)
                            size: Style.space(34)
                            focusable: true
                            enabled: root.loaded && !root.busy && !checker.running
                            tooltipText: "Обновить Ping и SSH-порты"
                            onClicked: root.refresh()
                        }
                    }
                    Caption { visible: root.page === "list"; text: root.summaryText() }
                    Flow {
                        visible: root.page === "list"
                        Layout.fillWidth: true
                        spacing: Style.space(6)
                        enabled: !root.busy
                        Action { text: "+ Устройство"; foreground: Color.accent; enabled: root.loaded; onClicked: root.editDevice(null) }
                        Action { text: "Группы"; bordered: false; enabled: root.loaded; onClicked: root.page = "groups" }
                        Action { text: "Импорт / экспорт"; bordered: false; enabled: root.loaded; onClicked: { root.page = "transfer"; root.importToken = "" } }
                    }
                    Action { visible: root.page === "groups"; text: "+ Группа"; foreground: Color.accent; enabled: !root.busy; onClicked: root.editGroup(null) }
                    Ui.PanelSeparator { Layout.fillWidth: true }
                }
                RowLayout {
                    visible: root.message !== ""
                    Layout.fillWidth: true
                    Label { text: root.message; color: root.error ? Color.urgent : root.secondaryText; font.pixelSize: Style.font.caption }
                    Ui.PanelActionButton {
                        iconText: "󰅖"
                        size: Style.space(28)
                        focusable: true
                        tooltipText: "Закрыть сообщение"
                        onClicked: root.message = ""
                    }
                }
                Flickable {
                    id: flick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    implicitHeight: content.implicitHeight
                    contentWidth: width
                    contentHeight: content.implicitHeight
                    clip: true
                    onContentHeightChanged: root.ensureVisible(root.scrollFocusItem)
                    onHeightChanged: root.ensureVisible(root.scrollFocusItem)
                    boundsBehavior: Flickable.StopAtBounds
                    Controls.ScrollBar.vertical: Controls.ScrollBar {}
                    ColumnLayout {
                        id: content
                        width: flick.width - Style.space(8)
                        spacing: Style.space(12)
                        ColumnLayout {
                            visible: root.page === "list"
                            Layout.fillWidth: true
                            spacing: Style.space(12)
                            enabled: !root.busy
                            Label { visible: root.loaded && root.profiles.devices.length === 0; text: "Пока нет устройств.\nДобавьте сервер, NAS или компьютер." }
                            Repeater {
                                model: root.profiles.groups
                                ColumnLayout {
                                    id: groupRow
                                    required property var modelData
                                    readonly property var groupDevices: root.profiles.devices.filter(function(d) { return d.group === groupRow.modelData.id })
                                    visible: groupDevices.length > 0
                                    Layout.fillWidth: true
                                    spacing: Style.space(6)
                                    Action {
                                        Layout.fillWidth: true
                                        leftAlign: true
                                        bordered: false
                                        iconText: groupRow.modelData.collapsed ? "󰅂" : "󰅀"
                                        text: groupRow.modelData.name + " · " + groupRow.groupDevices.length
                                        foreground: root.secondaryText
                                        onClicked: root.call({op: "saveGroup", id: groupRow.modelData.id, name: groupRow.modelData.name, collapsed: !groupRow.modelData.collapsed})
                                    }
                                    Repeater {
                                        model: groupRow.modelData.collapsed ? [] : groupRow.groupDevices
                                        Ui.BorderSurface {
                                            id: deviceCard
                                            required property var modelData
                                            readonly property var status: root.statusInfo(modelData)
                                            readonly property bool expanded: root.actionId === modelData.id
                                            readonly property string mountState: root.matchingSftpState(modelData)
                                            Layout.fillWidth: true
                                            implicitHeight: cardContent.implicitHeight + Style.space(20)
                                            color: "transparent"
                                            borderSpec: Border.controlSpec("normal", Color.foreground, Color.accent)
                                            radius: Style.cornerRadius
                                            ColumnLayout {
                                                id: cardContent
                                                x: Style.space(10)
                                                y: Style.space(10)
                                                width: parent.width - Style.space(20)
                                                spacing: Style.space(6)
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Label { text: deviceCard.modelData.name; font.bold: true; wrapMode: Text.NoWrap; elide: Text.ElideRight; Layout.minimumWidth: 0 }
                                                    Action {
                                                        bordered: false
                                                        text: deviceCard.status.kind === "pending" ? deviceCard.status.label : (root.statusPing(deviceCard.modelData) || deviceCard.status.label)
                                                        iconText: deviceCard.status.icon
                                                        iconSize: Style.space(12)
                                                        fontSize: Style.font.caption
                                                        foreground: deviceCard.status.kind === "online" ? root.secondaryText : deviceCard.status.color
                                                        enabled: !checker.running
                                                        tooltipText: root.statusDetails(deviceCard.modelData) + "\nПовторить проверку. Открытый порт не подтверждает вход по SSH."
                                                        onClicked: root.refreshDevice(deviceCard.modelData)
                                                    }
                                                }
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Caption {
                                                        text: deviceCard.modelData.login + "@" + deviceCard.modelData.host + ":" + deviceCard.modelData.port
                                                        wrapMode: Text.NoWrap
                                                        elide: Text.ElideMiddle
                                                        Layout.minimumWidth: 0
                                                    }
                                                    Action { text: "SSH"; iconText: "󰆍"; foreground: Color.accent; tooltipText: "Подключиться в выбранном терминале"; onClicked: root.launchDevice(deviceCard.modelData.id) }
                                                    Ui.PanelActionButton {
                                                        iconText: deviceCard.expanded ? "󰅃" : "󰅀"
                                                        fontSize: Style.space(20)
                                                        size: Style.space(34)
                                                        focusable: true
                                                        tooltipText: deviceCard.expanded ? "Скрыть действия" : "Показать действия"
                                                        onClicked: root.actionId = deviceCard.expanded ? "" : deviceCard.modelData.id
                                                        onActiveFocusChanged: if (activeFocus) root.ensureVisible(this)
                                                    }
                                                }
                                                ColumnLayout {
                                                    visible: deviceCard.expanded
                                                    Layout.fillWidth: true
                                                    spacing: Style.space(8)
                                                    Ui.PanelSeparator { Layout.fillWidth: true }
                                                    Flow {
                                                        Layout.fillWidth: true
                                                        spacing: Style.space(4)
                                                        Action {
                                                            text: "Файлы"
                                                            iconText: "󰉋"
                                                            bordered: false
                                                            enabled: deviceCard.mountState !== "foreign"
                                                            tooltipText: deviceCard.mountState === "mounted" ? "Открыть подключённый SFTP" : "Подключить SFTP через SSHFS"
                                                            onClicked: root.launchDevice(deviceCard.modelData.id, "sftp")
                                                        }
                                                        Action { text: "VS Code"; iconText: "󰨞"; bordered: false; enabled: deviceCard.modelData.auth === "agent"; onClicked: root.launchDevice(deviceCard.modelData.id, "vscode") }
                                                        Action { text: "Изменить"; iconText: "󰏫"; bordered: false; onClicked: root.editDevice(deviceCard.modelData) }
                                                        Action { text: "Ещё"; bordered: false; onClicked: { root.actionId = deviceCard.modelData.id; root.page = "actions" } }
                                                    }
                                                    Caption { visible: deviceCard.modelData.auth !== "agent"; text: "VS Code: нужен ключ или SSH-агент." }
                                                    Caption {
                                                        visible: deviceCard.mountState !== "unmounted"
                                                        text: deviceCard.mountState === "mounted" ? "SFTP подключён · отключение в «Ещё»" : "SFTP недоступен: точка подключения занята."
                                                        color: deviceCard.mountState === "foreign" ? Color.urgent : root.secondaryText
                                                    }
                                                    Caption { visible: (deviceCard.modelData.agents || []).length > 0; text: "AI CLI" }
                                                    Flow {
                                                        visible: (deviceCard.modelData.agents || []).length > 0
                                                        Layout.fillWidth: true
                                                        spacing: Style.space(6)
                                                        Repeater {
                                                            model: deviceCard.modelData.agents || []
                                                            Action {
                                                                required property string modelData
                                                                text: root.agentLabel(modelData)
                                                                iconText: root.agentIcon(modelData)
                                                                tooltipText: "Подключиться и запустить " + root.agentLabel(modelData)
                                                                onClicked: root.launchAgent(deviceCard.modelData.id, modelData)
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        ColumnLayout {
                            id: toolsPage
                            visible: root.page === "actions"
                            Layout.fillWidth: true
                            spacing: Style.space(10)
                            enabled: !root.busy && device !== null
                            readonly property var device: root.actionDevice()
                            Label { text: toolsPage.device ? toolsPage.device.name : ""; font.bold: true }
                            Caption { text: toolsPage.device ? root.statusDetails(toolsPage.device) : "" }
                            Caption { visible: text !== ""; text: toolsPage.device ? toolsPage.device.note : "" }
                            Action { Layout.fillWidth: true; leftAlign: true; iconText: "󰆏"; text: "Копировать адрес хоста"; onClicked: root.call({op: "copy", id: root.actionId}) }
                            Action { Layout.fillWidth: true; leftAlign: true; iconText: "󰌆"; text: "Проверить ключ сервера"; onClicked: root.inspectHostKey(root.actionId) }
                            Action {
                                visible: toolsPage.device !== null && root.matchingSftpState(toolsPage.device) === "mounted"
                                Layout.fillWidth: true
                                leftAlign: true
                                iconText: "󰅖"
                                text: "Отключить SFTP"
                                onClicked: root.call({op: "unmountSftp", id: root.actionId})
                            }
                            Ui.PanelSeparator { Layout.fillWidth: true }
                            Action { iconText: "󰆴"; text: "Удалить устройство"; foreground: Color.urgent; onClicked: root.requestDelete("deleteDevice", root.actionId) }
                        }
                        ColumnLayout {
                            visible: root.page === "device"
                            Layout.fillWidth: true
                            spacing: Style.space(12)
                            enabled: !root.busy
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: "Название" }
                                Field { id: nameField; placeholderText: "Например, домашний сервер"; maximumLength: 100; onTextChanged: if (State.DraftState.active) State.DraftState.name = text; onActiveFocusChanged: root.rememberDraftFocus("name", nameField) }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: "Адрес сервера" }
                                Field {
                                    id: hostField
                                    placeholderText: "IPv4, IPv6 без скобок или ASCII-домен"
                                    maximumLength: 253
                                    onTextChanged: {
                                        root.draftStatus = null
                                        if (State.DraftState.active) State.DraftState.host = text
                                    }
                                    onActiveFocusChanged: root.rememberDraftFocus("host", hostField)
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(12)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(4)
                                    Caption { text: "Пользователь" }
                                    Field { id: loginField; placeholderText: "SSH-логин"; maximumLength: 64; onTextChanged: if (State.DraftState.active) State.DraftState.login = text; onActiveFocusChanged: root.rememberDraftFocus("login", loginField) }
                                }
                                ColumnLayout {
                                    Layout.preferredWidth: Style.space(88)
                                    Layout.maximumWidth: Style.space(88)
                                    spacing: Style.space(4)
                                    Caption { text: "Порт" }
                                    Field {
                                        id: portField
                                        placeholderText: "22"
                                        maximumLength: 5
                                        onTextChanged: {
                                            root.draftStatus = null
                                            if (State.DraftState.active) State.DraftState.port = text
                                        }
                                        onActiveFocusChanged: root.rememberDraftFocus("port", portField)
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Action {
                                    text: root.busy && request.operation === "checkEndpoint" ? "Проверяем…" : "Проверить доступность"
                                    enabled: !root.busy && hostField.text.trim() !== "" && portField.text !== ""
                                    onClicked: root.checkDraftEndpoint()
                                }
                                Caption {
                                    visible: root.draftStatus !== null || root.busy && request.operation === "checkEndpoint"
                                    text: root.draftStatusInfo().icon + "  " + root.draftStatusInfo().label
                                    color: root.draftStatusInfo().color
                                }
                                Caption { visible: root.draftStatus !== null; text: root.draftStatusDetails() }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: "Группа" }
                                Choice {
                                    id: groupChoice
                                    options: root.profiles.groups.map(function(g) { return {value: g.id, label: g.name} })
                                    onChanged: function(v) { value = v; if (State.DraftState.active) State.DraftState.group = v }
                                }
                            }
                            Ui.PanelSeparator { Layout.fillWidth: true }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: "Аутентификация" }
                                Choice {
                                    id: authChoice
                                    options: [{value: "agent", label: "Ключ / SSH-агент"}, {value: "password", label: "Пароль"}]
                                    onChanged: function(v) { value = v; passwordField.text = ""; if (State.DraftState.active) { State.DraftState.auth = v; State.DraftState.password = "" } }
                                }
                            }
                            ColumnLayout {
                                visible: authChoice.value === "agent"
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: "Файл ключа · необязательно" }
                                Field { id: keyField; placeholderText: "/home/…/.ssh/id_ed25519"; maximumLength: 1024; onTextChanged: if (State.DraftState.active) State.DraftState.keyPath = text; onActiveFocusChanged: root.rememberDraftFocus("key", keyField) }
                                Caption { text: "Пусто — ключи по умолчанию или SSH-агент." }
                            }
                            ColumnLayout {
                                visible: authChoice.value === "password"
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: root.editId ? "Новый пароль" : "Пароль" }
                                Field { id: passwordField; password: true; placeholderText: root.editId ? "Пусто — оставить сохранённый" : "Пароль SSH"; maximumLength: 4096; onTextChanged: if (State.DraftState.active) State.DraftState.password = text; onActiveFocusChanged: root.rememberDraftFocus("password", passwordField) }
                                Caption { text: "Хранится в Secret Service. При смене адреса, порта или логина введите пароль заново." }
                            }
                            Ui.PanelSeparator { Layout.fillWidth: true }
                            Action {
                                Layout.fillWidth: true
                                leftAlign: true
                                bordered: false
                                iconText: State.DraftState.aiExpanded ? "󰅀" : "󰅂"
                                text: "AI CLI" + (State.DraftState.agents.length ? " · выбрано: " + State.DraftState.agents.length : " · не выбраны")
                                tooltipText: State.DraftState.agents.map(root.agentLabel).join(", ")
                                onClicked: State.DraftState.aiExpanded = !State.DraftState.aiExpanded
                            }
                            ColumnLayout {
                                visible: State.DraftState.aiExpanded
                                Layout.fillWidth: true
                                spacing: Style.space(8)
                                Caption { text: "Выберите CLI, уже установленные на сервере." }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Style.space(6)
                                    Repeater {
                                        model: Object.keys(root.agentLabels)
                                        Action {
                                            required property string modelData
                                            text: root.agentLabel(modelData)
                                            iconText: root.agentEnabled(modelData) ? "󰄬" : root.agentIcon(modelData)
                                            selected: root.agentEnabled(modelData)
                                            onClicked: root.toggleAgent(modelData)
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(4)
                                    Caption { text: "Папка AI CLI · необязательно" }
                                    Field {
                                        id: agentFolderField
                                        placeholderText: "/home/…/project"
                                        maximumLength: 1024
                                        onTextChanged: if (State.DraftState.active) State.DraftState.agentFolder = text
                                        onActiveFocusChanged: root.rememberDraftFocus("agentFolder", agentFolderField)
                                    }
                                    Caption { text: "Пусто — домашний каталог. CLI появятся в действиях карточки." }
                                }
                            }
                            Action {
                                Layout.fillWidth: true
                                leftAlign: true
                                bordered: false
                                iconText: State.DraftState.advancedExpanded ? "󰅀" : "󰅂"
                                text: "Дополнительно · папка и заметка"
                                onClicked: State.DraftState.advancedExpanded = !State.DraftState.advancedExpanded
                            }
                            ColumnLayout {
                                visible: State.DraftState.advancedExpanded
                                Layout.fillWidth: true
                                spacing: Style.space(8)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(4)
                                    Caption { text: "Папка файлов / VS Code · необязательно" }
                                    Field { id: folderField; placeholderText: "/home/…/project"; maximumLength: 1024; onTextChanged: if (State.DraftState.active) State.DraftState.remoteFolder = text; onActiveFocusChanged: root.rememberDraftFocus("folder", folderField) }
                                    Caption { text: "Папка для SFTP и VS Code, отдельно от папки AI CLI." }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(4)
                                    Caption { text: "Заметка · не для секретов" }
                                    Controls.TextArea {
                                        id: noteField
                                        Layout.fillWidth: true
                                        implicitHeight: Style.space(88)
                                        color: Color.foreground
                                        selectionColor: Style.selectionFillFor(Color.foreground, Color.accent)
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.body
                                        wrapMode: TextEdit.Wrap
                                        textFormat: TextEdit.PlainText
                                        background: Ui.BorderSurface {
                                            color: Style.controlFill(noteField.activeFocus, noteField.hovered, Color.foreground, Color.accent)
                                            borderSpec: Border.controlSpec(noteField.activeFocus ? "focus" : "normal", Color.foreground, Color.accent)
                                            radius: Style.cornerRadius
                                        }
                                        onTextChanged: if (State.DraftState.active) State.DraftState.note = text
                                        onActiveFocusChanged: root.rememberDraftFocus("note", noteField)
                                    }
                                }
                            }
                        }
                        ColumnLayout {
                            visible: root.page === "hostkey"
                            Layout.fillWidth: true
                            spacing: Style.space(12)
                            enabled: !root.busy
                            Caption { text: "Адрес known_hosts: " + root.hostKeyEndpoint }
                            Label { text: root.hostKeyRows }
                            Label {
                                text: "ВАЖНО: ssh-keyscan не доказывает подлинность сервера. Сверьте ВСЕ SHA256 fingerprint с администратором или консолью сервера по независимому доверенному каналу. Не подтверждайте ключ только потому, что он показан здесь."
                                color: Color.urgent
                            }
                            Label { text: root.hostKeyMessage }
                            Flow {
                                Layout.fillWidth: true
                                spacing: Style.space(8)
                                Action {
                                    id: trustHostKeyButton
                                    text: "Доверяю после сверки"
                                    enabled: root.hostKeyState === "new" && root.hostKeyToken !== ""
                                    onClicked: root.call({op: "trustHostKey", id: root.hostKeyDeviceId, keys: root.hostKeyKeys, token: root.hostKeyToken})
                                }
                                Action { id: cancelHostKeyButton; text: "Отмена"; onClicked: root.showList() }
                            }
                            Caption { visible: root.hostKeyState !== "new"; text: "Плагин не заменяет и не удаляет существующие записи known_hosts. Разберите смену ключа отдельно через доверенного администратора." }
                        }
                        ColumnLayout {
                            visible: root.page === "groups"
                            Layout.fillWidth: true
                            spacing: Style.space(16)
                            enabled: !root.busy
                            Repeater {
                                model: root.profiles.groups
                                ColumnLayout {
                                    id: groupEdit
                                    required property var modelData
                                    readonly property int deviceCount: root.profiles.devices.filter(function(d) { return d.group === groupEdit.modelData.id }).length
                                    readonly property string deleteReason: deviceCount > 0 ? "Для удаления сначала перенесите устройства в другую группу."
                                        : root.profiles.groups.length <= 1 ? "Последнюю группу удалить нельзя." : ""
                                    Layout.fillWidth: true
                                    spacing: Style.space(6)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: groupEdit.modelData.name; font.bold: true; elide: Text.ElideRight; wrapMode: Text.NoWrap; Layout.minimumWidth: 0 }
                                        Caption { Layout.fillWidth: false; text: "Устройств: " + groupEdit.deviceCount }
                                    }
                                    RowLayout {
                                        Action { text: "Изменить"; iconText: "󰏫"; onClicked: root.editGroup(groupEdit.modelData) }
                                        Action {
                                            text: "Удалить"
                                            bordered: false
                                            foreground: groupEdit.deleteReason === "" ? Color.urgent : root.secondaryText
                                            enabled: groupEdit.deleteReason === ""
                                            onClicked: root.requestDelete("deleteGroup", groupEdit.modelData.id)
                                        }
                                    }
                                    Caption { visible: groupEdit.deleteReason !== ""; text: groupEdit.deleteReason }
                                    Ui.PanelSeparator { Layout.fillWidth: true }
                                }
                            }
                        }
                        ColumnLayout {
                            visible: root.page === "group"
                            Layout.fillWidth: true
                            spacing: Style.space(4)
                            enabled: !root.busy
                            Caption { text: "Название группы" }
                            Field { id: groupName; placeholderText: "Например, работа"; maximumLength: 100 }
                        }
                        ColumnLayout {
                            visible: root.page === "transfer"
                            Layout.fillWidth: true
                            spacing: Style.space(12)
                            enabled: !root.busy
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: "JSON-файл · абсолютный путь" }
                                Field { id: transferPath; placeholderText: "/home/…/devices.json"; onTextChanged: root.importToken = "" }
                            }
                            Label { text: "Экспорт"; font.bold: true }
                            Action { id: notesToggle; property bool checked: false; selected: checked; text: (checked ? "☑ " : "☐ ") + "Включить заметки"; onClicked: checked = !checked }
                            Action { id: pathsToggle; property bool checked: false; selected: checked; text: (checked ? "☑ " : "☐ ") + "Включить пути"; onClicked: checked = !checked }
                            Action { text: "Экспорт в новый файл"; onClicked: root.call({op: "export", path: transferPath.text, notes: notesToggle.checked, paths: pathsToggle.checked}) }
                            Ui.PanelSeparator { Layout.fillWidth: true }
                            Label { text: "Импорт"; font.bold: true }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: "При совпадении адреса, порта и логина" }
                                Choice {
                                    id: duplicateChoice
                                    value: "skip"
                                    options: [{value: "skip", label: "Пропустить"}, {value: "replace", label: "Обновить данные, сохранить локальный вход"}]
                                    onChanged: function(v) { value = v; root.importToken = "" }
                                }
                            }
                            Action { text: "Предпросмотр импорта"; onClicked: { root.importToken = ""; root.call({op: "previewImport", path: transferPath.text, policy: duplicateChoice.value}) } }
                            Label { visible: root.importToken !== ""; text: root.importSummary + "\nИтоговый список:\n" + root.previewRows }
                            Caption { text: "Пароли и содержимое ключей не переносятся. Новые устройства используют ключ / SSH-агент. Проверьте адреса и пути в предпросмотре." }
                            Action { text: "Применить импорт"; enabled: root.importToken !== ""; onClicked: root.call({op: "import", path: transferPath.text, policy: duplicateChoice.value, token: root.importToken}) }
                        }
                        ColumnLayout {
                            visible: root.page === "settings"
                            Layout.fillWidth: true
                            spacing: Style.space(12)
                            enabled: !root.busy && root.settingsLoaded
                            Label { text: "Подключение"; font.bold: true }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: "Терминал по умолчанию" }
                                Choice {
                                    id: terminalChoice
                                    options: root.terminals.map(function(t) {
                                        return {value: t.value, label: t.label + (t.available ? "" : " · не установлен")}
                                    })
                                    onChanged: function(v) { value = v }
                                }
                            }
                            Caption { text: "Общий для кнопки SSH и запуска всех AI CLI на всех устройствах. VS Code и SFTP открываются отдельно." }
                            Caption {
                                visible: root.settingsLoaded && !root.terminalAvailable
                                text: "Этот терминал не найден в PATH. Установите его самостоятельно или выберите доступный."
                            }
                            Ui.PanelSeparator { Layout.fillWidth: true }
                            Caption { text: "Изменения применяются после сохранения к новым подключениям. Уже открытые терминалы не затрагиваются." }
                            Caption { text: "Настройки хранятся отдельно от устройств и не включаются в их импорт / экспорт." }
                        }
                    }
                }
                ColumnLayout {
                    visible: root.page === "device" || root.page === "group" || root.page === "settings"
                    Layout.fillWidth: true
                    spacing: Style.space(10)
                    Ui.PanelSeparator { Layout.fillWidth: true }
                    RowLayout {
                        Layout.fillWidth: true
                        enabled: !root.busy
                        Action { text: "Отмена"; bordered: false; onClicked: root.navigateBack() }
                        Item { Layout.fillWidth: true }
                        Action {
                            text: root.busy && ["saveDevice", "saveGroup", "saveSettings"].indexOf(request.operation) >= 0 ? "Сохраняем…" : "Сохранить"
                            enabled: root.page !== "settings" || (root.settingsLoaded && root.terminalAvailable && terminalChoice.value !== root.globalConfig.defaultTerminal)
                            foreground: Color.accent
                            onClicked: {
                                if (root.page === "device") root.saveDevice()
                                else if (root.page === "settings") root.call({op: "saveSettings", settings: {version: 1, defaultTerminal: terminalChoice.value}})
                                else root.call({op: "saveGroup", id: root.groupId, name: groupName.text})
                            }
                        }
                    }
                }
            }
            Ui.ConfirmDialog {
                id: deleteConfirm
                anchors.fill: parent
                z: 20
                opened: root.confirmKind !== ""
                message: root.confirmKind === "discardDraft" ? "Выйти без сохранения и удалить черновик?"
                    : root.confirmKind === "deleteDevice" ? "Удалить устройство безвозвратно?" : "Удалить группу безвозвратно?"
                cancelText: root.confirmKind === "discardDraft" ? "Продолжить" : "Отмена"
                confirmText: root.confirmKind === "discardDraft" ? "Не сохранять" : "Удалить"
                onCanceled: {
                    root.confirmKind = ""
                    root.confirmId = ""
                    root.restoreDraftFocus()
                }
                onConfirmed: {
                    var kind = root.confirmKind
                    var targetId = root.confirmId
                    root.confirmKind = ""
                    root.confirmId = ""
                    if (kind === "discardDraft") root.discardDeviceDraft()
                    else root.call({op: kind, id: targetId})
                }
            }
        }
    }
    component Label: Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
    }
    component Caption: Label {
        color: root.secondaryText
        font.pixelSize: Style.font.caption
    }
    component Field: Ui.TextField {
        Layout.fillWidth: true
        onActiveFocusChanged: if (activeFocus) root.ensureVisible(this)
    }
    component Choice: FocusScope {
        id: choice
        property alias value: dropdown.value
        property alias options: dropdown.options
        signal changed(string value)
        Layout.fillWidth: true
        implicitHeight: dropdown.implicitHeight
        onActiveFocusChanged: if (activeFocus) root.ensureVisible(this)
        Ui.Dropdown {
            id: dropdown
            anchors.fill: parent
            showLabel: false
            foreground: Color.foreground
            background: root.surfaceColor
            onChanged: function(v) { choice.changed(v) }
        }
    }
    component Action: Ui.Button {
        focusable: true
        bordered: true
        iconSize: Style.space(18)
        opacity: enabled ? 1 : 0.45
        onActiveFocusChanged: if (activeFocus) root.ensureVisible(this)
    }
}
