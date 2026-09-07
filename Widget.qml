pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui
import "state" as State

Ui.Panel {
    id: root
    moduleName: "vornashev.remote-hosts"
    ipcTarget: "vornashev.remote-hosts"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    property var profiles: ({version: 1, groups: [], devices: []})
    property var statuses: ({})
    property var sftpStates: ({})
    property var globalConfig: ({version: 1, defaultTerminal: "ghostty", language: "en"})
    property var terminals: []
    property bool settingsLoaded: false
    readonly property string language: page === "settings" && settingsLoaded
                                       ? languageChoice.value : (globalConfig.language || "en")
    readonly property bool terminalAvailable: terminals.some(function(t) { return t.value === terminalChoice.value && t.available })
    readonly property bool addressesHidden: State.PrivacyState.addressesHidden
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

    function t(text) {
        return State.I18n.t(language, text)
    }

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
    onAddressesHiddenChanged: {
        if (!addressesHidden) return
        var endpointFocused = hostField.activeFocus || loginField.activeFocus || portField.activeFocus
        hostField.deselect()
        loginField.deselect()
        portField.deselect()
        if (endpointFocused) pageFrame.forceActiveFocus()
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
        payload.language = language
        request.operation = payload.op
        request.payload = JSON.stringify(payload)
        request.running = true
        requestGuard.restart()
    }
    function copyEndpoint(d) {
        if (!d) return
        var endpoint = d.login + "@" + d.host + ":" + d.port
        Quickshell.execDetached(["wl-copy", endpoint])
        error = false
        message = root.t("SSH endpoint copied")
    }
    function refresh() {
        if (!loaded || checker.running) return
        checker.operation = "all"
        checker.payload = JSON.stringify({op: "check", language: language})
        checker.running = true
        checkGuard.restart()
    }
    function refreshDevice(d) {
        if (!loaded || checker.running || !d) return
        checker.operation = "device"
        checker.payload = JSON.stringify({op: "checkDevice", id: d.id, language: language})
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
        if (addressesHidden && (key === "host" || key === "login" || key === "port")) return pageFrame
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
            if (root.addressesHidden && (target === hostField || target === loginField || target === portField)) {
                pageFrame.forceActiveFocus()
                return
            }
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
            message = t("SSH port must be an integer from 1 to 65535"); error = true; return
        }
        draftStatus = null
        call({op: "checkEndpoint", host: hostField.text, port: Number(portField.text)})
    }
    function draftStatusInfo() {
        if (busy && request.operation === "checkEndpoint")
            return {label: t("Check ping and SSH port…"), icon: "◌", color: Color.accent}
        if (!draftStatus) return {label: t("No check has run yet"), icon: "○", color: secondaryText}
        if (draftStatus.ssh === "open") return {label: t("Server available · SSH port open"), icon: "●", color: Color.accent}
        if (draftStatus.ping === "ok") return {label: t("Ping responds · SSH port unavailable"), icon: "▲", color: Color.urgent}
        if (draftStatus.ssh === "dns-error") return {label: t("Could not resolve address"), icon: "!", color: Color.urgent}
        return {label: t("Server or SSH port unavailable"), icon: "●", color: Color.urgent}
    }
    function draftStatusDetails() {
        if (!draftStatus) return ""
        var ping = draftStatus.ms !== null ? draftStatus.ms + " ms" : t("no response")
        var ssh = draftStatus.ssh === "open" ? t("open") : draftStatus.ssh === "timeout" ? t("timeout") : t("closed")
        return "Ping: " + ping + " · TCP SSH: " + ssh
    }
    function saveDevice() {
        if (!/^[0-9]{1,5}$/.test(portField.text)) {
            message = t("SSH port must be an integer from 1 to 65535"); error = true; return
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
            return {kind: "pending", label: t("Checking…"), icon: "◌", color: Color.accent}
        var s = matchingStatus(d)
        if (!s) return checker.running
            ? {kind: "pending", label: t("Checking…"), icon: "◌", color: Color.accent}
            : {kind: "unknown", label: t("Not checked"), icon: "○", color: secondaryText}
        if (s.ssh === "open")
            return {kind: "online", label: t("Available"), icon: "●", color: Color.accent}
        if (s.ping === "ok")
            return {kind: "degraded", label: t("SSH unavailable"), icon: "▲", color: Color.urgent}
        if (s.ssh === "dns-error" || s.ssh === "error" || s.ping === "error")
            return {kind: "error", label: t("Check failed"), icon: "!", color: Color.urgent}
        return {kind: "offline", label: t("Unavailable"), icon: "●", color: Color.urgent}
    }
    function statusPing(d) {
        var s = matchingStatus(d)
        return s && s.ms !== null && s.ms !== undefined ? s.ms + " ms" : ""
    }
    function relativeCheckAge(checkedAt) {
        var checked = Date.parse(checkedAt)
        if (!isFinite(checked)) return t("check time unknown")
        var seconds = Math.max(0, Math.floor((clockMs - checked) / 1000))
        if (seconds < 45) return t("checked just now")
        if (seconds < 3600) return language === "ru" ? "проверено " + Math.floor(seconds / 60) + " мин назад"
                                                    : "checked " + Math.floor(seconds / 60) + " min ago"
        if (seconds < 86400) return language === "ru" ? "проверено " + Math.floor(seconds / 3600) + " ч назад"
                                                     : "checked " + Math.floor(seconds / 3600) + " h ago"
        return language === "ru" ? "проверено " + Math.floor(seconds / 86400) + " дн назад"
                                 : "checked " + Math.floor(seconds / 86400) + " d ago"
    }
    function statusDetails(d) {
        var s = matchingStatus(d)
        if (!s) return checker.running ? t("Checking ping and SSH port") : t("No check has run yet")
        var labels = {ok: t("response"), unreachable: t("no response"), error: t("error"), unavailable: t("Unavailable").toLowerCase(),
            timeout: t("timeout"), open: t("open"), closed: t("closed"), "dns-error": t("DNS error")}
        var ping = s.ms !== null ? s.ms + " ms" : (labels[s.ping] || s.ping)
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
        if (!loaded) return t("LOADING…")
        if (checker.running) return t("REFRESHING STATUSES…")
        return language === "ru"
            ? profiles.devices.length + " ХОСТОВ · " + onlineCount() + " ДОСТУПНО"
            : profiles.devices.length + " HOSTS · " + onlineCount() + " AVAILABLE"
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
                    throw new Error(root.t("Invalid helper response"))
                if (!result.ok) throw new Error(typeof result.error === "string" ? result.error : root.t("Helper error"))
                if (result.data) { root.profiles = result.data; root.loaded = true }
                if (result.globalSettings) {
                    terminalChoice.value = result.globalSettings.defaultTerminal
                    languageChoice.value = result.globalSettings.language || "en"
                    root.globalConfig = result.globalSettings
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
                    root.importSummary = root.language === "ru"
                        ? "Добавить: " + result.preview.added + "; пропустить: " + result.preview.skipped + "; заменить: " + result.preview.replaced
                        : "Add: " + result.preview.added + "; skip: " + result.preview.skipped + "; replace: " + result.preview.replaced
                    root.previewRows = result.previewDevices.map(function(d) { return d.name + " — " + d.login + "@" + d.host + ":" + d.port + " · SSH · " + d.auth + (d.agents && d.agents.length ? "\nAI: " + d.agents.map(root.agentLabel).join(", ") : "") + (d.agentFolder ? "\n" + (root.language === "ru" ? "Папка AI: " : "AI folder: ") + d.agentFolder : "") + (d.keyPath ? "\n" + (root.language === "ru" ? "Ключ: " : "Key: ") + d.keyPath : "") + (d.remoteFolder ? "\n" + (root.language === "ru" ? "Папка VS Code/SFTP: " : "VS Code/SFTP folder: ") + d.remoteFolder : "") + (d.note ? "\n" + (root.language === "ru" ? "Заметка: " : "Note: ") + d.note : "") }).join("\n\n")
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
                    ? root.t("Client opened. See its window for the connection result.")
                    : (result.message || "")
                if (root.refreshAfterLoad) {
                    root.refreshAfterLoad = false
                    Qt.callLater(root.refresh)
                }
                root.restoreDraftFocus()
            } catch (e) {
                root.error = true
                root.message = reply === "" ? root.t("Helper did not respond; check Python and permissions")
                                             : (String(e.message).indexOf("JSON") >= 0 ? root.t("Invalid helper response") : String(e.message))
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
            root.error = true; root.message = root.t("Operation exceeded 65 seconds")
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
                    throw new Error(root.t("Invalid helper response"))
                if (!result.ok) throw new Error(typeof result.error === "string" ? result.error : root.t("Check failed"))
                if (checker.operation === "device") {
                    var merged = Object.assign({}, root.statuses)
                    for (var id in result.statuses) merged[id] = result.statuses[id]
                    root.statuses = merged
                } else {
                    root.statuses = result.statuses
                }
            } catch (e) {
                var detail = reply === "" ? root.t("helper did not respond")
                                           : (String(e.message).indexOf("JSON") >= 0 ? root.t("invalid helper response") : String(e.message))
                root.error = true; root.message = root.t("Check failed: ") + detail
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
        tooltipText: root.t("Remote Hosts")
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
                            tooltipText: root.page === "group" ? root.t("Back to groups") : root.t("Back to hosts")
                            onClicked: root.navigateBack()
                        }
                        Label {
                            font.bold: true
                            font.pixelSize: Style.font.heading
                            text: root.page === "list" ? root.t("Remote Hosts")
                                : root.page === "device" ? root.t(root.editId ? "Edit host" : "New host")
                                : root.page === "groups" ? root.t("Groups")
                                : root.page === "group" ? root.t(root.groupId ? "Edit group" : "New group")
                                : root.page === "transfer" ? root.t("Import / export")
                                : root.page === "settings" ? root.t("Settings")
                                : root.page === "hostkey" ? root.t("Verify host key") : root.t("Host tools")
                        }
                        Ui.PanelActionButton {
                            iconText: root.addressesHidden ? "󰈉" : "󰈈"
                            foreground: root.addressesHidden ? Color.accent : Color.foreground
                            fontSize: Style.space(20)
                            size: Style.space(34)
                            focusable: true
                            tooltipText: root.t(root.addressesHidden ? "Show logins and addresses" : "Hide logins and addresses")
                            onClicked: State.PrivacyState.addressesHidden = !State.PrivacyState.addressesHidden
                        }
                        Ui.PanelActionButton {
                            visible: root.page === "list"
                            iconText: "󰒓"
                            fontSize: Style.space(20)
                            size: Style.space(34)
                            focusable: true
                            enabled: !root.busy
                            tooltipText: root.t("Global settings")
                            onClicked: root.openSettings()
                        }
                        Ui.PanelActionButton {
                            visible: root.page === "list"
                            iconText: "󰑐"
                            fontSize: Style.space(20)
                            size: Style.space(34)
                            focusable: true
                            enabled: root.loaded && !root.busy && !checker.running
                            tooltipText: root.t("Refresh ping and SSH ports")
                            onClicked: root.refresh()
                        }
                    }
                    Caption { visible: root.page === "list"; text: root.summaryText() }
                    Flow {
                        visible: root.page === "list"
                        Layout.fillWidth: true
                        spacing: Style.space(6)
                        enabled: !root.busy
                        Action { text: root.t("+ Host"); foreground: Color.accent; enabled: root.loaded; onClicked: root.editDevice(null) }
                        Action { text: root.t("Groups"); bordered: false; enabled: root.loaded; onClicked: root.page = "groups" }
                        Action { text: root.t("Import / export"); bordered: false; enabled: root.loaded; onClicked: { root.page = "transfer"; root.importToken = "" } }
                    }
                    Action { visible: root.page === "groups"; text: root.t("+ Group"); foreground: Color.accent; enabled: !root.busy; onClicked: root.editGroup(null) }
                    Ui.PanelSeparator { Layout.fillWidth: true }
                }
                RowLayout {
                    visible: root.message !== ""
                    Layout.fillWidth: true
                    Label {
                        text: root.message
                        color: root.error ? Color.urgent : root.secondaryText
                        font.pixelSize: Style.font.caption
                        layer.enabled: root.addressesHidden && root.error && visible
                        layer.effect: PrivacyBlur {}
                    }
                    Ui.PanelActionButton {
                        iconText: "󰅖"
                        size: Style.space(28)
                        focusable: true
                        tooltipText: root.t("Dismiss message")
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
                            Label { visible: root.loaded && root.profiles.devices.length === 0; text: root.t("No hosts yet.\nAdd a server, NAS, or computer.") }
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
                                                        tooltipText: root.statusDetails(deviceCard.modelData) + "\n" + root.t("Retry check. An open port does not confirm SSH authentication.")
                                                        onClicked: root.refreshDevice(deviceCard.modelData)
                                                    }
                                                }
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    CopyAddress {
                                                        addressText: deviceCard.modelData.login + "@" + deviceCard.modelData.host + ":" + deviceCard.modelData.port
                                                        onClicked: root.copyEndpoint(deviceCard.modelData)
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    Action { text: "SSH"; iconText: "󰆍"; foreground: Color.accent; tooltipText: root.t("Connect in the selected terminal"); onClicked: root.launchDevice(deviceCard.modelData.id) }
                                                    Ui.PanelActionButton {
                                                        iconText: deviceCard.expanded ? "󰅃" : "󰅀"
                                                        fontSize: Style.space(20)
                                                        size: Style.space(34)
                                                        focusable: true
                                                        tooltipText: root.t(deviceCard.expanded ? "Hide actions" : "Show actions")
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
                                                            text: root.t("Files")
                                                            iconText: "󰉋"
                                                            bordered: false
                                                            enabled: deviceCard.mountState !== "foreign"
                                                            tooltipText: root.t(deviceCard.mountState === "mounted" ? "Open mounted SFTP" : "Mount SFTP using SSHFS")
                                                            onClicked: root.launchDevice(deviceCard.modelData.id, "sftp")
                                                        }
                                                        Action { text: "VS Code"; iconText: "󰨞"; bordered: false; enabled: deviceCard.modelData.auth === "agent"; onClicked: root.launchDevice(deviceCard.modelData.id, "vscode") }
                                                        Action { text: root.t("Edit"); iconText: "󰏫"; bordered: false; onClicked: root.editDevice(deviceCard.modelData) }
                                                        Action { text: root.t("More"); bordered: false; onClicked: { root.actionId = deviceCard.modelData.id; root.page = "actions" } }
                                                    }
                                                    Caption { visible: deviceCard.modelData.auth !== "agent"; text: root.t("VS Code requires a key or SSH agent.") }
                                                    Caption {
                                                        visible: deviceCard.mountState !== "unmounted"
                                                        text: root.t(deviceCard.mountState === "mounted" ? "SFTP mounted · disconnect under More" : "SFTP unavailable: mount point is occupied.")
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
                                                                tooltipText: root.t("Connect and launch ") + root.agentLabel(modelData)
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
                            Action { Layout.fillWidth: true; leftAlign: true; iconText: "󰆏"; text: root.t("Copy SSH endpoint"); onClicked: root.copyEndpoint(toolsPage.device) }
                            Action { Layout.fillWidth: true; leftAlign: true; iconText: "󰌆"; text: root.t("Verify host key"); onClicked: root.inspectHostKey(root.actionId) }
                            Action {
                                visible: toolsPage.device !== null && root.matchingSftpState(toolsPage.device) === "mounted"
                                Layout.fillWidth: true
                                leftAlign: true
                                iconText: "󰅖"
                                text: root.t("Disconnect SFTP")
                                onClicked: root.call({op: "unmountSftp", id: root.actionId})
                            }
                            Ui.PanelSeparator { Layout.fillWidth: true }
                            Action { iconText: "󰆴"; text: root.t("Delete host"); foreground: Color.urgent; onClicked: root.requestDelete("deleteDevice", root.actionId) }
                        }
                        ColumnLayout {
                            visible: root.page === "device"
                            Layout.fillWidth: true
                            spacing: Style.space(12)
                            enabled: !root.busy
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: root.t("Name") }
                                Field { id: nameField; placeholderText: root.t("For example, home server"); maximumLength: 100; onTextChanged: if (State.DraftState.active) State.DraftState.name = text; onActiveFocusChanged: root.rememberDraftFocus("name", nameField) }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: root.t("Server address") }
                                Field {
                                    id: hostField
                                    enabled: !root.addressesHidden
                                    layer.enabled: root.addressesHidden && visible
                                    layer.effect: PrivacyBlur {}
                                    placeholderText: root.t("IPv4, unbracketed IPv6, or ASCII domain")
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
                                    Caption { text: root.t("User") }
                                    Field {
                                        id: loginField
                                        enabled: !root.addressesHidden
                                        placeholderText: root.t("SSH login")
                                        maximumLength: 64
                                        layer.enabled: root.addressesHidden && visible
                                        layer.effect: PrivacyBlur {}
                                        onTextChanged: if (State.DraftState.active) State.DraftState.login = text
                                        onActiveFocusChanged: root.rememberDraftFocus("login", loginField)
                                    }
                                }
                                ColumnLayout {
                                    Layout.preferredWidth: Style.space(88)
                                    Layout.maximumWidth: Style.space(88)
                                    spacing: Style.space(4)
                                    Caption { text: root.t("Port") }
                                    Field {
                                        id: portField
                                        enabled: !root.addressesHidden
                                        layer.enabled: root.addressesHidden && visible
                                        layer.effect: PrivacyBlur {}
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
                            Caption {
                                visible: root.addressesHidden
                                text: root.t("Turn off address hiding to edit these fields.")
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Action {
                                    text: root.busy && request.operation === "checkEndpoint" ? root.t("Checking…") : root.t("Check availability")
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
                                Caption { text: root.t("Group") }
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
                                Caption { text: root.t("Authentication") }
                                Choice {
                                    id: authChoice
                                    options: [{value: "agent", label: root.t("Key / SSH agent")}, {value: "password", label: root.t("Password")}]
                                    onChanged: function(v) { value = v; passwordField.text = ""; if (State.DraftState.active) { State.DraftState.auth = v; State.DraftState.password = "" } }
                                }
                            }
                            ColumnLayout {
                                visible: authChoice.value === "agent"
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: root.t("Key file · optional") }
                                Field { id: keyField; placeholderText: "/home/…/.ssh/id_ed25519"; maximumLength: 1024; onTextChanged: if (State.DraftState.active) State.DraftState.keyPath = text; onActiveFocusChanged: root.rememberDraftFocus("key", keyField) }
                                Caption { text: root.t("Empty uses default keys or SSH agent.") }
                            }
                            ColumnLayout {
                                visible: authChoice.value === "password"
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: root.t(root.editId ? "New password" : "Password") }
                                Field { id: passwordField; password: true; placeholderText: root.t(root.editId ? "Empty keeps the saved password" : "SSH password"); maximumLength: 4096; onTextChanged: if (State.DraftState.active) State.DraftState.password = text; onActiveFocusChanged: root.rememberDraftFocus("password", passwordField) }
                                Caption { text: root.t("Stored in Secret Service. Enter it again after changing address, port, or login.") }
                            }
                            Ui.PanelSeparator { Layout.fillWidth: true }
                            Action {
                                Layout.fillWidth: true
                                leftAlign: true
                                bordered: false
                                iconText: State.DraftState.aiExpanded ? "󰅀" : "󰅂"
                                text: "AI CLI" + (State.DraftState.agents.length ? " · " + root.t("selected") + ": " + State.DraftState.agents.length : " · " + root.t("none selected"))
                                tooltipText: State.DraftState.agents.map(root.agentLabel).join(", ")
                                onClicked: State.DraftState.aiExpanded = !State.DraftState.aiExpanded
                            }
                            ColumnLayout {
                                visible: State.DraftState.aiExpanded
                                Layout.fillWidth: true
                                spacing: Style.space(8)
                                Caption { text: root.t("Select CLI tools already installed on the server.") }
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
                                    Caption { text: root.t("AI CLI folder · optional") }
                                    Field {
                                        id: agentFolderField
                                        placeholderText: "/home/…/project"
                                        maximumLength: 1024
                                        onTextChanged: if (State.DraftState.active) State.DraftState.agentFolder = text
                                        onActiveFocusChanged: root.rememberDraftFocus("agentFolder", agentFolderField)
                                    }
                                    Caption { text: root.t("Empty uses the home directory. CLI tools appear in card actions.") }
                                }
                            }
                            Action {
                                Layout.fillWidth: true
                                leftAlign: true
                                bordered: false
                                iconText: State.DraftState.advancedExpanded ? "󰅀" : "󰅂"
                                text: root.t("Advanced · folder and note")
                                onClicked: State.DraftState.advancedExpanded = !State.DraftState.advancedExpanded
                            }
                            ColumnLayout {
                                visible: State.DraftState.advancedExpanded
                                Layout.fillWidth: true
                                spacing: Style.space(8)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(4)
                                    Caption { text: root.t("Files / VS Code folder · optional") }
                                    Field { id: folderField; placeholderText: "/home/…/project"; maximumLength: 1024; onTextChanged: if (State.DraftState.active) State.DraftState.remoteFolder = text; onActiveFocusChanged: root.rememberDraftFocus("folder", folderField) }
                                    Caption { text: root.t("Folder for SFTP and VS Code, separate from the AI CLI folder.") }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(4)
                                    Caption { text: root.t("Note · not for secrets") }
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
                            Caption {
                                text: "known_hosts: " + root.hostKeyEndpoint
                                layer.enabled: root.addressesHidden && visible
                                layer.effect: PrivacyBlur {}
                            }
                            Label { text: root.hostKeyRows }
                            Label {
                                text: root.t("IMPORTANT: ssh-keyscan does not prove server identity. Verify EVERY SHA256 fingerprint with the administrator or server console over an independent trusted channel. Do not trust a key merely because it appears here.")
                                color: Color.urgent
                            }
                            Label {
                                text: root.hostKeyMessage
                                layer.enabled: root.addressesHidden && visible
                                layer.effect: PrivacyBlur {}
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: Style.space(8)
                                Action {
                                    id: trustHostKeyButton
                                    text: root.t("Trust after verification")
                                    enabled: root.hostKeyState === "new" && root.hostKeyToken !== "" && !root.addressesHidden
                                    onClicked: root.call({op: "trustHostKey", id: root.hostKeyDeviceId, keys: root.hostKeyKeys, token: root.hostKeyToken})
                                }
                                Action { id: cancelHostKeyButton; text: root.t("Cancel"); onClicked: root.showList() }
                            }
                            Caption {
                                visible: root.addressesHidden
                                text: root.t("Show addresses before trusting a host key.")
                            }
                            Caption { visible: root.hostKeyState !== "new"; text: root.t("The plugin does not replace or remove existing known_hosts entries. Resolve key changes separately with a trusted administrator.") }
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
                                    readonly property string deleteReason: deviceCount > 0 ? root.t("Move hosts to another group before deleting it.")
                                        : root.profiles.groups.length <= 1 ? root.t("The last group cannot be deleted.") : ""
                                    Layout.fillWidth: true
                                    spacing: Style.space(6)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: groupEdit.modelData.name; font.bold: true; elide: Text.ElideRight; wrapMode: Text.NoWrap; Layout.minimumWidth: 0 }
                                        Caption { Layout.fillWidth: false; text: root.t("Hosts") + ": " + groupEdit.deviceCount }
                                    }
                                    RowLayout {
                                        Action { text: root.t("Edit"); iconText: "󰏫"; onClicked: root.editGroup(groupEdit.modelData) }
                                        Action {
                                            text: root.t("Delete")
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
                            Caption { text: root.t("Group name") }
                            Field { id: groupName; placeholderText: root.t("For example, work"); maximumLength: 100 }
                        }
                        ColumnLayout {
                            visible: root.page === "transfer"
                            Layout.fillWidth: true
                            spacing: Style.space(12)
                            enabled: !root.busy
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: root.t("JSON file · absolute path") }
                                Field { id: transferPath; placeholderText: "/home/…/devices.json"; onTextChanged: root.importToken = "" }
                            }
                            Label { text: root.t("Export"); font.bold: true }
                            Action { id: notesToggle; property bool checked: false; selected: checked; text: (checked ? "☑ " : "☐ ") + root.t("Include notes"); onClicked: checked = !checked }
                            Action { id: pathsToggle; property bool checked: false; selected: checked; text: (checked ? "☑ " : "☐ ") + root.t("Include paths"); onClicked: checked = !checked }
                            Action { text: root.t("Export to new file"); onClicked: root.call({op: "export", path: transferPath.text, notes: notesToggle.checked, paths: pathsToggle.checked}) }
                            Ui.PanelSeparator { Layout.fillWidth: true }
                            Label { text: root.t("Import"); font.bold: true }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: root.t("When address, port, and login match") }
                                Choice {
                                    id: duplicateChoice
                                    value: "skip"
                                    options: [{value: "skip", label: root.t("Skip")}, {value: "replace", label: root.t("Update data, keep local authentication")}]
                                    onChanged: function(v) { value = v; root.importToken = "" }
                                }
                            }
                            Action { text: root.t("Preview import"); onClicked: { root.importToken = ""; root.call({op: "previewImport", path: transferPath.text, policy: duplicateChoice.value}) } }
                            Label {
                                visible: root.importToken !== ""
                                text: root.importSummary + "\n" + root.t("Final list:\n")
                            }
                            Label {
                                visible: root.importToken !== ""
                                text: root.previewRows
                                layer.enabled: root.addressesHidden && visible
                                layer.effect: PrivacyBlur {}
                            }
                            Caption { text: root.t("Passwords and key contents are not transferred. New hosts use a key / SSH agent. Verify addresses and paths in the preview.") }
                            Action { text: root.t("Apply import"); enabled: root.importToken !== ""; onClicked: root.call({op: "import", path: transferPath.text, policy: duplicateChoice.value, token: root.importToken}) }
                        }
                        ColumnLayout {
                            visible: root.page === "settings"
                            Layout.fillWidth: true
                            spacing: Style.space(12)
                            enabled: !root.busy && root.settingsLoaded
                            Label { text: root.t("General"); font.bold: true }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: root.t("Language") }
                                Choice {
                                    id: languageChoice
                                    options: [{value: "en", label: "English"}, {value: "ru", label: "Русский"}]
                                    onChanged: function(v) { value = v }
                                }
                            }
                            Ui.PanelSeparator { Layout.fillWidth: true }
                            Label { text: root.t("Connection"); font.bold: true }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(4)
                                Caption { text: root.t("Default terminal") }
                                Choice {
                                    id: terminalChoice
                                    options: root.terminals.map(function(t) {
                                        return {value: t.value, label: t.label + (t.available ? "" : " · " + root.t("not installed"))}
                                    })
                                    onChanged: function(v) { value = v }
                                }
                            }
                            Caption { text: root.t("Used by SSH and every AI CLI on all hosts. VS Code and SFTP open separately.") }
                            Caption {
                                visible: root.settingsLoaded && !root.terminalAvailable
                                text: root.t("This terminal was not found in PATH. Install it yourself or select an available terminal.")
                            }
                            Ui.PanelSeparator { Layout.fillWidth: true }
                            Caption { text: root.t("Saved changes apply to new connections. Existing terminal windows are unaffected.") }
                            Caption { text: root.t("Settings are stored separately from hosts and are excluded from import / export.") }
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
                        Action { text: root.t("Cancel"); bordered: false; onClicked: root.navigateBack() }
                        Item { Layout.fillWidth: true }
                        Action {
                            text: root.busy && ["saveDevice", "saveGroup", "saveSettings"].indexOf(request.operation) >= 0 ? root.t("Saving…") : root.t("Save")
                            enabled: root.page !== "settings" || (root.settingsLoaded && root.terminalAvailable
                                     && (terminalChoice.value !== root.globalConfig.defaultTerminal
                                         || languageChoice.value !== root.globalConfig.language))
                            foreground: Color.accent
                            onClicked: {
                                if (root.page === "device") root.saveDevice()
                                else if (root.page === "settings") root.call({op: "saveSettings", settings: {version: 1, defaultTerminal: terminalChoice.value, language: languageChoice.value}})
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
                message: root.confirmKind === "discardDraft" ? root.t("Leave without saving and discard the draft?")
                    : root.confirmKind === "deleteDevice" ? root.t("Delete this host permanently?") : root.t("Delete this group permanently?")
                cancelText: root.t(root.confirmKind === "discardDraft" ? "Continue" : "Cancel")
                confirmText: root.t(root.confirmKind === "discardDraft" ? "Discard" : "Delete")
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
    component PrivacyBlur: MultiEffect {
        blurEnabled: true
        blur: 1.0
        blurMax: 32
        autoPaddingEnabled: true
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
    component CopyAddress: Ui.Button {
        id: copyAddress
        property string addressText: ""
        text: ""
        fontSize: Style.font.caption
        leftAlign: true
        bordered: false
        rightPadding: Style.space(28)
        implicitWidth: addressMetrics.advanceWidth + horizontalPadding * 2 + Style.space(28)
        implicitHeight: addressLabel.implicitHeight + verticalPadding * 2 + _reservedBorderTop + _reservedBorderBottom
        Layout.fillWidth: false
        Layout.minimumWidth: 0
        tooltipText: root.t("Copy SSH endpoint")
        foreground: root.secondaryText

        Text {
            id: addressLabel
            anchors.left: parent.left
            anchors.leftMargin: copyAddress._reservedContentLeftInset
            anchors.right: parent.right
            anchors.rightMargin: copyAddress._reservedBorderRight + copyAddress.rightPadding
            anchors.verticalCenter: parent.verticalCenter
            text: copyAddress.addressText
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            font.family: copyAddress.fontFamily
            font.pixelSize: copyAddress.fontSize
            color: copyAddress.foreground
            layer.enabled: root.addressesHidden && visible
            layer.effect: PrivacyBlur {}
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰆏"
            visible: copyAddress.hot
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.space(14)
        }
        TextMetrics {
            id: addressMetrics
            text: copyAddress.addressText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }
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
