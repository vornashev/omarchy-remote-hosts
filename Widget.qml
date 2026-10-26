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
    property var scripts: ({})
    property string scriptHostId: ""
    property string scriptId: ""
    property string scriptFilePath: ""
    property string scriptSavedPath: ""
    property bool scriptFromFile: false
    property bool scriptContentLoaded: true
    property var scriptBrowser: ({folder: "", parent: "", files: []})
    property string selectedScriptFile: ""
    property bool scriptsOnly: true
    property string scriptReturnPage: "list"
    property var globalConfig: ({version: 1, defaultTerminal: "ghostty", language: "en", layout: "auto", watchMinutes: 0})
    property var terminals: []
    property bool settingsLoaded: false
    property string languageDraft: "en"
    property string layoutDraft: "auto"
    property string terminalDraft: "ghostty"
    property string watchDraft: "0"
    // Language and layout switch the whole panel only after Save.
    readonly property string language: globalConfig.language || "en"
    readonly property string layoutSetting: globalConfig.layout || "auto"
    readonly property int watchMinutes: globalConfig.watchMinutes || 0
    readonly property bool wide: layoutSetting === "wide"
        || (layoutSetting === "auto" && panel.availableCardWidth - panel.padding * 2 >= Style.space(760))
    readonly property bool settingsDirty: settingsLoaded && (terminalDraft !== globalConfig.defaultTerminal
        || languageDraft !== globalConfig.language || layoutDraft !== globalConfig.layout
        || watchDraft !== String(watchMinutes))
    readonly property bool terminalAvailable: terminals.some(function(t) { return t.value === terminalDraft && t.available })
    readonly property string terminalName: {
        for (var i = 0; i < terminals.length; i++)
            if (terminals[i].value === globalConfig.defaultTerminal) return terminals[i].label
        return globalConfig.defaultTerminal
    }
    readonly property bool addressesHidden: State.PrivacyState.addressesHidden
    readonly property var agentLabels: ({
        claude: "Claude", codex: "Codex", pi: "Pi", opencode: "OpenCode", gemini: "Gemini",
        aider: "Aider", goose: "Goose", amp: "Amp", copilot: "Copilot", qwen: "Qwen"
    })
    readonly property var agentCommands: ({goose: "goose session"})
    property double clockMs: Date.now()
    property bool loaded: false
    property bool refreshAfterLoad: false
    property string page: "list"

    // View state. Selection, search, tab and collapse state are never
    // persisted and cost no helper round-trip.
    property string selectedKey: ""
    property string query: ""
    property string groupFilter: ""
    property var collapsedGroups: ({})
    property string highlightGroupId: ""
    property string dockMode: ""
    property int dockCursor: 0
    property bool detailZone: false
    property int detailCursor: 0
    property string hostDeleteId: ""
    property string menuHostId: ""
    property bool menuFull: true
    property real menuX: 0
    property real menuY: 0
    property int menuIndex: 0
    property var toasts: []
    property int toastSeq: 0
    property int progressToast: 0

    property string editId: ""
    property var draftStatus: null
    property string confirmKind: ""
    property string confirmId: ""

    property string groupEditId: ""
    property string groupEditName: ""
    property bool groupEditInvalid: false
    property string groupDeleteId: ""

    property string transferTab: "import"
    property string importPolicy: "skip"
    property string importToken: ""
    property var importSummary: null
    property var importRows: []
    property bool exportNotes: true
    property bool exportPaths: false
    property var exportPreview: null
    property string exportRequested: ""
    property string exportError: ""
    property string exportDone: ""

    property string hostKeyDeviceId: ""
    property string hostKeyEndpoint: ""
    property string hostKeyToken: ""
    property var hostKeyKeys: []
    property string hostKeyState: ""
    property string hostKeyMessage: ""
    property double hostKeyScannedAt: 0
    property bool hostKeyCompared: false
    property string hostKeyCopied: ""
    property var pendingHostKeys: null

    property string pendingLaunchId: ""
    property string pendingLaunchClient: ""
    property string pendingLaunchAgent: ""
    property string pendingLaunchScript: ""
    property string launchHostId: ""
    property string launchTarget: ""
    // A launch or unmount started from the bar menu reopens the panel when it
    // needs attention: a failure or a host key that is not verified yet.
    property bool barAction: false
    property var unmountQueue: []

    // Bar surface. The icon shows one signal at a time; the tooltip and the
    // right-click menu are built from the same list/check/mount state.
    property bool quickMenuOpen: false
    property int quickIndex: -1
    property int tooltipPage: -1
    property real wheelDelta: 0
    property bool hoverShown: false
    readonly property var pinnedDevices: profiles.devices.filter(function(d) { return d.pinned })
    readonly property var pinnedDown: pinnedDevices.filter(function(d) { return root.unreachable(d) })
    readonly property var mountedDevices: profiles.devices.filter(function(d) { return root.matchingSftpState(d) === "mounted" })
    readonly property string barMode: pinnedDown.length > 0 ? "alert" : checking ? "checking"
        : mountedDevices.length > 0 ? "mounted" : addressesHidden ? "private" : "idle"

    property var checkQueue: []
    property var checkingIds: ({})
    property int checkTotal: 0
    property int checkDone: 0
    readonly property bool checking: checkQueue.length > 0 || Object.keys(checkingIds).length > 0
    readonly property var checkWorkers: [checkWorker0, checkWorker1, checkWorker2, checkWorker3]

    readonly property string helperPath: decodeURIComponent(Qt.resolvedUrl("helper.py").toString().replace(/^file:\/\//, ""))
    readonly property bool busy: request.running
    // Panel chrome comes from the theme's [popups] surface. Supporting text
    // uses the kit's own dim convention (`Qt.darker(foreground, 1.4)`).
    readonly property color popupSurface: Color.popups.background
    readonly property color secondaryText: Qt.darker(Color.foreground, 1.4)
    readonly property color faintText: Qt.darker(Color.foreground, 2.0)
    readonly property color tint: Style.normalFillFor(Color.foreground, Color.accent)
    readonly property color urgentTint: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.12)
    readonly property color rule: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)

    readonly property var rows: computeRows()
    readonly property string currentKey: {
        for (var i = 0; i < rows.length; i++) if (rows[i].key === selectedKey) return selectedKey
        var id = selectedKey.split(":").pop()
        for (var j = 0; j < rows.length; j++) if (rows[j].id === id) return rows[j].key
        return rows.length ? rows[0].key : ""
    }
    readonly property var current: deviceById(currentKey.split(":").pop())
    readonly property string currentId: current ? current.id : ""

    function t(text) {
        return State.I18n.t(language, text)
    }

    onPageChanged: {
        detailZone = false
        dockMode = ""
        hostDeleteId = ""
        menuHostId = ""
        Qt.callLater(function() {
            if (root.page === "list") root.focusSearch()
            else if (root.page !== "device" && root.page !== "hostkey") pageFrame.forceActiveFocus()
        })
    }
    onCurrentIdChanged: {
        dockMode = ""
        hostDeleteId = ""
        detailCursor = 0
        if (current && statusAgeSeconds(current) > 60) refreshDevice(current)
    }
    onAddressesHiddenChanged: {
        if (!addressesHidden) return
        var endpointFocused = hostField.activeFocus || loginField.activeFocus || portField.activeFocus
        hostField.deselect()
        loginField.deselect()
        portField.deselect()
        if (endpointFocused) pageFrame.forceActiveFocus()
    }

    // --- helpers --------------------------------------------------------------

    function ensureVisible(item) {
        if (!item || !item.visible) return
        var view = item.parent
        while (view && !(view.flickableDirection !== undefined && view.contentItem)) view = view.parent
        if (!view) return
        Qt.callLater(function() {
            if (!item || !item.visible) return
            var y = item.mapToItem(view.contentItem, 0, 0).y
            var margin = Style.space(8)
            if (y < view.contentY + margin) view.contentY = Math.max(0, y - margin)
            else if (y + item.height > view.contentY + view.height - margin)
                view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, y + item.height - view.height + margin))
        })
    }
    function deviceById(id) {
        for (var i = 0; i < profiles.devices.length; i++)
            if (profiles.devices[i].id === id) return profiles.devices[i]
        return null
    }
    function groupById(id) {
        for (var i = 0; i < profiles.groups.length; i++)
            if (profiles.groups[i].id === id) return profiles.groups[i]
        return null
    }
    function groupName(id) {
        var g = groupById(id)
        return g ? g.name : ""
    }
    function groupDevices(id) {
        return profiles.devices.filter(function(d) { return d.group === id })
    }
    function endpointText(d) {
        return d ? d.login + "@" + d.host : ""
    }
    function endpointPort(d) {
        return d ? d.login + "@" + d.host + ":" + d.port : ""
    }
    function agentLabel(agent) {
        return agentLabels[agent] || agent
    }
    function agentIcon(agent) {
        return agent === "pi" ? "π" : "󰚩"
    }
    function agentCommand(agent) {
        return agentCommands[agent] || agent
    }
    function hostScripts(d) {
        return d ? (scripts[d.id] || []) : []
    }
    function byName(a, b) {
        return a.name.localeCompare(b.name, undefined, {sensitivity: "base"})
    }
    function searchScore(d, q) {
        var name = d.name.toLowerCase()
        if (name.indexOf(q) === 0) return 0
        if (name.indexOf(q) > 0) return 1
        if ((d.login + "@" + d.host).toLowerCase().indexOf(q) >= 0) return 2
        if (groupName(d.group).toLowerCase().indexOf(q) >= 0) return 3
        if (d.note.toLowerCase().indexOf(q) >= 0) return 4
        return -1
    }
    function computeRows() {
        var devices = profiles.devices.slice()
        var result = []
        function add(section, list) {
            for (var i = 0; i < list.length; i++)
                result.push({key: section + ":" + list[i].id, section: section, id: list[i].id})
        }
        var q = query.trim().toLowerCase()
        if (q !== "") {
            var scored = devices.map(function(d) { return {d: d, s: root.searchScore(d, q)} })
                .filter(function(x) { return x.s >= 0 })
            scored.sort(function(a, b) { return a.s - b.s || root.byName(a.d, b.d) })
            var found = scored.map(function(x) { return x.d })
            add("best", found.slice(0, 1))
            add("match", found.slice(1))
            return result
        }
        if (!wide && groupFilter !== "") devices = devices.filter(function(d) { return d.group === root.groupFilter })
        devices.sort(byName)
        add("pinned", devices.filter(function(d) { return d.pinned }))
        if (wide) {
            for (var g = 0; g < profiles.groups.length; g++) {
                var id = profiles.groups[g].id
                if (!collapsedGroups[id]) add(id, devices.filter(function(d) { return d.group === id }))
            }
        } else {
            add("all", devices)
        }
        return result
    }
    function sections() {
        var q = query.trim() !== ""
        var list = []
        function rowsOf(key) { return root.rows.filter(function(r) { return r.section === key }) }
        if (q) {
            list.push({key: "best", title: t("Best match"), count: -1, rows: rowsOf("best")})
            list.push({key: "match", title: t("Other matches"), count: -1, rows: rowsOf("match")})
        } else {
            list.push({key: "pinned", title: t("Pinned"), count: -1, rows: rowsOf("pinned")})
            if (wide) {
                for (var g = 0; g < profiles.groups.length; g++) {
                    var group = profiles.groups[g]
                    var count = groupDevices(group.id).length
                    if (count > 0) list.push({key: group.id, title: group.name, count: count, rows: rowsOf(group.id), group: true})
                }
            } else {
                list.push({key: "all", title: t("All hosts · A–Z"), count: -1, rows: rowsOf("all")})
            }
        }
        return list.filter(function(s) { return s.rows.length > 0 || s.group })
    }
    // Escaped StyledText with the search match tinted; names and addresses
    // never reach the renderer as markup.
    function highlight(text, color) {
        function escape(v) { return v.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
        var q = query.trim()
        var at = q === "" ? -1 : text.toLowerCase().indexOf(q.toLowerCase())
        if (at < 0) return escape(text)
        return escape(text.slice(0, at)) + "<font color=\"" + color + "\">" + escape(text.slice(at, at + q.length))
               + "</font>" + escape(text.slice(at + q.length))
    }
    function matchCount() {
        return rows.length
    }
    function select(key) {
        selectedKey = key
        hostDeleteId = ""
    }
    function moveSelection(step) {
        if (!rows.length) return
        var index = 0
        for (var i = 0; i < rows.length; i++) if (rows[i].key === currentKey) index = i
        select(rows[Math.max(0, Math.min(rows.length - 1, index + step))].key)
    }
    function nextTab(step) {
        var tabs = [""].concat(profiles.groups.filter(function(g) { return root.groupDevices(g.id).length > 0 })
                                             .map(function(g) { return g.id }))
        var index = Math.max(0, tabs.indexOf(groupFilter))
        groupFilter = tabs[(index + step + tabs.length) % tabs.length]
    }
    function toggleGroupCollapsed(id) {
        var next = Object.assign({}, collapsedGroups)
        if (next[id]) delete next[id]
        else next[id] = true
        collapsedGroups = next
    }
    function focusSearch() {
        if (opened && page === "list" && searchBox.visible) searchBox.field.forceActiveFocus()
    }
    function typeIntoSearch(text) {
        query = query + text
        searchBox.field.forceActiveFocus()
        searchBox.field.cursorPosition = searchBox.field.text.length
    }

    // --- toasts ---------------------------------------------------------------

    function toast(kind, title, detail, action, hostId) {
        toastSeq += 1
        var lifetime = kind === "progress" ? 70000 : kind === "error" ? 9000 : 4000
        var item = {id: toastSeq, kind: kind, title: title, detail: detail || "", action: action || "",
                    hostId: hostId || "", expires: Date.now() + lifetime}
        toasts = toasts.filter(function(x) { return x.kind !== "progress" || x.id === root.progressToast }).concat([item]).slice(-4)
        return item.id
    }
    function dismissToast(id) {
        toasts = toasts.filter(function(x) { return x.id !== id })
    }
    function toastAction(item) {
        dismissToast(item.id)
        if (item.action === "verify") openPendingHostKeys(item.hostId)
    }
    function failure(text) {
        toast("error", text)
    }

    // --- helper requests ------------------------------------------------------

    function call(payload) {
        if (busy) return false
        payload.language = language
        request.operation = payload.op
        request.payload = JSON.stringify(payload)
        request.running = true
        requestGuard.restart()
        return true
    }
    function copyEndpoint(d) {
        if (!d) return
        var copied = endpointText(d) + (d.port === 22 ? "" : " -p " + d.port)
        Quickshell.execDetached(["wl-copy", copied])
        toast("info", t("SSH endpoint copied"), copied, "", d.id)
    }
    function statusAgeSeconds(d) {
        var s = matchingStatus(d)
        if (!s) return Infinity
        var checked = Date.parse(s.checkedAt)
        return isFinite(checked) ? Math.max(0, (Date.now() - checked) / 1000) : Infinity
    }
    function refresh() {
        if (!loaded) return
        enqueueChecks(profiles.devices.map(function(d) { return d.id }))
    }
    function refreshDevice(d) {
        if (loaded && d) enqueueChecks([d.id])
    }
    function enqueueChecks(ids) {
        if (!checking) {
            checkTotal = 0
            checkDone = 0
        }
        var queue = checkQueue.slice()
        var added = 0
        for (var i = 0; i < ids.length; i++) {
            if (queue.indexOf(ids[i]) < 0 && !checkingIds[ids[i]]) {
                queue.push(ids[i])
                added++
            }
        }
        checkTotal += added
        checkQueue = queue
        pumpChecks()
    }
    function pumpChecks() {
        for (var i = 0; i < checkWorkers.length && checkQueue.length > 0; i++) {
            var worker = checkWorkers[i]
            if (worker.running) continue
            var queue = checkQueue.slice()
            var id = queue.shift()
            checkQueue = queue
            var busyIds = Object.assign({}, checkingIds)
            busyIds[id] = true
            checkingIds = busyIds
            worker.deviceId = id
            worker.payload = JSON.stringify({op: "checkDevice", id: id, language: language})
            worker.guard.restart()
            worker.running = true
        }
    }
    function finishCheck(worker, reply) {
        worker.guard.stop()
        var busyIds = Object.assign({}, checkingIds)
        delete busyIds[worker.deviceId]
        checkingIds = busyIds
        checkDone += 1
        try {
            var result = JSON.parse(reply)
            if (!result || result.ok !== true || typeof result.statuses !== "object")
                throw new Error(result && typeof result.error === "string" ? result.error : t("invalid helper response"))
            statuses = Object.assign({}, statuses, result.statuses)
        } catch (e) {
            // A host deleted while queued is not a failure worth a toast.
            if (deviceById(worker.deviceId))
                failure(t("Check failed: ") + (reply === "" ? t("helper did not respond") : String(e.message)))
        }
        Qt.callLater(pumpChecks)
    }
    function openSettings() {
        if (busy) return
        page = "settings"
        settingsLoaded = false
        call({op: "getSettings"})
    }
    function saveSettings() {
        if (!settingsDirty || !terminalAvailable) return
        call({op: "saveSettings", settings: {version: 1, defaultTerminal: terminalDraft, language: languageDraft, layout: layoutDraft,
                                             watchMinutes: Number(watchDraft)}})
    }
    function revertSettings() {
        terminalDraft = globalConfig.defaultTerminal
        languageDraft = globalConfig.language
        layoutDraft = globalConfig.layout
        watchDraft = String(watchMinutes)
    }
    function openTransfer(tab) {
        if (busy) return
        transferTab = tab || "import"
        importToken = ""
        exportError = ""
        exportDone = ""
        if (exportPathField.text === "") exportPathField.text = defaultExportPath()
        page = "transfer"
        if (transferTab === "export") Qt.callLater(requestExportPreview)
    }
    function defaultExportPath() {
        var home = Quickshell.env("HOME") || ""
        return home + "/hosts-" + Qt.formatDate(new Date(), "yyyy-MM-dd") + ".json"
    }
    function requestExportPreview() {
        var key = exportNotes + "/" + exportPaths
        if (call({op: "previewExport", notes: exportNotes, paths: exportPaths})) exportRequested = key
    }
    function previewImport() {
        importToken = ""
        call({op: "previewImport", path: importPathField.text, policy: importPolicy})
    }
    function clearPendingLaunch() {
        pendingLaunchId = ""
        pendingLaunchClient = ""
        pendingLaunchAgent = ""
        pendingLaunchScript = ""
    }
    function beginLaunch(id, target, title, detail) {
        pendingLaunchId = id
        launchHostId = id
        launchTarget = target
        progressToast = 0
        progressToast = toast("progress", title, detail, "", id)
    }
    function endLaunch() {
        if (progressToast) dismissToast(progressToast)
        progressToast = 0
        launchHostId = ""
        launchTarget = ""
    }
    function launchDevice(id, client) {
        var d = deviceById(id)
        if (busy || !d) return
        if (client === "vscode" && d.auth !== "agent") return
        clearPendingLaunch()
        pendingLaunchClient = client || ""
        var title = client === "sftp" ? t("Mounting SFTP…") : client === "vscode" ? t("Opening VS Code…")
                                       : t("Opening SSH in %1…").arg(terminalName)
        beginLaunch(id, client || "ssh", title, d.name + " · " + endpointPort(d))
        var payload = {op: "launch", id: id}
        if (client) payload.client = client
        call(payload)
    }
    function launchAgent(id, agent) {
        var d = deviceById(id)
        if (busy || !d) return
        clearPendingLaunch()
        pendingLaunchAgent = agent
        beginLaunch(id, "agent:" + agent, t("Launching %1 in %2…").arg(agentLabel(agent)).arg(d.agentFolder || "~"),
                    d.name + " · " + terminalName)
        call({op: "launchAgent", id: id, agent: agent})
    }
    function launchScript(hostId, entry) {
        var d = deviceById(hostId)
        if (busy || !d) return
        clearPendingLaunch()
        pendingLaunchScript = entry.id
        beginLaunch(hostId, "script:" + entry.id, t("Running %1…").arg(entry.name), d.name + " · " + terminalName)
        call({op: "launchScript", id: hostId, scriptId: entry.id})
    }
    function retryPendingLaunch() {
        var id = pendingLaunchId, client = pendingLaunchClient, agent = pendingLaunchAgent, script = pendingLaunchScript
        clearPendingLaunch()
        if (id === "") return
        Qt.callLater(function() {
            if (script !== "") {
                var entry = root.hostScripts(root.deviceById(id)).filter(function(s) { return s.id === script })[0]
                if (entry) root.launchScript(id, entry)
            } else if (agent !== "") root.launchAgent(id, agent)
            else root.launchDevice(id, client)
        })
    }
    function inspectHostKey(id, keepPending) {
        if (busy || !deviceById(id)) return
        if (!keepPending) clearPendingLaunch()
        call({op: "scanHostKey", id: id})
    }
    function showHostKeys(keys) {
        hostKeyDeviceId = keys.deviceId
        hostKeyEndpoint = keys.endpoint
        hostKeyToken = keys.token
        hostKeyKeys = keys.keys
        hostKeyState = keys.state
        hostKeyMessage = keys.message
        hostKeyScannedAt = Date.now()
        hostKeyCompared = false
        hostKeyCopied = ""
        pendingHostKeys = null
        clockMs = Date.now()
        page = "hostkey"
    }
    function openPendingHostKeys(hostId) {
        if (pendingHostKeys && pendingHostKeys.deviceId === hostId) showHostKeys(pendingHostKeys)
        else inspectHostKey(hostId, true)
    }
    function fingerprintGroups(fingerprint) {
        var body = String(fingerprint).replace(/^SHA256:/, "")
        var groups = []
        for (var i = 0; i < body.length; i += 11) groups.push(body.substr(i, 11))
        return groups
    }
    function algorithmLabel(algorithm) {
        if (algorithm === "ssh-ed25519") return "ED25519"
        if (algorithm.indexOf("ecdsa") === 0) return "ECDSA " + algorithm.replace(/^ecdsa-sha2-nistp/, "P-")
        if (algorithm === "ssh-rsa") return "RSA"
        return algorithm.toUpperCase()
    }
    function copyFingerprint(key) {
        Quickshell.execDetached(["wl-copy", key.fingerprint])
        hostKeyCopied = key.fingerprint
        copiedTimer.restart()
    }
    function requestHostDelete(id) {
        if (busy || !deviceById(id)) return
        hostDeleteId = id
        dockMode = "delete"
        menuHostId = ""
        pageFrame.forceActiveFocus()
    }
    function confirmHostDelete() {
        var id = hostDeleteId
        hostDeleteId = ""
        dockMode = ""
        if (id !== "") call({op: "deleteDevice", id: id})
    }
    function deleteConsequence(d) {
        var count = hostScripts(d).length
        var parts = []
        if (count > 0) parts.push(count === 1 ? t("its script") : t("its %1 scripts").arg(count))
        if (d.auth === "password") parts.push(t("saved password"))
        if (d.saveKeyPassphrase) parts.push(t("saved key passphrase"))
        var lead = parts.length ? t("Also removes %1.").arg(parts.join(", ")) + " " : ""
        return lead + t("Nothing is changed on the server.")
    }
    function togglePin(d) {
        if (!d || busy) return
        call({op: "setPinned", id: d.id, pinned: !d.pinned})
    }
    function openMenu(d, x, y, full) {
        if (!d) return
        selectByDevice(d)
        menuHostId = d.id
        menuFull = full
        menuX = x
        menuY = y
        menuIndex = 0
        pageFrame.forceActiveFocus()
    }
    function selectByDevice(d) {
        for (var i = 0; i < rows.length; i++) if (rows[i].id === d.id) {
            if (rows[i].key !== currentKey && currentKey.split(":").pop() !== d.id) select(rows[i].key)
            return
        }
        selectedKey = "x:" + d.id
    }
    function menuItems() {
        var d = deviceById(menuHostId)
        if (!d) return []
        var mount = matchingSftpState(d)
        var items = []
        if (menuFull) {
            items.push({id: "ssh", icon: "󰆍", label: "SSH", key: "↵"})
            items.push({id: "files", icon: "󰉋", label: t("Files"), key: "F", enabled: mount !== "foreign"})
            items.push({id: "vscode", icon: "󰨞", label: "VS Code", key: "C", enabled: d.auth === "agent", separator: true})
        }
        items.push({id: "edit", icon: "󰏫", label: t("Edit host"), key: "E"})
        items.push({id: "verify", icon: "󰒃", label: t("Verify host key"), key: "K"})
        items.push({id: "copy", icon: "󰆏", label: t("Copy SSH endpoint"), key: "Y"})
        items.push({id: "pin", icon: d.pinned ? "󰤰" : "󰐃", label: d.pinned ? t("Unpin") : t("Pin to top"), key: "P", separator: !menuFull})
        if (!menuFull)
            items.push({id: "unmount", icon: "󰅖", label: t("Disconnect SFTP"), key: mount === "mounted" ? "" : t("not mounted"),
                        enabled: mount === "mounted", separator: true})
        items.push({id: "delete", icon: "󰆴", label: t("Delete host…"), key: "Del", danger: true})
        return items
    }
    function runMenuItem(item) {
        var d = deviceById(menuHostId)
        menuHostId = ""
        if (!d || item.enabled === false) return
        runAction(item.id, d)
    }
    function runAction(id, d) {
        if (!d) return
        if (id === "ssh") launchDevice(d.id)
        else if (id === "files") launchDevice(d.id, "sftp")
        else if (id === "vscode") launchDevice(d.id, "vscode")
        else if (id === "edit") editDevice(d)
        else if (id === "verify") inspectHostKey(d.id)
        else if (id === "copy") copyEndpoint(d)
        else if (id === "pin") togglePin(d)
        else if (id === "unmount") call({op: "unmountSftp", id: d.id})
        else if (id === "delete") requestHostDelete(d.id)
        else if (id === "retry") refreshDevice(d)
    }
    // Ordered keyboard targets of the wide detail pane.
    function detailTargets() {
        var d = current
        if (!d) return []
        var list = ["ssh", "files", "vscode"]
        var agents = d.agents || []
        for (var i = 0; i < agents.length; i++) list.push("agent:" + agents[i])
        var entries = hostScripts(d)
        for (var j = 0; j < entries.length; j++) list.push("script:" + entries[j].id)
        return list
    }
    function detailTargetIndex(target) {
        return detailTargets().indexOf(target)
    }
    function activateTarget(target) {
        var d = current
        if (!d || !target) return
        if (target.indexOf("agent:") === 0) launchAgent(d.id, target.slice(6))
        else if (target.indexOf("script:") === 0) {
            var entry = hostScripts(d).filter(function(s) { return "script:" + s.id === target })[0]
            if (entry) launchScript(d.id, entry)
        } else runAction(target, d)
    }
    function jumpDetail(prefix) {
        var targets = detailTargets()
        for (var i = 0; i < targets.length; i++) if (targets[i].indexOf(prefix) === 0) {
            detailZone = true
            detailCursor = i
            return
        }
    }
    function moveDetail(dx, dy) {
        var targets = detailTargets()
        if (!targets.length) return
        var index = Math.max(0, Math.min(targets.length - 1, detailCursor))
        var target = targets[index]
        var tile = index < 3
        if (tile && dx !== 0) index = Math.max(0, Math.min(2, index + dx))
        else if (tile && dy > 0) index = Math.min(targets.length - 1, 3)
        else if (!tile && dx !== 0) {
            var agents = targets.filter(function(x) { return x.indexOf("agent:") === 0 })
            var scriptsList = targets.filter(function(x) { return x.indexOf("script:") === 0 })
            var isAgent = target.indexOf("agent:") === 0
            var from = isAgent ? agents : scriptsList
            var to = isAgent ? scriptsList : agents
            var position = from.indexOf(target)
            if ((dx > 0) === isAgent && to.length) index = targets.indexOf(to[Math.min(position, to.length - 1)])
        } else if (!tile && dy !== 0) {
            var group = targets.filter(function(x) { return x.indexOf(target.split(":")[0] + ":") === 0 })
            var at = group.indexOf(target) + dy
            if (at < 0) index = 0
            else if (at < group.length) index = targets.indexOf(group[at])
        }
        detailCursor = index
    }
    function navigateBack() {
        if (busy) return
        if (page === "device") requestConfirm("discardDraft", "")
        else if (page === "scriptFiles") page = "scriptEditor"
        else if (page === "scriptEditor") page = scriptReturnPage
        else showList()
    }
    function requestConfirm(kind, id) {
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
        groupEditId = ""
        groupDeleteId = ""
        hostKeyToken = ""
        hostKeyKeys = []
        hostKeyState = ""
    }

    // --- scripts --------------------------------------------------------------

    function editScript(hostId, entry) {
        if (busy) return
        scriptReturnPage = page === "device" ? "device" : "list"
        scriptHostId = hostId
        scriptId = entry ? entry.id : ""
        scriptFilePath = ""
        scriptSavedPath = entry ? (entry.sourcePath || "") : ""
        scriptFromFile = scriptSavedPath !== ""
        selectedScriptFile = ""
        scriptNameField.text = entry ? entry.name : ""
        scriptContentField.text = ""
        scriptContentLoaded = !entry
        page = "scriptEditor"
        if (entry) loadScriptPreview({id: hostId, scriptId: entry.id}, "saved")
    }
    function loadScriptPreview(selector, kind) {
        if (scriptPreview.running) return
        scriptContentLoaded = false
        scriptPreview.kind = kind
        scriptPreview.path = kind === "file" ? selector.path : ""
        scriptPreview.payload = JSON.stringify(selector)
        scriptPreview.running = true
    }
    function saveScript() {
        if (!scriptContentLoaded) return
        var payload = {op: "saveScript", id: scriptHostId, scriptId: scriptId,
                       name: scriptNameField.text.trim()}
        if (scriptFilePath !== "") payload.path = scriptFilePath
        else if (scriptSavedPath === "" && scriptContentField.text.trim() !== "") payload.body = scriptContentField.text
        else if (scriptId === "") return
        call(payload)
    }
    function openScriptFile() {
        if (selectedScriptFile === "" || scriptPreview.running) return
        scriptContentField.text = ""
        scriptFilePath = ""
        scriptSavedPath = ""
        scriptFromFile = true
        page = "scriptEditor"
        loadScriptPreview({path: selectedScriptFile}, "file")
    }

    // --- host form ------------------------------------------------------------

    function discardDeviceDraft() {
        State.DraftState.clear()
        passwordField.text = ""
        passphraseField.text = ""
        draftStatus = null
        showList()
    }
    function focusItem(key) {
        if (addressesHidden && (key === "host" || key === "login" || key === "port")) return pageFrame
        if (key === "host") return hostField
        if (key === "port") return portField
        if (key === "login") return loginField
        if (key === "key") return keyField
        if (key === "passphrase") return passphraseField
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
        keyField.text = State.DraftState.keyPath
        passphraseField.text = State.DraftState.passphrase
        agentFolderField.text = State.DraftState.agentFolder
        folderField.text = State.DraftState.remoteFolder
        passwordField.text = State.DraftState.password
    }
    function editDevice(d, name) {
        if (busy) return
        State.DraftState.editId = d ? d.id : ""
        State.DraftState.name = d ? d.name : (name || "")
        State.DraftState.host = d ? d.host : ""
        State.DraftState.port = d ? String(d.port) : "22"
        State.DraftState.login = d ? d.login : ""
        State.DraftState.group = d ? d.group : (groupFilter !== "" && groupById(groupFilter) ? groupFilter
                                                 : profiles.groups.length ? profiles.groups[0].id : "")
        State.DraftState.note = d ? d.note : ""
        State.DraftState.auth = d ? d.auth : "agent"
        State.DraftState.keyPath = d ? d.keyPath : ""
        State.DraftState.saveKeyPassphrase = d ? (d.saveKeyPassphrase || false) : false
        State.DraftState.client = d ? d.client : "ghostty"
        State.DraftState.agents = d && d.agents ? d.agents.slice() : []
        State.DraftState.agentFolder = d ? (d.agentFolder || "") : ""
        State.DraftState.remoteFolder = d ? d.remoteFolder : ""
        State.DraftState.pinned = d ? (d.pinned || false) : false
        State.DraftState.password = ""
        State.DraftState.passphrase = ""
        State.DraftState.focusKey = d ? "name" : (name ? "host" : "name")
        draftStatus = null
        State.DraftState.active = true
        loadDraft()
        page = "device"
        restoreDraftFocus()
        scheduleDraftCheck()
    }
    function setAuth(v) {
        passwordField.text = ""
        passphraseField.text = ""
        State.DraftState.auth = v
        State.DraftState.password = ""
        State.DraftState.passphrase = ""
        if (v !== "agent") State.DraftState.saveKeyPassphrase = false
    }
    function toggleDraftAgent(agent) {
        var list = State.DraftState.agents.slice()
        var index = list.indexOf(agent)
        if (index >= 0) list.splice(index, 1)
        else list.push(agent)
        State.DraftState.agents = list
    }
    readonly property bool draftPortValid: /^[0-9]{1,5}$/.test(portField.text) && Number(portField.text) >= 1
                                           && Number(portField.text) <= 65535
    function scheduleDraftCheck() {
        draftStatus = null
        if (State.DraftState.active && hostField.text.trim() !== "" && draftPortValid) draftCheckTimer.restart()
        else draftCheckTimer.stop()
    }
    function checkDraftEndpoint() {
        if (draftChecker.running || hostField.text.trim() === "" || !draftPortValid) return
        draftChecker.host = hostField.text.trim()
        draftChecker.port = Number(portField.text)
        draftChecker.payload = JSON.stringify({op: "checkEndpoint", host: draftChecker.host, port: draftChecker.port, language: language})
        draftChecker.running = true
    }
    function draftStatusInfo() {
        if (draftChecker.running || draftCheckTimer.running) return {kind: "pending", label: t("Checking ping and SSH port…")}
        if (!draftStatus) return {kind: "unknown", label: t("Enter an address to check ping and SSH port")}
        if (draftStatus.error) return {kind: "error", label: draftStatus.error}
        var ping = draftStatus.ms !== null ? Math.round(draftStatus.ms) + " ms" : t("no response")
        if (draftStatus.ssh === "open") return {kind: "online", label: t("Reachable · SSH port open · ping %1").arg(ping)}
        if (draftStatus.ping === "ok") return {kind: "degraded", label: t("Ping %1 · SSH port closed").arg(ping)}
        if (draftStatus.ssh === "dns-error") return {kind: "offline", label: t("Could not resolve address")}
        return {kind: "offline", label: t("No ping reply · SSH port closed")}
    }
    function saveDevice() {
        if (busy || !State.DraftState.active) return
        if (!draftPortValid) {
            portField.forceActiveFocus()
            return
        }
        var auth = State.DraftState.auth
        var payload = {op: "saveDevice", device: {
            id: editId, name: nameField.text, host: hostField.text, port: Number(portField.text),
            login: loginField.text || "root", group: groupChoice.value, note: noteField.text,
            auth: auth, keyPath: auth === "agent" ? keyField.text : "",
            saveKeyPassphrase: auth === "agent" && State.DraftState.saveKeyPassphrase,
            client: State.DraftState.client || "ghostty", launchMode: "shell", customExecutable: "",
            agents: State.DraftState.agents, agentFolder: agentFolderField.text,
            remoteFolder: folderField.text, pinned: State.DraftState.pinned
        }, password: auth === "password" ? passwordField.text : ""}
        if (State.DraftState.saveKeyPassphrase) payload.passphrase = passphraseField.text
        call(payload)
        passwordField.text = ""
        passphraseField.text = ""
        State.DraftState.passphrase = ""
    }
    function finishDeviceSave(data) {
        var name = State.DraftState.name
        var editing = State.DraftState.editId
        State.DraftState.clear()
        passwordField.text = ""
        passphraseField.text = ""
        draftStatus = null
        showList()
        var saved = editing ? deviceById(editing) : data.devices.filter(function(d) { return d.name === name }).pop()
        if (saved) {
            query = ""
            selectByDevice(saved)
            refreshDevice(saved)
        }
    }

    // --- groups ---------------------------------------------------------------

    function focusNewGroup() {
        var field = wide ? newGroupWide : newGroupNarrow
        field.forceActiveFocus()
    }
    function commitGroupEdit() {
        var name = groupEditName.trim()
        if (name === "") {
            groupEditInvalid = true
            return
        }
        var id = groupEditId
        if (call({op: "saveGroup", id: id, name: name})) groupEditId = ""
    }
    function addGroup(field) {
        var name = field.text.trim()
        if (name === "") return
        if (call({op: "saveGroup", id: "", name: name})) field.text = ""
    }
    function groupDeleteReason(g) {
        var count = groupDevices(g.id).length
        if (count > 0) return t("%1 has %2 hosts. Move them to another group in Edit host before deleting.").arg(g.name).arg(count)
        if (profiles.groups.length <= 1) return t("The last group always stays.")
        return ""
    }

    // --- status ---------------------------------------------------------------

    function matchingStatus(d) {
        var s = d ? statuses[d.id] : null
        return s && JSON.stringify(s.endpoint) === JSON.stringify([d.host, d.port, d.login]) ? s : null
    }
    function statusKind(d) {
        if (!d) return "unknown"
        if (checkingIds[d.id] || checkQueue.indexOf(d.id) >= 0) return "pending"
        var s = matchingStatus(d)
        if (!s) return "unknown"
        if (s.ssh === "open") return "online"
        if (s.ping === "ok") return "degraded"
        if (s.ssh === "dns-error" || s.ssh === "error" || s.ping === "error") return "error"
        return "offline"
    }
    function unreachable(d) {
        var kind = statusKind(d)
        return kind === "offline" || kind === "error" || kind === "degraded"
    }
    // Reachability owns the dot; latency colour encodes speed with theme
    // roles only: neutral up to 50 ms, accent below 100 ms, urgent above.
    function latencyColor(ms) {
        return ms <= 50 ? secondaryText : (ms < 100 ? Color.accent : Color.urgent)
    }
    function statusDotColor(kind) {
        if (kind === "online") return Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.75)
        if (kind === "degraded") return Color.accent
        if (kind === "unknown" || kind === "pending") return Color.muted
        return Color.urgent
    }
    function rowStatus(d) {
        var kind = statusKind(d)
        var s = matchingStatus(d)
        if (kind === "pending") return {text: "", color: secondaryText, spinner: true}
        if (kind === "offline" || kind === "error") return {text: t("offline"), color: Color.urgent}
        if (s && s.ms !== null && s.ms !== undefined) return {text: Math.round(s.ms) + " ms", color: latencyColor(s.ms)}
        if (kind === "degraded") return {text: t("SSH closed"), color: Color.accent}
        if (kind === "online") return {text: t("open"), color: secondaryText}
        return {text: query.trim() !== "" ? t("not checked") : "—", color: faintText}
    }
    function ageText(seconds) {
        if (seconds < 60) return t("%1 s ago").arg(Math.floor(seconds))
        if (seconds < 3600) return t("%1 min ago").arg(Math.floor(seconds / 60))
        if (seconds < 86400) return t("%1 h ago").arg(Math.floor(seconds / 3600))
        return t("%1 d ago").arg(Math.floor(seconds / 86400))
    }
    function relativeAge(seconds) {
        return isFinite(seconds) ? t("checked %1").arg(ageText(seconds)) : t("not checked yet")
    }
    function checkAge(d) {
        var s = matchingStatus(d)
        var checked = s ? Date.parse(s.checkedAt) : NaN
        return relativeAge(isFinite(checked) ? Math.max(0, (clockMs - checked) / 1000) : Infinity)
    }
    function pingText(d) {
        var s = matchingStatus(d)
        if (statusKind(d) === "pending") return t("checking…")
        if (!s) return t("not checked")
        if (s.ms !== null && s.ms !== undefined) return Math.round(s.ms) + " ms"
        return s.ping === "timeout" ? t("timeout") : t("no response")
    }
    function portText(d) {
        var s = matchingStatus(d)
        if (statusKind(d) === "pending") return t("checking…")
        if (!s) return t("not checked")
        var labels = {open: t("open"), closed: t("closed"), timeout: t("timeout"), "dns-error": t("DNS error")}
        return labels[s.ssh] || t("error")
    }
    function statusDetails(d) {
        if (!matchingStatus(d)) return statusKind(d) === "pending" ? t("Checking ping and SSH port…") : t("Not checked yet")
        return "Ping: " + pingText(d) + " · SSH " + d.port + ": " + portText(d) + " · " + checkAge(d)
    }
    function unreachableTitle(d) {
        return statusKind(d) === "degraded" ? t("SSH port is closed") : t("Host is not reachable")
    }
    function unreachableDetail(d) {
        var s = matchingStatus(d)
        if (s && s.ssh === "dns-error") return t("The address does not resolve · %1. You can still try to connect.").arg(checkAge(d))
        var ping = s && s.ping === "ok" ? t("Ping replies") : t("No ping reply")
        return t("%1 and port %2 is %3 · %4. You can still try to connect.").arg(ping).arg(d.port).arg(portText(d)).arg(checkAge(d))
    }
    function matchingSftpState(d) {
        var state = d ? sftpStates[d.id] : null
        return state && JSON.stringify(state.endpoint) === JSON.stringify([d.host, d.port, d.login, d.remoteFolder])
               ? state.state : "unmounted"
    }
    function authText(d) {
        if (!d) return ""
        if (d.auth === "password") return t("password") + " · " + t("saved")
        var key = d.keyPath ? d.keyPath.split("/").pop() : t("agent")
        return t("key") + " · " + key
    }
    function sftpText(d) {
        var state = matchingSftpState(d)
        return state === "mounted" ? t("mounted") : state === "foreign" ? t("mount point busy") : t("not mounted")
    }

    // --- bar --------------------------------------------------------------------

    // Hover card content. Only host names appear, never user@host, so the
    // card is safe while the screen is shared.
    function hoverModel() {
        if (!loaded) return {pager: "", title: t("Remote Hosts"), subtitle: "", lines: [], footer: []}
        var d = tooltipPage >= 0 ? pinnedDevices[tooltipPage] : null
        if (d) {
            var facts = [t("group: %1").arg(groupName(d.group))]
            var agents = (d.agents || []).map(agentLabel).join(", ")
            if (agents !== "") facts.push("AI: " + agents)
            if (matchingSftpState(d) === "mounted") facts.push(t("SFTP mounted"))
            return {pager: "%1 / %2".arg(tooltipPage + 1).arg(pinnedDevices.length), title: d.name, subtitle: "",
                    lines: [{color: statusDotColor(statusKind(d)), text: t("ping %1 · SSH %2").arg(pingText(d)).arg(portText(d)), dim: true}],
                    footer: [facts.join(" · ")]}
        }
        var lines = []
        pinnedDown.slice(0, 3).forEach(function(x) { lines.push({color: Color.urgent, text: root.t("%1 — unreachable").arg(x.name)}) })
        if (pinnedDown.length > 3) lines.push({color: Color.urgent, text: t("+%1 more unreachable").arg(pinnedDown.length - 3), dim: true})
        mountedDevices.slice(0, 3).forEach(function(x) { lines.push({color: root.secondaryText, text: root.t("SFTP: %1 mounted").arg(x.name)}) })
        if (mountedDevices.length > 3) lines.push({color: secondaryText, text: t("+%1 more mounted").arg(mountedDevices.length - 3), dim: true})
        var newest = -Infinity
        profiles.devices.forEach(function(x) {
            var s = root.matchingStatus(x)
            var at = s ? Date.parse(s.checkedAt) : NaN
            if (isFinite(at) && at > newest) newest = at
        })
        var age = checking ? t("checking…") : relativeAge(isFinite(newest) ? Math.max(0, (clockMs - newest) / 1000) : Infinity)
        var footer = [age + " · " + t("middle-click to refresh")]
        if (pinnedDevices.length > 0) footer.push(t("scroll for pinned hosts"))
        return {pager: "", title: t("Remote Hosts"), lines: lines, footer: footer,
                subtitle: t("%1 hosts · %2 pinned").arg(profiles.devices.length).arg(pinnedDevices.length)}
    }
    function scrollTooltip(delta) {
        var n = pinnedDevices.length
        // Touchpads send small deltas; one page per wheel notch (120).
        wheelDelta += delta
        if (n === 0 || Math.abs(wheelDelta) < 120) return
        var step = wheelDelta < 0 ? 1 : -1
        wheelDelta = 0
        // Pages: summary (-1), then each pinned host; scrolling only browses.
        var page = tooltipPage + step
        tooltipPage = page >= n ? -1 : page < -1 ? n - 1 : page
        hoverShown = button.tooltipHovered
    }
    function toggleQuickMenu() {
        if (quickMenuOpen) { quickMenuOpen = false; return }
        if (opened) close()
        if (!loaded) call({op: "list"})
        quickIndex = -1
        quickMenuOpen = true
    }
    function quickMenuItems() {
        var items = []
        pinnedDevices.slice(0, 5).forEach(function(d) {
            var kind = root.statusKind(d)
            var mounted = root.matchingSftpState(d) === "mounted"
            var s = root.matchingStatus(d)
            var trailing = kind === "pending" ? root.t("checking…")
                         : root.unreachable(d) ? (kind === "degraded" ? root.t("SSH closed") : root.t("unreachable"))
                         : mounted ? "SFTP" : s && s.ms !== null && s.ms !== undefined ? Math.round(s.ms) + " ms" : ""
            items.push({id: "host", deviceId: d.id, label: d.name, key: trailing, kind: kind, mounted: mounted,
                        dim: root.unreachable(d), enabled: !root.busy})
        })
        if (items.length > 0) items[items.length - 1].separator = true
        items.push({id: "refresh", icon: "󰑐", label: t("Check all"), enabled: loaded})
        if (mountedDevices.length > 0)
            items.push({id: "unmount", icon: "󰅖", label: t("Disconnect SFTP (%1)").arg(mountedDevices.length), enabled: !busy})
        items.push({id: "privacy", icon: addressesHidden ? "󰈈" : "󰈉",
                    label: addressesHidden ? t("Show addresses") : t("Hide addresses")})
        items.push({id: "panel", icon: "󰍜", label: t("Open panel")})
        return items
    }
    function runQuickItem(item) {
        if (!item || item.enabled === false) return
        quickMenuOpen = false
        if (item.id === "host") {
            barAction = true
            launchDevice(item.deviceId)
            if (!busy) barAction = false
        } else if (item.id === "refresh") refresh()
        else if (item.id === "unmount") {
            unmountQueue = mountedDevices.map(function(d) { return d.id })
            barAction = true
            pumpUnmount()
        } else if (item.id === "privacy") State.PrivacyState.addressesHidden = !State.PrivacyState.addressesHidden
        else if (item.id === "panel") open()
    }
    function pumpUnmount() {
        if (unmountQueue.length === 0) { barAction = false; return }
        var queue = unmountQueue.slice()
        var id = queue.shift()
        unmountQueue = queue
        if (!deviceById(id)) Qt.callLater(pumpUnmount)
        else if (!call({op: "unmountSftp", id: id})) { unmountQueue = []; barAction = false }
    }
    function handleQuickKey(event) {
        var items = quickMenuItems()
        var key = event.key
        if (key === Qt.Key_Escape) { quickMenuOpen = false; return true }
        if (key === Qt.Key_Down || key === Qt.Key_Up) {
            var step = key === Qt.Key_Down ? 1 : -1
            for (var i = 1; i <= items.length; i++) {
                var next = ((quickIndex < 0 && step < 0 ? 0 : quickIndex) + step * i + items.length) % items.length
                if (items[next].enabled !== false) { quickIndex = next; break }
            }
            return true
        }
        if ((key === Qt.Key_Return || key === Qt.Key_Enter) && quickIndex >= 0) {
            runQuickItem(items[quickIndex])
            return true
        }
        return false
    }

    // --- keyboard -------------------------------------------------------------

    function handleKey(event) {
        var key = event.key
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        if (confirmKind !== "") return deleteConfirm.handleKey(event)
        if (menuHostId !== "") return handleMenuKey(event)
        if (page === "device") {
            if (ctrl && (key === Qt.Key_Return || key === Qt.Key_Enter)) { saveDevice(); return true }
            if (key === Qt.Key_Escape) { close(); return true }
            return false
        }
        if (page === "settings" && ctrl && (key === Qt.Key_Return || key === Qt.Key_Enter)) { saveSettings(); return true }
        if (page === "groups" && key === Qt.Key_N && !ctrl) { focusNewGroup(); return true }
        if (page === "groups" && groupDeleteId !== "") {
            if (key === Qt.Key_Escape) { groupDeleteId = ""; return true }
            if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                var gid = groupDeleteId
                groupDeleteId = ""
                call({op: "deleteGroup", id: gid})
                return true
            }
        }
        if (page === "hostkey" && key === Qt.Key_R && !ctrl) { inspectHostKey(hostKeyDeviceId, true); return true }
        if (page !== "list") {
            if (key === Qt.Key_Escape) { navigateBack(); return true }
            return false
        }
        return handleListKey(event)
    }
    function handleMenuKey(event) {
        var items = menuItems()
        var key = event.key
        if (key === Qt.Key_Escape) menuHostId = ""
        else if (key === Qt.Key_Down) menuIndex = (menuIndex + 1) % items.length
        else if (key === Qt.Key_Up) menuIndex = (menuIndex - 1 + items.length) % items.length
        else if (key === Qt.Key_Return || key === Qt.Key_Enter) runMenuItem(items[menuIndex])
        else {
            var letter = key === Qt.Key_Delete ? "Del" : event.text.toUpperCase()
            var match = items.filter(function(i) { return i.key === letter })[0]
            if (match) runMenuItem(match)
            else if (letter !== "") menuHostId = ""
        }
        return true
    }
    function handleListKey(event) {
        var key = event.key
        var text = event.text
        var d = current
        if ((event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) !== 0) return false
        if (hostDeleteId !== "") {
            if (key === Qt.Key_Escape) { hostDeleteId = ""; dockMode = "" }
            else if (key === Qt.Key_Return || key === Qt.Key_Enter) confirmHostDelete()
            return true
        }
        if (key === Qt.Key_Escape) {
            if (dockMode !== "") dockMode = ""
            else if (detailZone) detailZone = false
            else if (query !== "") { query = ""; focusSearch() }
            else close()
            return true
        }
        if (dockMode === "ai" || dockMode === "scripts") {
            var count = dockMode === "ai" ? (d ? d.agents.length : 0) : hostScripts(d).length
            if (key === Qt.Key_Down) { dockCursor = Math.min(count - 1, dockCursor + 1); return true }
            if (key === Qt.Key_Up) { dockCursor = Math.max(0, dockCursor - 1); return true }
            var digit = text >= "1" && text <= "9" ? Number(text) - 1 : -1
            if (key === Qt.Key_Return || key === Qt.Key_Enter || (digit >= 0 && digit < count)) {
                var index = digit >= 0 ? digit : dockCursor
                if (dockMode === "ai") launchAgent(d.id, d.agents[index])
                else launchScript(d.id, hostScripts(d)[index])
                dockMode = ""
                return true
            }
        }
        if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
            if (wide) detailZone = !detailZone && current !== null
            else nextTab(key === Qt.Key_Backtab ? -1 : 1)
            return true
        }
        if (wide && detailZone) {
            if (key === Qt.Key_Left) { moveDetail(-1, 0); return true }
            if (key === Qt.Key_Right) { moveDetail(1, 0); return true }
            if (key === Qt.Key_Up) { moveDetail(0, -1); return true }
            if (key === Qt.Key_Down) { moveDetail(0, 1); return true }
            if (key === Qt.Key_Return || key === Qt.Key_Enter) { activateTarget(detailTargets()[detailCursor]); return true }
        }
        if (key === Qt.Key_Up) { moveSelection(-1); return true }
        if (key === Qt.Key_Down) { moveSelection(1); return true }
        if (key === Qt.Key_Slash) { focusSearch(); return true }
        if (!d) {
            if (key === Qt.Key_N && profiles.devices.length === 0) { editDevice(null); return true }
            if (text !== "" && text.trim() !== "") { typeIntoSearch(text); return true }
            return false
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter) { launchDevice(d.id); return true }
        if (key === Qt.Key_Space) { togglePin(d); return true }
        if (key === Qt.Key_Delete) { requestHostDelete(d.id); return true }
        var letter = text.toLowerCase()
        var actions = {f: "files", c: "vscode", y: "copy", e: "edit", k: "verify", p: "pin", r: "retry"}
        if (letter === "k" && toasts.some(function(x) { return x.action === "verify" })) {
            toastAction(toasts.filter(function(x) { return x.action === "verify" }).pop())
            return true
        }
        if (actions[letter]) { runAction(actions[letter], d); return true }
        if (letter === "a") {
            if (wide) jumpDetail("agent:")
            else if (d.agents.length) { dockMode = dockMode === "ai" ? "" : "ai"; dockCursor = 0 }
            return true
        }
        if (letter === "s") {
            if (wide) jumpDetail("script:")
            else { dockMode = dockMode === "scripts" ? "" : "scripts"; dockCursor = 0 }
            return true
        }
        if (text !== "" && text.trim() !== "") { typeIntoSearch(text); return true }
        return false
    }

    // Match Yandex Music's lifecycle: closing never clears the active mode.
    // DraftState also restores the form if another widget instance opens.
    onOpenedChanged: if (opened) {
        clockMs = Date.now()
        menuHostId = ""
        quickMenuOpen = false
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
            focusSearch()
        } else if (page === "settings") {
            openSettings()
        }
    }

    // --- processes ------------------------------------------------------------

    Process {
        id: scriptPreview
        property string payload: ""
        property string kind: ""
        property string path: ""
        command: ["python3", root.helperPath, "--script-preview"]
        stdinEnabled: true
        onStarted: { write(payload + "\n"); payload = "" }
        stdout: StdioCollector { id: scriptPreviewStdout; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: function(code) {
            var body = scriptPreviewStdout.text || ""
            if (root.page !== "scriptEditor") return
            if (code !== 0 || body === "") {
                root.failure(root.t("Could not load script content; try again."))
                return
            }
            scriptContentField.text = body
            if (kind === "file") {
                root.scriptSavedPath = ""
                root.scriptFilePath = path
            }
            root.scriptContentLoaded = true
        }
    }

    Process {
        id: request
        property string payload: ""
        property string operation: ""
        command: ["python3", root.helperPath]
        stdinEnabled: true
        onStarted: { write(payload + "\n"); payload = "" }
        stdout: StdioCollector { id: requestStdout; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true } // Never forward helper stderr to the shell log.
        onExited: function(code) {
            requestGuard.stop()
            payload = ""
            var reply = requestStdout.text || ""
            var launching = ["launch", "launchAgent", "launchScript"].indexOf(operation) >= 0
            try {
                var result = JSON.parse(reply)
                if (!result || typeof result !== "object" || typeof result.ok !== "boolean")
                    throw new Error(root.t("Invalid helper response"))
                if (!result.ok) throw new Error(typeof result.error === "string" ? result.error : root.t("Helper error"))
                root.applyResult(operation, result)
            } catch (e) {
                var text = reply === "" ? root.t("Helper did not respond; check Python and permissions")
                                        : (String(e.message).indexOf("JSON") >= 0 ? root.t("Invalid helper response") : String(e.message))
                if (launching || operation === "trustHostKey") {
                    root.clearPendingLaunch()
                    root.endLaunch()
                }
                if (operation === "export" && root.page === "transfer") root.exportError = text
                else root.failure(text)
                if (root.barAction && !root.opened) root.open()
                root.barAction = false
                root.unmountQueue = []
                root.refreshAfterLoad = false
            }
        }
    }
    function applyResult(operation, result) {
        if (result.data) { profiles = result.data; loaded = true }
        if (result.globalSettings) {
            globalConfig = result.globalSettings
            revertSettings()
            settingsLoaded = true
        }
        if (result.terminals) terminals = result.terminals
        if (result.sftpStates) {
            sftpStates = operation === "list" ? result.sftpStates : Object.assign({}, sftpStates, result.sftpStates)
        }
        if (result.scripts) scripts = Object.assign({}, scripts, result.scripts)
        if (result.browser) scriptBrowser = result.browser
        if (result.preview) {
            importToken = result.token
            importSummary = result.preview
            importRows = result.previewRows || []
        }
        if (result.exportPreview) {
            exportPreview = result.exportPreview
        }
        var launching = ["launch", "launchAgent", "launchScript"].indexOf(operation) >= 0
        if (result.hostKeys) {
            if (launching) {
                // A launch never opens the verification page by itself: it
                // says why it stopped and offers the verification step.
                endLaunch()
                pendingHostKeys = result.hostKeys
                var d = deviceById(result.hostKeys.deviceId)
                var subject = pendingLaunchScript !== "" && d
                    ? (hostScripts(d).filter(function(s) { return s.id === root.pendingLaunchScript })[0] || {name: ""}).name
                    : ""
                toast("warning", subject ? t("%1: host key not verified").arg(subject) : t("Host key not verified"),
                      subject ? t("Scripts need a verified host key.") : t("Compare fingerprints once before the first connection."),
                      "verify", result.hostKeys.deviceId)
                if (barAction) open()
            } else {
                showHostKeys(result.hostKeys)
            }
        } else if (launching) {
            endLaunch()
            clearPendingLaunch()
            if (operation === "launchScript") toast("success", t("Script started"), t("See the terminal for its output."))
            else if (pendingLaunchClient === "sftp" || operation === "launch" && result.sftpStates)
                toast("success", result.message || t("Files opened"))
            else toast("success", t("Client opened"), t("See its window for the connection result."))
        }
        if (operation === "saveDevice") finishDeviceSave(result.data)
        else if (operation === "trustHostKey") {
            toast("success", t("Host key trusted"), t("Added to known_hosts."))
            var retry = {id: pendingLaunchId, client: pendingLaunchClient, agent: pendingLaunchAgent, script: pendingLaunchScript}
            showList()
            if (retry.id !== "") {
                pendingLaunchId = retry.id
                pendingLaunchClient = retry.client
                pendingLaunchAgent = retry.agent
                pendingLaunchScript = retry.script
                retryPendingLaunch()
            }
        } else if (operation === "deleteDevice") {
            toast("info", result.message || t("Host deleted"))
        } else if (operation === "import") {
            importToken = ""
            importRows = []
            importSummary = null
            toast("success", result.message || t("Import complete"))
            showList()
            refresh()
        } else if (operation === "export") {
            exportError = ""
            exportDone = exportPathField.text.split("/").pop()
        } else if (operation === "saveScript" || operation === "deleteScript") {
            page = scriptReturnPage
            toast("success", result.message || "")
        } else if (operation === "saveSettings") {
            toast("success", t("Settings saved"))
            showList()
        } else if (operation === "unmountSftp") {
            toast("info", result.message || t("SFTP disconnected"))
            if (unmountQueue.length > 0) Qt.callLater(pumpUnmount)
        }
        if (unmountQueue.length === 0) barAction = false
        if (page === "transfer" && transferTab === "export" && exportRequested !== exportNotes + "/" + exportPaths)
            Qt.callLater(requestExportPreview)
        if (refreshAfterLoad) {
            refreshAfterLoad = false
            Qt.callLater(refresh)
        }
        restoreDraftFocus()
    }
    Timer {
        id: requestGuard
        interval: 65000
        onTriggered: {
            request.signal(9); request.payload = ""
            if (["launch", "launchAgent", "launchScript", "trustHostKey"].indexOf(request.operation) >= 0) {
                root.clearPendingLaunch()
                root.endLaunch()
            }
            root.failure(root.t("Operation exceeded 65 seconds"))
        }
    }
    component CheckWorker: Process {
        id: worker
        property string deviceId: ""
        property string payload: ""
        property Timer guard: Timer { interval: 30000; onTriggered: worker.signal(9) }
        command: ["python3", root.helperPath]
        stdinEnabled: true
        onStarted: { write(payload + "\n"); payload = "" }
        stdout: StdioCollector { id: workerStdout; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: root.finishCheck(worker, workerStdout.text || "")
    }
    CheckWorker { id: checkWorker0 }
    CheckWorker { id: checkWorker1 }
    CheckWorker { id: checkWorker2 }
    CheckWorker { id: checkWorker3 }

    // Unsaved form endpoints are probed by their own process so typing never
    // blocks Save or other helper requests.
    Process {
        id: draftChecker
        property string payload: ""
        property string host: ""
        property int port: 0
        command: ["python3", root.helperPath]
        stdinEnabled: true
        onStarted: { write(payload + "\n"); payload = "" }
        stdout: StdioCollector { id: draftCheckerStdout; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: {
            if (draftChecker.host !== hostField.text.trim() || draftChecker.port !== Number(portField.text)) {
                root.scheduleDraftCheck()
                return
            }
            try {
                var result = JSON.parse(draftCheckerStdout.text || "")
                root.draftStatus = result.ok === true ? result.draftStatus
                                 : {error: typeof result.error === "string" ? result.error : root.t("Check failed")}
            } catch (e) {
                root.draftStatus = {error: root.t("Check failed")}
            }
        }
    }
    Timer {
        id: draftCheckTimer
        interval: 900
        onTriggered: root.checkDraftEndpoint()
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.opened
        onTriggered: {
            root.clockMs = Date.now()
            var now = Date.now()
            if (root.toasts.some(function(x) { return x.expires <= now }))
                root.toasts = root.toasts.filter(function(x) { return x.expires > now })
        }
    }
    // Badge, tooltip and menu need the catalog before the panel first opens.
    // Listing reads local files only; no host is contacted here.
    Component.onCompleted: if (!loaded) call({op: "list"})
    // Opt-in background check of pinned hosts, so the alert badge does not
    // depend on the last manual refresh. Closed panels also re-read the list
    // to pick up mounts and pins changed elsewhere.
    Timer {
        interval: Math.max(1, root.watchMinutes) * 60000
        repeat: true
        running: root.loaded && root.watchMinutes > 0
        onTriggered: {
            if (!root.opened && !root.busy) root.call({op: "list"})
            root.enqueueChecks(root.pinnedDevices.map(function(d) { return d.id }))
        }
    }
    Timer {
        id: copiedTimer
        interval: 2000
        onTriggered: root.hostKeyCopied = ""
    }

    Ui.BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        iconComponent: Component {
            RemoteHostsIcon {
                color: button.active && button.useActiveColor ? button.activeColor : button.foreground
                alertColor: Color.urgent
                mode: root.barMode
            }
        }
        // The bar tooltip is plain centered text; the hover card below
        // replaces it to keep the dots and hierarchy readable.
        tooltipText: ""
        onTooltipHoveredChanged: {
            root.clockMs = Date.now()
            if (tooltipHovered) hoverDelay.restart()
            else { hoverDelay.stop(); root.hoverShown = false; root.tooltipPage = -1; root.wheelDelta = 0 }
        }
        onPressed: function(b) {
            hoverDelay.stop()
            root.hoverShown = false
            if (b === Qt.MiddleButton) root.refresh()
            else if (b === Qt.RightButton) root.toggleQuickMenu()
            else { root.quickMenuOpen = false; root.toggle() }
        }
        onWheelMoved: function(delta) { root.scrollTooltip(delta) }
    }
    Timer {
        id: hoverDelay
        interval: 400
        onTriggered: root.hoverShown = button.tooltipHovered
    }
    PopupWindow {
        id: hoverCard
        readonly property var model: root.hoverModel()
        readonly property color text: Color.tooltip.text
        visible: root.hoverShown && !root.opened && !root.quickMenuOpen && button.QsWindow.window !== null
        color: "transparent"
        implicitWidth: Style.space(260)
        implicitHeight: Math.ceil(hoverColumn.implicitHeight + Style.space(20))
        anchor {
            window: button.QsWindow.window
            adjustment: PopupAdjustment.Slide
            edges: Edges.Top | Edges.Left
            gravity: Edges.Bottom | Edges.Right
            rect.width: 1
            rect.height: 1
            onAnchoring: {
                var window = button.QsWindow.window
                if (!window) return
                var position = root.bar ? root.bar.position : "top"
                var w = hoverCard.implicitWidth, h = hoverCard.implicitHeight
                var x = button.width / 2 - w / 2, y = button.height + 6
                if (position === "bottom") y = -h - 6
                else if (position === "left") { x = button.width + 6; y = button.height / 2 - h / 2 }
                else if (position === "right") { x = -w - 6; y = button.height / 2 - h / 2 }
                var point = window.contentItem.mapFromItem(button, x, y)
                hoverCard.anchor.rect.x = Math.round(point.x)
                hoverCard.anchor.rect.y = Math.round(point.y)
            }
        }
        Ui.BorderSurface {
            anchors.fill: parent
            color: Color.tooltip.background
            borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
            radius: Style.cornerRadius
            ColumnLayout {
                id: hoverColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(10)
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(5)
                Label {
                    visible: hoverCard.model.pager !== ""
                    text: "‹  " + hoverCard.model.pager + "  ›"
                    color: Qt.darker(hoverCard.text, 2.0)
                    font.pixelSize: Style.font.caption
                }
                Label {
                    text: hoverCard.model.title
                    color: hoverCard.text
                    font.bold: true
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
                Label {
                    visible: hoverCard.model.subtitle !== ""
                    text: hoverCard.model.subtitle
                    color: Qt.darker(hoverCard.text, 1.4)
                    font.pixelSize: Style.font.bodySmall
                }
                Repeater {
                    model: hoverCard.model.lines
                    RowLayout {
                        id: hoverLine
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Style.space(8)
                        Rectangle {
                            implicitWidth: Style.space(6)
                            implicitHeight: Style.space(6)
                            radius: width / 2
                            color: hoverLine.modelData.color
                        }
                        Label {
                            text: hoverLine.modelData.text
                            color: hoverLine.modelData.dim ? Qt.darker(hoverCard.text, 1.4) : hoverCard.text
                            font.pixelSize: Style.font.bodySmall
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                    }
                }
                Repeater {
                    model: hoverCard.model.footer
                    Label {
                        required property string modelData
                        text: modelData
                        color: Qt.darker(hoverCard.text, 2.0)
                        font.pixelSize: Style.font.caption
                    }
                }
            }
        }
    }
    QtObject {
        id: quickMenuOwner
        function close() { root.quickMenuOpen = false }
    }
    Ui.PopupCard {
        id: quickMenu
        anchorItem: button
        bar: root.bar
        owner: quickMenuOwner
        open: root.quickMenuOpen
        contentWidth: quickMenu.fittedContentWidth(Style.space(270))
        contentHeight: quickMenu.fittedContentHeight(quickColumn.implicitHeight)
        FocusScope {
            anchors.fill: parent
            focus: root.quickMenuOpen
            Keys.onPressed: function(event) { event.accepted = root.handleQuickKey(event) }
            ColumnLayout {
                id: quickColumn
                readonly property var items: root.quickMenuItems()
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 0
                Caption {
                    visible: root.pinnedDevices.length > 0
                    Layout.leftMargin: Style.space(6)
                    Layout.bottomMargin: Style.space(4)
                    text: root.t("Pinned").toUpperCase()
                    color: root.faintText
                    font.bold: true
                    font.letterSpacing: 1.2
                }
                Caption {
                    visible: root.loaded && root.pinnedDevices.length === 0
                    Layout.leftMargin: Style.space(6)
                    Layout.bottomMargin: Style.space(6)
                    text: root.t("Pin hosts in the panel to reach them from here.")
                }
                Repeater {
                    model: quickColumn.items
                    ColumnLayout {
                        id: quickEntry
                        required property var modelData
                        required property int index
                        readonly property bool usable: modelData.enabled !== false
                        Layout.fillWidth: true
                        spacing: 0
                        Ui.CursorSurface {
                            Layout.fillWidth: true
                            implicitHeight: Style.space(30)
                            hasCursor: quickEntry.usable && root.quickIndex === quickEntry.index
                            fill: Style.hoverFillFor(Color.foreground, Color.accent)
                            opacity: quickEntry.usable ? 1 : 0.45
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: quickEntry.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onContainsMouseChanged: if (containsMouse) root.quickIndex = quickEntry.index
                                onClicked: root.runQuickItem(quickEntry.modelData)
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Style.space(6)
                                anchors.rightMargin: Style.space(6)
                                spacing: Style.space(8)
                                StatusDot {
                                    visible: quickEntry.modelData.id === "host"
                                    kind: quickEntry.modelData.kind || "unknown"
                                }
                                Text {
                                    visible: quickEntry.modelData.id !== "host"
                                    Layout.preferredWidth: Style.space(10)
                                    horizontalAlignment: Text.AlignHCenter
                                    textFormat: Text.PlainText
                                    text: quickEntry.modelData.icon || ""
                                    color: root.secondaryText
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.body
                                }
                                Label {
                                    text: quickEntry.modelData.label
                                    color: quickEntry.modelData.dim ? root.secondaryText : Color.foreground
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                }
                                Caption {
                                    Layout.fillWidth: false
                                    visible: text !== ""
                                    text: quickEntry.modelData.key || ""
                                    color: root.faintText
                                    wrapMode: Text.NoWrap
                                }
                            }
                        }
                        Rectangle {
                            visible: quickEntry.modelData.separator === true
                            Layout.fillWidth: true
                            Layout.topMargin: Style.space(4)
                            Layout.bottomMargin: Style.space(4)
                            implicitHeight: 1
                            color: root.rule
                        }
                    }
                }
            }
        }
    }
    Ui.KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: root.page === "device" && State.DraftState.active
                     ? root.focusItem(State.DraftState.focusKey)
                     : root.page === "list" ? searchBox.field : pageFrame
        contentWidth: panel.fittedContentWidth(Style.space(root.wide ? 980 : 460))
        contentHeight: panel.fittedContentHeight(Style.space(root.wide ? 640 : 700))
        FocusScope {
            id: pageFrame
            anchors.fill: parent
            // Escape/outside click preserves the draft; leaving the editor is explicit.
            Keys.onPressed: function(event) { if (root.handleKey(event)) event.accepted = true }

            RowLayout {
                anchors.fill: parent
                spacing: 0
                enabled: root.confirmKind === ""

                // ---- host browser: whole panel when narrow, left pane when wide
                ColumnLayout {
                    id: browser
                    visible: root.wide || root.page === "list"
                    Layout.fillHeight: true
                    Layout.fillWidth: !root.wide
                    Layout.preferredWidth: root.wide ? Style.space(320) : -1
                    Layout.maximumWidth: root.wide ? Style.space(320) : -1
                    spacing: Style.space(10)
                    // Forms and pages dim the list but leave it clickable.
                    opacity: root.wide && root.page !== "list" ? 0.6 : 1

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(6)
                        Label {
                            text: root.t("Remote Hosts")
                            font.bold: true
                            font.pixelSize: Style.font.heading
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                        IconAction {
                            iconText: root.checking ? "" : "󰑐"
                            spinning: root.checking
                            active: root.checking
                            enabled: root.loaded && root.profiles.devices.length > 0
                            tooltipText: root.t("Refresh ping and SSH ports")
                            onClicked: root.refresh()
                        }
                        PrivacyButton { visible: !root.wide }
                        IconAction {
                            visible: !root.wide
                            iconText: "󰒓"
                            enabled: root.loaded
                            tooltipText: root.t("Settings")
                            onClicked: root.openSettings()
                        }
                        Primary {
                            visible: root.wide
                            iconText: "󰐕"
                            text: root.t("Host")
                            compact: true
                            enabled: root.loaded
                            tooltipText: root.t("New host")
                            onClicked: root.editDevice(null)
                        }
                    }
                    SearchBox { id: searchBox; Layout.fillWidth: true }
                    // Group tabs (narrow) or the match summary while searching.
                    ColumnLayout {
                        visible: !root.wide || root.query.trim() !== ""
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            visible: root.query.trim() === "" && !root.wide && root.profiles.devices.length > 0
                            Layout.fillWidth: true
                            spacing: Style.space(14)
                            Repeater {
                                model: [{id: "", name: root.t("All"), count: root.profiles.devices.length}].concat(
                                    root.profiles.groups.map(function(g) { return {id: g.id, name: g.name, count: root.groupDevices(g.id).length} })
                                        .filter(function(g) { return g.count > 0 }))
                                Tab {
                                    required property var modelData
                                    text: modelData.name
                                    count: modelData.count
                                    selected: root.groupFilter === modelData.id
                                    onClicked: root.groupFilter = modelData.id
                                }
                            }
                            Item { Layout.fillWidth: true }
                            IconAction {
                                iconText: "󰐕"
                                size: Style.space(24)
                                tooltipText: root.t("Groups")
                                onClicked: root.page = "groups"
                            }
                        }
                        RowLayout {
                            visible: root.query.trim() !== ""
                            Layout.fillWidth: true
                            Layout.bottomMargin: Style.space(6)
                            spacing: Style.space(8)
                            Label {
                                Layout.fillWidth: false
                                text: root.matchCount() === 1 ? root.t("1 match") : root.t("%1 matches").arg(root.matchCount())
                                font.bold: true
                                color: root.matchCount() === 0 ? Color.urgent : Color.foreground
                                wrapMode: Text.NoWrap
                            }
                            Caption { text: root.t("in name · address · group · note"); wrapMode: Text.NoWrap; elide: Text.ElideRight }
                            Caption { Layout.fillWidth: false; visible: !root.wide; text: root.t("Esc clears"); wrapMode: Text.NoWrap }
                        }
                        Rule { visible: !root.wide || root.query.trim() !== "" }
                    }
                    ProgressLine { visible: root.checking; Layout.fillWidth: true }

                    Scroll {
                        id: hostScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Style.space(2)
                        opacity: !root.wide && (root.dockMode === "ai" || root.dockMode === "scripts") ? 0.6 : 1
                        DraftRow {
                            visible: root.wide && State.DraftState.active && State.DraftState.editId === ""
                        }
                        Repeater {
                            model: root.sections()
                            ColumnLayout {
                                id: sectionBlock
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Style.space(2)
                                SectionTitle {
                                    Layout.topMargin: Style.space(6)
                                    text: sectionBlock.modelData.title
                                    count: sectionBlock.modelData.count
                                    collapsible: sectionBlock.modelData.group === true
                                    collapsed: root.collapsedGroups[sectionBlock.modelData.key] === true
                                    onToggled: root.toggleGroupCollapsed(sectionBlock.modelData.key)
                                }
                                Repeater {
                                    model: sectionBlock.modelData.rows
                                    HostRow {
                                        required property var modelData
                                        rowKey: modelData.key
                                        device: root.deviceById(modelData.id)
                                        showPin: !root.wide && sectionBlock.modelData.key === "pinned"
                                    }
                                }
                            }
                        }
                        RowLayout {
                            visible: root.checking && !root.wide
                            Layout.fillWidth: true
                            Layout.topMargin: Style.space(8)
                            Layout.leftMargin: Style.space(10)
                            spacing: Style.space(8)
                            Spinner {}
                            Caption {
                                text: root.t("Checking %1 of %2 · ping + SSH port · list stays usable")
                                      .arg(Math.min(root.checkTotal, root.checkDone + 1)).arg(root.checkTotal)
                            }
                        }
                        RowLayout {
                            visible: root.query.trim() !== "" && root.rows.length > 0
                            Layout.fillWidth: true
                            Layout.topMargin: Style.space(10)
                            Layout.leftMargin: Style.space(10)
                            spacing: Style.space(8)
                            Caption { Layout.fillWidth: false; text: "↵"; font.pixelSize: Style.font.body }
                            Caption { text: root.t("Enter connects to the best match right away") }
                        }
                        EmptyState {
                            visible: root.loaded && root.query.trim() !== "" && root.rows.length === 0
                            Layout.topMargin: Style.space(root.wide ? 40 : 120)
                            iconText: "󰍉"
                            title: root.t("No host matches “%1”").arg(root.query.trim())
                            body: root.t("Add it as a new host — the name is filled in for you.")
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillWidth: false
                                spacing: Style.space(10)
                                Primary {
                                    iconText: "󰐕"
                                    text: root.t("Add “%1”").arg(root.query.trim())
                                    onClicked: { var name = root.query.trim(); root.query = ""; root.editDevice(null, name) }
                                }
                                Action { iconText: "󰅖"; text: root.t("Clear") + "   Esc"; bordered: true; onClicked: { root.query = ""; root.focusSearch() } }
                            }
                        }
                        EmptyState {
                            visible: root.loaded && root.profiles.devices.length === 0 && (root.wide || root.query.trim() === "")
                            Layout.topMargin: Style.space(root.wide ? 120 : 80)
                            iconText: "󰒋"
                            title: root.wide ? "" : root.t("Add your first host")
                            body: root.wide ? root.t("No hosts yet") : root.t("A server, NAS or another computer. Once added you get SSH, Files, VS Code, AI CLI and scripts here in one click.")
                            RowLayout {
                                visible: !root.wide
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillWidth: false
                                spacing: Style.space(10)
                                Primary { iconText: "󰐕"; text: root.t("Add host") + "   N"; onClicked: root.editDevice(null) }
                                Action { iconText: "󰇚"; text: root.t("Import JSON"); bordered: true; onClicked: root.openTransfer("import") }
                            }
                        }
                        Caption {
                            visible: !root.loaded
                            Layout.topMargin: Style.space(20)
                            horizontalAlignment: Text.AlignHCenter
                            text: root.t("Loading…")
                        }
                    }

                    ToastStack { visible: !root.wide && root.toasts.length > 0 }

                    Rule { visible: root.wide }
                    RowLayout {
                        visible: root.wide
                        Layout.fillWidth: true
                        spacing: Style.space(4)
                        Action { iconText: "󰌨"; text: root.t("Groups"); selected: root.page === "groups"; enabled: root.loaded; onClicked: root.page = "groups" }
                        Action { iconText: "󰓡"; text: root.t("Import / export"); selected: root.page === "transfer"; enabled: root.loaded; onClicked: root.openTransfer("import") }
                        Item { Layout.fillWidth: true }
                        IconAction {
                            iconText: "󰒓"
                            active: root.page === "settings"
                            enabled: root.loaded
                            tooltipText: root.t("Settings")
                            onClicked: root.page === "settings" ? root.showList() : root.openSettings()
                        }
                    }
                    Dock { visible: !root.wide && root.current !== null }
                    RowLayout {
                        visible: !root.wide && root.current === null && root.loaded && root.profiles.devices.length > 0
                        Layout.fillWidth: true
                        Caption { text: root.t("The dock hides when nothing is selected") }
                    }
                }

                Rectangle {
                    visible: root.wide
                    Layout.fillHeight: true
                    Layout.leftMargin: Style.space(14)
                    Layout.rightMargin: Style.space(18)
                    implicitWidth: 1
                    color: root.rule
                }

                // ---- right pane (wide) or full-panel page (narrow)
                Item {
                    id: pagePane
                    visible: root.wide || root.page !== "list"
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Detail { anchors.fill: parent; visible: root.page === "list" && root.wide }

                    // ---- host form
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.page === "device"
                        spacing: Style.space(12)
                        PageHeader {
                            title: root.t(root.editId ? "Edit host" : "New host")
                            subtitle: root.t("Draft is kept while the panel is closed")
                            showPrivacy: false
                            Action { text: root.t("Discard"); enabled: !root.busy; onClicked: root.requestConfirm("discardDraft", "") }
                            Primary {
                                iconText: "󰄬"
                                text: root.busy && request.operation === "saveDevice" ? root.t("Saving…") : root.t("Save") + "   Ctrl+↵"
                                enabled: !root.busy
                                onClicked: root.saveDevice()
                            }
                        }
                        Scroll {
                            id: formScroll
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            GridLayout {
                                Layout.fillWidth: true
                                columns: root.wide ? 2 : 1
                                columnSpacing: Style.space(28)
                                rowSpacing: Style.space(16)
                                enabled: !root.busy
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.alignment: Qt.AlignTop
                                    spacing: Style.space(10)
                                    Rule { title: root.t("Connection") }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Style.space(12)
                                        FieldBlock {
                                            label: root.t("Name")
                                            Field { id: nameField; placeholderText: root.t("For example, home server"); maximumLength: 100; onTextChanged: if (State.DraftState.active) State.DraftState.name = text; onActiveFocusChanged: root.rememberDraftFocus("name", nameField) }
                                        }
                                        FieldBlock {
                                            label: root.t("Group")
                                            Layout.preferredWidth: Style.space(150)
                                            Layout.fillWidth: false
                                            Choice {
                                                id: groupChoice
                                                options: root.profiles.groups.map(function(g) { return {value: g.id, label: g.name} })
                                                onChanged: function(v) { value = v; if (State.DraftState.active) State.DraftState.group = v }
                                            }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Style.space(12)
                                        FieldBlock {
                                            label: root.t("Server address")
                                            Field {
                                                id: hostField
                                                enabled: !root.addressesHidden
                                                layer.enabled: root.addressesHidden && visible
                                                layer.effect: PrivacyBlur {}
                                                placeholderText: root.t("IPv4, IPv6 or domain")
                                                maximumLength: 253
                                                onTextChanged: {
                                                    if (State.DraftState.active) State.DraftState.host = text
                                                    root.scheduleDraftCheck()
                                                }
                                                onActiveFocusChanged: root.rememberDraftFocus("host", hostField)
                                            }
                                        }
                                        FieldBlock {
                                            label: root.t("Port")
                                            Layout.preferredWidth: Style.space(90)
                                            Layout.fillWidth: false
                                            Field {
                                                id: portField
                                                enabled: !root.addressesHidden
                                                layer.enabled: root.addressesHidden && visible
                                                layer.effect: PrivacyBlur {}
                                                accent: root.draftPortValid ? Color.accent : Color.urgent
                                                foreground: root.draftPortValid ? Color.foreground : Color.urgent
                                                placeholderText: "22"
                                                maximumLength: 5
                                                onTextChanged: {
                                                    if (State.DraftState.active) State.DraftState.port = text
                                                    root.scheduleDraftCheck()
                                                }
                                                onActiveFocusChanged: root.rememberDraftFocus("port", portField)
                                            }
                                        }
                                    }
                                    Notice {
                                        visible: !root.draftPortValid && State.DraftState.active
                                        kind: "error"
                                        text: root.t("SSH port must be an integer from 1 to 65535")
                                    }
                                    FieldBlock {
                                        label: root.t("SSH login")
                                        Field {
                                            id: loginField
                                            enabled: !root.addressesHidden
                                            placeholderText: "root"
                                            maximumLength: 64
                                            layer.enabled: root.addressesHidden && visible
                                            layer.effect: PrivacyBlur {}
                                            onTextChanged: if (State.DraftState.active) State.DraftState.login = text
                                            onActiveFocusChanged: root.rememberDraftFocus("login", loginField)
                                        }
                                    }
                                    Caption { visible: root.addressesHidden; text: root.t("Turn off address hiding to edit these fields.") }
                                    Tinted {
                                        Layout.fillWidth: true
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.space(8)
                                            StatusDot { kind: root.draftStatusInfo().kind }
                                            Caption {
                                                text: root.draftStatusInfo().label
                                                layer.enabled: root.addressesHidden && visible
                                                layer.effect: PrivacyBlur {}
                                            }
                                            Action {
                                                visible: root.draftStatus !== null
                                                iconText: "󰑐"
                                                text: root.t("Retry")
                                                onClicked: root.checkDraftEndpoint()
                                            }
                                        }
                                    }
                                    Rule { title: root.t("Authentication"); Layout.topMargin: Style.space(6) }
                                    Segmented {
                                        Layout.fillWidth: true
                                        value: State.DraftState.auth
                                        options: [{value: "agent", label: root.t("Key / SSH agent"), icon: "󰌆"},
                                                  {value: "password", label: root.t("Password"), icon: "󰌾"}]
                                        onChanged: function(v) { root.setAuth(v) }
                                    }
                                    ColumnLayout {
                                        visible: State.DraftState.auth === "agent"
                                        Layout.fillWidth: true
                                        spacing: Style.space(8)
                                        FieldBlock {
                                            label: root.t("Key file · optional")
                                            Field {
                                                id: keyField
                                                placeholderText: root.t("Empty uses default keys or the SSH agent")
                                                maximumLength: 1024
                                                onTextChanged: if (State.DraftState.active) {
                                                    if (text !== State.DraftState.keyPath && text !== "") {
                                                        passphraseField.text = ""
                                                        State.DraftState.passphrase = ""
                                                    }
                                                    State.DraftState.keyPath = text
                                                    if (text === "") {
                                                        State.DraftState.saveKeyPassphrase = false
                                                        passphraseField.text = ""
                                                        State.DraftState.passphrase = ""
                                                    }
                                                }
                                                onActiveFocusChanged: root.rememberDraftFocus("key", keyField)
                                            }
                                        }
                                        CheckRow {
                                            checked: State.DraftState.saveKeyPassphrase
                                            enabled: keyField.text !== ""
                                            text: root.t("Save key passphrase")
                                            detail: root.t("Auto-fill applies to terminal, AI CLI, and SFTP, not VS Code.")
                                            onToggled: {
                                                State.DraftState.saveKeyPassphrase = !State.DraftState.saveKeyPassphrase
                                                if (!State.DraftState.saveKeyPassphrase) {
                                                    passphraseField.text = ""
                                                    State.DraftState.passphrase = ""
                                                }
                                            }
                                        }
                                        FieldBlock {
                                            visible: State.DraftState.saveKeyPassphrase
                                            label: root.t("Key passphrase")
                                            hint: root.t("Stored in Secret Service. Re-enter after changing address, port, login, or key.")
                                            Field {
                                                id: passphraseField
                                                password: true
                                                placeholderText: root.t(root.editId ? "Empty keeps the saved passphrase" : "Key passphrase")
                                                maximumLength: 4096
                                                onTextChanged: if (State.DraftState.active) State.DraftState.passphrase = text
                                                onActiveFocusChanged: root.rememberDraftFocus("passphrase", passphraseField)
                                            }
                                        }
                                    }
                                    FieldBlock {
                                        visible: State.DraftState.auth === "password"
                                        label: root.t(root.editId ? "New password" : "Password")
                                        hint: root.t("Stored in Secret Service. Enter it again after changing address, port, or login.")
                                        Field { id: passwordField; password: true; placeholderText: root.t(root.editId ? "Empty keeps the saved password" : "SSH password"); maximumLength: 4096; onTextChanged: if (State.DraftState.active) State.DraftState.password = text; onActiveFocusChanged: root.rememberDraftFocus("password", passwordField) }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.alignment: Qt.AlignTop
                                    spacing: Style.space(10)
                                    Rule { title: "AI CLI"; trailing: root.t("%1 of %2").arg(State.DraftState.agents.length).arg(Object.keys(root.agentLabels).length) }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: Style.space(6)
                                        Repeater {
                                            model: Object.keys(root.agentLabels)
                                            Action {
                                                required property string modelData
                                                readonly property bool on: State.DraftState.agents.indexOf(modelData) >= 0
                                                iconText: on ? "󰄬" : "󰐕"
                                                text: root.agentLabel(modelData)
                                                bordered: true
                                                selected: on
                                                onClicked: root.toggleDraftAgent(modelData)
                                            }
                                        }
                                    }
                                    FieldBlock {
                                        label: root.t("Project folder · optional")
                                        hint: root.t("AI CLI tools start here. Empty uses the home directory.")
                                        Field {
                                            id: agentFolderField
                                            placeholderText: "/home/…/project"
                                            maximumLength: 1024
                                            onTextChanged: if (State.DraftState.active) State.DraftState.agentFolder = text
                                            onActiveFocusChanged: root.rememberDraftFocus("agentFolder", agentFolderField)
                                        }
                                    }
                                    Rule { title: root.t("Scripts"); trailing: root.editId ? String(root.hostScripts(root.deviceById(root.editId)).length) : ""; Layout.topMargin: Style.space(6) }
                                    Tinted {
                                        visible: root.editId === ""
                                        Layout.fillWidth: true
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.space(10)
                                            Caption { Layout.fillWidth: false; text: "󰌾"; font.pixelSize: Style.font.body }
                                            Caption { text: root.t("Save this host before adding scripts.") }
                                        }
                                    }
                                    Repeater {
                                        model: root.editId ? root.hostScripts(root.deviceById(root.editId)) : []
                                        RowLayout {
                                            id: formScriptRow
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: Style.space(6)
                                            Caption { Layout.fillWidth: false; text: "󰐊"; font.pixelSize: Style.font.body }
                                            Label { text: formScriptRow.modelData.name; font.bold: true; elide: Text.ElideRight; wrapMode: Text.NoWrap; Layout.minimumWidth: 0 }
                                            IconAction { iconText: "󰏫"; tooltipText: root.t("Edit script"); onClicked: root.editScript(root.editId, formScriptRow.modelData) }
                                            IconAction {
                                                iconText: "󰆴"
                                                hoverColor: Color.urgent
                                                tooltipText: root.t("Delete script")
                                                onClicked: { root.scriptHostId = root.editId; root.scriptReturnPage = "device"; root.requestConfirm("deleteScript", formScriptRow.modelData.id) }
                                            }
                                        }
                                    }
                                    Action {
                                        visible: root.editId !== ""
                                        Layout.fillWidth: true
                                        iconText: "󰐕"
                                        text: root.t("Add script")
                                        bordered: true
                                        onClicked: root.editScript(root.editId, null)
                                    }
                                    Rule { title: root.t("Advanced"); Layout.topMargin: Style.space(6) }
                                    FieldBlock {
                                        label: root.t("Files / VS Code folder · optional")
                                        Field { id: folderField; placeholderText: "/home/…/project"; maximumLength: 1024; onTextChanged: if (State.DraftState.active) State.DraftState.remoteFolder = text; onActiveFocusChanged: root.rememberDraftFocus("folder", folderField) }
                                    }
                                    FieldBlock {
                                        label: root.t("Note · not for secrets")
                                        Controls.TextArea {
                                            id: noteField
                                            Layout.fillWidth: true
                                            implicitHeight: Math.max(Style.space(64), contentHeight + topPadding + bottomPadding)
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
                        }
                    }

                    // ---- host key verification
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.page === "hostkey"
                        spacing: Style.space(12)
                        PageHeader {
                            title: root.t("Verify host key") + " · " + (root.deviceById(root.hostKeyDeviceId) || {name: ""}).name
                            subtitle: root.hostKeyEndpoint + " · " + root.t("scanned %1").arg(root.ageText(Math.max(0, (root.clockMs - root.hostKeyScannedAt) / 1000)))
                            blurSubtitle: true
                            Action {
                                iconText: "󰑐"
                                text: root.t("Rescan")
                                bordered: true
                                enabled: !root.busy
                                onClicked: root.inspectHostKey(root.hostKeyDeviceId, true)
                            }
                        }
                        Scroll {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Style.space(12)
                            RowLayout {
                                visible: root.hostKeyState === "new"
                                Layout.fillWidth: true
                                spacing: Style.space(10)
                                Step { number: 1; text: root.t("Scan"); done: true }
                                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.secondaryText }
                                Step { number: 2; text: root.t("Compare"); done: true; current: !root.hostKeyCompared }
                                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.rule }
                                Step { number: 3; text: root.t("Trust"); done: root.hostKeyCompared; current: root.hostKeyCompared }
                            }
                            Rule { title: root.t("SHA256 fingerprints"); trailing: root.t("%1 keys").arg(root.hostKeyKeys.length) }
                            Repeater {
                                model: root.hostKeyKeys
                                Ui.CursorSurface {
                                    id: keyCard
                                    required property var modelData
                                    readonly property bool copied: root.hostKeyCopied === modelData.fingerprint
                                    Layout.fillWidth: true
                                    implicitHeight: keyColumn.implicitHeight + Style.space(20)
                                    hasCursor: keyHover.hovered
                                    current: copied
                                    HoverHandler { id: keyHover }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Style.space(12)
                                        anchors.rightMargin: Style.space(12)
                                        spacing: Style.space(10)
                                        ColumnLayout {
                                            id: keyColumn
                                            Layout.fillWidth: true
                                            spacing: Style.space(4)
                                            Caption { text: root.algorithmLabel(keyCard.modelData.algorithm); font.bold: true; font.letterSpacing: 1.6 }
                                            Flow {
                                                Layout.fillWidth: true
                                                spacing: Style.space(10)
                                                Repeater {
                                                    model: root.fingerprintGroups(keyCard.modelData.fingerprint)
                                                    Text {
                                                        required property string modelData
                                                        required property int index
                                                        textFormat: Text.PlainText
                                                        text: modelData
                                                        color: index % 2 ? root.secondaryText : Color.foreground
                                                        font.family: Style.font.family
                                                        font.pixelSize: Style.font.subtitle
                                                    }
                                                }
                                            }
                                        }
                                        Action {
                                            iconText: keyCard.copied ? "󰄬" : "󰆏"
                                            text: keyCard.copied ? root.t("Copied") : root.t("Copy")
                                            onClicked: root.copyFingerprint(keyCard.modelData)
                                        }
                                    }
                                }
                            }
                            Caption { text: root.t("Fingerprints are split into groups of 11 so they can be read aloud over the phone. Existing known_hosts entries are never replaced or removed. A changed key must be resolved with the administrator.") }
                            Notice {
                                visible: root.hostKeyState !== "new"
                                kind: root.hostKeyState === "known" ? "info" : "error"
                                title: root.hostKeyState === "known" ? root.t("Already trusted") : root.t("Not changed")
                                text: root.hostKeyMessage
                            }
                            GridLayout {
                                visible: root.hostKeyState === "new"
                                Layout.fillWidth: true
                                Layout.topMargin: Style.space(6)
                                columns: root.wide ? 2 : 1
                                columnSpacing: Style.space(24)
                                rowSpacing: Style.space(12)
                                Notice {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredWidth: 1
                                    kind: "error"
                                    iconText: "󰒃"
                                    title: root.t("A scan does not prove identity")
                                    text: root.t("Compare every fingerprint with the administrator over a separate trusted channel.")
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.alignment: Qt.AlignTop
                                    spacing: Style.space(10)
                                    CheckRow {
                                        checked: root.hostKeyCompared
                                        text: root.t("I compared the fingerprints with the administrator")
                                        onToggled: root.hostKeyCompared = !root.hostKeyCompared
                                    }
                                    Primary {
                                        id: trustHostKeyButton
                                        Layout.fillWidth: true
                                        iconText: "󰒃"
                                        text: root.t("Trust & add to known_hosts")
                                        enabled: root.hostKeyCompared && root.hostKeyToken !== "" && !root.addressesHidden && !root.busy
                                        onClicked: root.call({op: "trustHostKey", id: root.hostKeyDeviceId, keys: root.hostKeyKeys, token: root.hostKeyToken})
                                    }
                                    Caption { text: root.t("Enabled after the checkbox. Disabled while addresses are hidden.") }
                                }
                            }
                        }
                    }

                    // ---- settings
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.page === "settings"
                        spacing: Style.space(12)
                        PageHeader {
                            title: root.t("Settings")
                            subtitle: root.t("Applies to new connections · not exported")
                            showPrivacy: !root.wide
                            Action { visible: root.wide; text: root.t("Revert"); enabled: root.settingsDirty && !root.busy; onClicked: root.revertSettings() }
                            Primary { visible: root.wide; iconText: "󰄬"; text: root.t("Save"); enabled: root.settingsDirty && root.terminalAvailable && !root.busy; onClicked: root.saveSettings() }
                        }
                        Scroll {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            GridLayout {
                                Layout.fillWidth: true
                                columns: root.wide ? 2 : 1
                                columnSpacing: Style.space(28)
                                rowSpacing: Style.space(14)
                                enabled: !root.busy && root.settingsLoaded
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.alignment: Qt.AlignTop
                                    spacing: Style.space(12)
                                    Rule { title: root.t("General") }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: root.t("Language") }
                                        Segmented {
                                            value: root.languageDraft
                                            options: [{value: "en", label: "English"}, {value: "ru", label: "Русский"}]
                                            onChanged: function(v) { root.languageDraft = v }
                                        }
                                    }
                                    Rule { title: root.t("Layout"); visible: !root.wide }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.space(2)
                                            Label { text: root.t("Panel layout") }
                                            Caption { text: root.t("Auto: wide from 760 px") }
                                        }
                                        Segmented {
                                            value: root.layoutDraft
                                            options: [{value: "auto", label: root.t("Auto")}, {value: "compact", label: root.t("Compact")},
                                                      {value: "wide", label: root.t("Wide")}]
                                            onChanged: function(v) { root.layoutDraft = v }
                                        }
                                    }
                                    Rule { title: root.t("Bar") }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Style.space(2)
                                            Label { text: root.t("Check pinned hosts") }
                                            Caption { text: root.t("Minutes between background checks · lights the bar badge") }
                                        }
                                        Segmented {
                                            value: root.watchDraft
                                            options: [{value: "0", label: root.t("Off")}, {value: "5", label: "5"}, {value: "15", label: "15"},
                                                      {value: "30", label: "30"}, {value: "60", label: "60"}]
                                            onChanged: function(v) { root.watchDraft = v }
                                        }
                                    }
                                    Rule { title: root.t("About"); visible: root.wide }
                                    InfoLine { visible: root.wide; iconText: "󰋼"; text: root.t("Changes apply to new connections; open terminals keep running.") }
                                    InfoLine { visible: root.wide; iconText: "󰒃"; text: root.t("Settings are stored separately from hosts and never exported.") }
                                    InfoLine { visible: root.wide; iconText: "󰗊"; text: root.t("Language and layout switch the whole panel after Save.") }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.alignment: Qt.AlignTop
                                    spacing: Style.space(6)
                                    Rule { title: root.t("Terminal"); trailing: "SSH · AI CLI · " + root.t("scripts") }
                                    Caption { visible: !root.wide; text: root.t("Opens SSH, AI CLI and scripts on every host. VS Code and Files open on their own.") }
                                    Notice {
                                        visible: root.settingsLoaded && !root.terminalAvailable
                                        kind: "error"
                                        text: root.t("%1 is not in PATH. SSH and AI CLI cannot open until you pick an installed terminal or install it yourself.")
                                              .arg((root.terminals.filter(function(t) { return t.value === root.terminalDraft })[0] || {label: root.terminalDraft}).label)
                                    }
                                    Repeater {
                                        model: root.terminals
                                        Ui.CursorSurface {
                                            id: terminalRow
                                            required property var modelData
                                            readonly property bool chosen: root.terminalDraft === modelData.value
                                            Layout.fillWidth: true
                                            implicitHeight: Style.space(40)
                                            hasCursor: terminalMouse.containsMouse
                                            current: chosen
                                            color: chosen && !modelData.available ? root.urgentTint : (hasCursor ? fill : chosen ? currentFill : "transparent")
                                            MouseArea {
                                                id: terminalMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.terminalDraft = terminalRow.modelData.value
                                            }
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Style.space(12)
                                                anchors.rightMargin: Style.space(12)
                                                spacing: Style.space(12)
                                                Radio { checked: terminalRow.chosen; danger: !terminalRow.modelData.available }
                                                Label {
                                                    text: terminalRow.modelData.label
                                                    font.bold: terminalRow.chosen
                                                    color: terminalRow.modelData.available || terminalRow.chosen ? Color.foreground : root.secondaryText
                                                    wrapMode: Text.NoWrap
                                                }
                                                Caption {
                                                    Layout.fillWidth: false
                                                    text: terminalRow.modelData.available ? root.t("installed") : root.t("not installed")
                                                    color: terminalRow.modelData.available ? root.faintText : Color.urgent
                                                    wrapMode: Text.NoWrap
                                                }
                                            }
                                        }
                                    }
                                    Caption { visible: root.wide; text: root.t("VS Code and Files open in their own windows and ignore this choice.") }
                                    InfoLine { visible: !root.wide; iconText: "󰋼"; text: root.t("Stored separately from hosts and not included in import / export.") }
                                }
                            }
                        }
                        Footer {
                            visible: !root.wide
                            status: root.settingsLoaded && !root.terminalAvailable ? root.t("Save is blocked") : ""
                            Action { text: root.t("Cancel"); onClicked: root.showList() }
                            Primary { iconText: "󰄬"; text: root.t("Save"); enabled: root.settingsDirty && root.terminalAvailable && !root.busy; onClicked: root.saveSettings() }
                        }
                    }

                    // ---- import / export
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.page === "transfer"
                        spacing: Style.space(12)
                        PageHeader {
                            title: root.t("Import / export")
                            subtitle: root.t("JSON · passwords and keys are never transferred")
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(18)
                            Tab { text: root.t("Import"); iconText: "󰇚"; selected: root.transferTab === "import"; onClicked: root.transferTab = "import" }
                            Tab {
                                text: root.t("Export")
                                iconText: "󰕒"
                                selected: root.transferTab === "export"
                                onClicked: { root.transferTab = "export"; root.exportDone = ""; root.requestExportPreview() }
                            }
                            Item { Layout.fillWidth: true }
                        }
                        Rule { Layout.topMargin: -Style.space(12) }
                        Scroll {
                            visible: root.transferTab === "import"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Style.space(12)
                            FieldBlock {
                                label: root.t("JSON file · absolute path")
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(10)
                                    Field {
                                        id: importPathField
                                        placeholderText: "/home/…/hosts.json"
                                        enabled: !root.busy
                                        onTextChanged: root.importToken = ""
                                        onAccepted: root.previewImport()
                                    }
                                    Action { iconText: "󰈈"; text: root.t("Preview"); bordered: true; enabled: !root.busy && importPathField.text !== ""; onClicked: root.previewImport() }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(12)
                                Caption { Layout.fillWidth: !root.wide; text: root.t("When address, port and login match"); font.pixelSize: Style.font.body; wrapMode: Text.NoWrap }
                                Segmented {
                                    Layout.fillWidth: !root.wide
                                    value: root.importPolicy
                                    options: [{value: "skip", label: root.t("Skip")}, {value: "replace", label: root.t("Update, keep local auth")}]
                                    onChanged: function(v) { root.importPolicy = v; root.importToken = "" }
                                }
                                Item { visible: root.wide; Layout.fillWidth: true }
                            }
                            ColumnLayout {
                                visible: root.importToken !== "" && root.importSummary !== null
                                Layout.fillWidth: true
                                spacing: Style.space(10)
                                Rule {
                                    title: root.t("Preview")
                                    trailing: root.importSummary ? root.t("%1 hosts after import · %2 groups").arg(root.importSummary.hosts).arg(root.importSummary.groups) : ""
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.space(2)
                                    Stat { sign: "+"; value: root.importSummary ? root.importSummary.added : 0; label: root.t("new") }
                                    Stat { sign: "~"; value: root.importSummary ? root.importSummary.replaced : 0; label: root.t("updated"); valueColor: Color.accent }
                                    Stat { sign: "="; value: root.importSummary ? root.importSummary.skipped : 0; label: root.t("skipped"); valueColor: root.secondaryText }
                                }
                                RowLayout {
                                    visible: root.wide
                                    Layout.fillWidth: true
                                    Layout.topMargin: Style.space(4)
                                    spacing: Style.space(10)
                                    Item { implicitWidth: Style.space(16) }
                                    ColumnHead { Layout.preferredWidth: 3; label: root.t("Host") }
                                    ColumnHead { Layout.preferredWidth: 2; label: root.t("Group") }
                                    ColumnHead { Layout.preferredWidth: 5; label: root.t("Endpoint") }
                                    ColumnHead { Layout.preferredWidth: 2; label: root.t("Auth") }
                                    ColumnHead { Layout.preferredWidth: 2; label: "AI" }
                                }
                                Repeater {
                                    model: root.importRows
                                    ImportRow {}
                                }
                            }
                            InfoLine { iconText: "󰌆"; text: root.t("Passwords and key contents are never transferred. New hosts start with a key / SSH agent.") }
                            InfoLine { iconText: "󰌾"; text: root.t("Apply uses exactly this preview. If the file or your hosts change, preview again.") }
                        }
                        Footer {
                            visible: root.transferTab === "import"
                            status: root.importToken !== "" ? root.t("Preview is up to date") : root.t("Preview the file first")
                            Action { text: root.t("Cancel"); onClicked: root.showList() }
                            Primary {
                                iconText: "󰇚"
                                text: root.t("Apply import")
                                enabled: root.importToken !== "" && !root.busy
                                onClicked: root.call({op: "import", path: importPathField.text, policy: root.importPolicy, token: root.importToken})
                            }
                        }
                        Scroll {
                            visible: root.transferTab === "export"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            GridLayout {
                                Layout.fillWidth: true
                                columns: root.wide ? 2 : 1
                                columnSpacing: Style.space(28)
                                rowSpacing: Style.space(14)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.alignment: Qt.AlignTop
                                    spacing: Style.space(12)
                                    FieldBlock {
                                        label: root.t("New JSON file · absolute path")
                                        hint: root.exportError !== "" ? "" : root.t("Must not exist yet — nothing is overwritten. Saved with 0600.")
                                        Field {
                                            id: exportPathField
                                            enabled: !root.busy
                                            placeholderText: "/home/…/hosts.json"
                                            accent: root.exportError !== "" ? Color.urgent : Color.accent
                                            onTextChanged: { root.exportError = ""; root.exportDone = "" }
                                        }
                                    }
                                    Caption { visible: root.exportError !== ""; text: root.exportError; color: Color.urgent }
                                    Rule { title: root.t("Include") }
                                    CheckRow { checked: true; locked: true; text: root.t("Hosts and groups"); detail: root.t("Name, address, port, login, AI CLI. Auth becomes key / agent.") }
                                    CheckRow {
                                        checked: root.exportNotes
                                        text: root.t("Notes")
                                        detail: root.t("Free-text notes of every host")
                                        onToggled: { root.exportNotes = !root.exportNotes; root.requestExportPreview() }
                                    }
                                    CheckRow {
                                        checked: root.exportPaths
                                        text: root.t("Paths")
                                        detail: root.t("Key file, AI CLI folder, Files / VS Code folder")
                                        onToggled: { root.exportPaths = !root.exportPaths; root.requestExportPreview() }
                                    }
                                    Tinted {
                                        visible: !root.wide
                                        Layout.fillWidth: true
                                        Caption { text: root.t("Never exported").toUpperCase(); font.bold: true; font.letterSpacing: 1.6 }
                                        Label { text: root.t("Passwords · key passphrases · key contents · scripts · settings · whether a secret is saved") }
                                    }
                                }
                                ColumnLayout {
                                    visible: root.wide
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    Layout.alignment: Qt.AlignTop
                                    spacing: Style.space(10)
                                    Rule {
                                        title: root.t("File preview")
                                        trailing: root.exportPreview ? root.t("%1 hosts · %2 groups").arg(root.exportPreview.hosts).arg(root.exportPreview.groups) : ""
                                    }
                                    Tinted {
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.fillWidth: true
                                            textFormat: Text.PlainText
                                            wrapMode: Text.WrapAnywhere
                                            text: root.exportSampleText()
                                            color: root.secondaryText
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.bodySmall
                                            lineHeight: 1.3
                                            layer.enabled: root.addressesHidden && visible
                                            layer.effect: PrivacyBlur {}
                                        }
                                    }
                                    Caption { text: root.t("Auth is always exported as key / agent — a file never claims a saved password. Passwords, passphrases, key contents, scripts and settings are never exported.") }
                                }
                            }
                            Notice {
                                visible: root.exportDone !== ""
                                Layout.topMargin: Style.space(6)
                                kind: "success"
                                title: root.t("Exported without passwords")
                                text: root.exportDone + " · " + root.t("permissions 0600")
                            }
                        }
                        Footer {
                            visible: root.transferTab === "export"
                            status: root.exportPreview ? root.t("%1 hosts · %2 groups").arg(root.exportPreview.hosts).arg(root.exportPreview.groups) : ""
                            Action { text: root.t("Cancel"); onClicked: root.showList() }
                            Primary {
                                iconText: "󰕒"
                                text: root.t("Export")
                                enabled: !root.busy && exportPathField.text !== "" && root.exportError === ""
                                onClicked: root.call({op: "export", path: exportPathField.text, notes: root.exportNotes, paths: root.exportPaths})
                            }
                        }
                    }

                    // ---- groups
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.page === "groups"
                        spacing: Style.space(12)
                        PageHeader {
                            title: root.t("Groups")
                            subtitle: root.t("%1 groups · changes save immediately").arg(root.profiles.groups.length)
                            Primary { visible: root.wide; iconText: "󰐕"; text: root.t("Group") + "   N"; onClicked: root.focusNewGroup() }
                        }
                        RowLayout {
                            visible: !root.wide
                            Layout.fillWidth: true
                            spacing: Style.space(10)
                            NewGroupField { id: newGroupNarrow }
                        }
                        Scroll {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Style.space(2)
                            RowLayout {
                                visible: root.wide
                                Layout.fillWidth: true
                                spacing: Style.space(10)
                                ColumnHead { Layout.leftMargin: Style.space(14); Layout.preferredWidth: Style.space(250); Layout.fillWidth: false; label: root.t("Group") }
                                ColumnHead { label: root.t("Hosts") }
                            }
                            Rule { visible: root.wide }
                            Rule { visible: !root.wide; title: root.t("All groups") }
                            Repeater {
                                model: root.profiles.groups
                                GroupRow {}
                            }
                            RowLayout {
                                visible: root.wide
                                Layout.fillWidth: true
                                Layout.topMargin: Style.space(10)
                                Layout.leftMargin: Style.space(14)
                                spacing: Style.space(14)
                                NewGroupField { id: newGroupWide; Layout.preferredWidth: Style.space(250); Layout.fillWidth: false }
                                Caption { text: "↵ " + root.t("adds to the end of the list") }
                            }
                        }
                        Rule {}
                        Flow {
                            Layout.fillWidth: true
                            spacing: Style.space(18)
                            InfoLine { width: implicitWidth; Layout.fillWidth: false; iconText: "󰌾"; text: root.t("Only empty groups can be deleted") }
                            InfoLine { width: implicitWidth; Layout.fillWidth: false; iconText: "󰌨"; text: root.t("The last group always stays") }
                            InfoLine { visible: root.wide; width: implicitWidth; Layout.fillWidth: false; iconText: "󰳽"; text: root.t("Click a group to highlight its hosts") }
                        }
                    }

                    // ---- script editor
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.page === "scriptEditor"
                        spacing: Style.space(12)
                        PageHeader {
                            title: root.t(root.scriptId ? "Edit script" : "Add script")
                            subtitle: (root.deviceById(root.scriptHostId) || {name: ""}).name + " · " + root.t("runs over SSH stdin")
                        }
                        Scroll {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Style.space(12)
                            enabled: !root.busy
                            FieldBlock {
                                label: root.t("Script name")
                                Field { id: scriptNameField; placeholderText: root.t("For example, deploy-prod"); maximumLength: 100 }
                            }
                            FieldBlock {
                                label: root.t("Script content")
                                Controls.ScrollView {
                                    id: scriptContentScroll
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Style.space(180)
                                    clip: true
                                    contentWidth: availableWidth
                                    contentHeight: Math.max(height, scriptContentField.contentHeight
                                                            + scriptContentField.topPadding + scriptContentField.bottomPadding)
                                    Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
                                    Controls.ScrollBar.vertical.policy: Controls.ScrollBar.AsNeeded
                                    background: Ui.BorderSurface {
                                        color: Style.controlFill(scriptContentField.activeFocus, false, Color.foreground, Color.accent)
                                        borderSpec: Border.controlSpec(scriptContentField.activeFocus ? "focus" : "normal", Color.foreground, Color.accent)
                                        radius: Style.cornerRadius
                                    }
                                    Controls.TextArea {
                                        id: scriptContentField
                                        width: scriptContentScroll.availableWidth
                                        height: scriptContentScroll.contentHeight
                                        wrapMode: TextEdit.Wrap
                                        color: Color.foreground
                                        selectionColor: Style.selectionFillFor(Color.foreground, Color.accent)
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.body
                                        readOnly: root.scriptFromFile || !root.scriptContentLoaded
                                        placeholderText: root.scriptContentLoaded ? "#!/usr/bin/env bash\n# " + root.t("Commands run on the host after connecting")
                                                                                   : root.t("Loading script content…")
                                        placeholderTextColor: root.faintText
                                        background: null
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.space(10)
                                Action {
                                    text: root.t("Choose .sh file")
                                    iconText: "󰉋"
                                    bordered: true
                                    onClicked: { root.selectedScriptFile = ""; root.call({op: "browseScripts", folder: ""}); root.page = "scriptFiles" }
                                }
                                Caption {
                                    visible: root.scriptFilePath !== "" || root.scriptSavedPath !== ""
                                    text: root.scriptFilePath || root.scriptSavedPath
                                    elide: Text.ElideMiddle
                                    wrapMode: Text.NoWrap
                                    layer.enabled: root.addressesHidden && visible
                                    layer.effect: PrivacyBlur {}
                                }
                            }
                            InfoLine { iconText: "󰒃"; text: root.t("The local script is copied privately and sent to the host through SSH stdin when run. Do not include passwords.") }
                            Action {
                                visible: root.scriptId !== ""
                                Layout.topMargin: Style.space(6)
                                text: root.t("Delete script")
                                iconText: "󰆴"
                                bordered: true
                                foreground: Color.urgent
                                onClicked: root.requestConfirm("deleteScript", root.scriptId)
                            }
                        }
                        Footer {
                            Action { text: root.t("Cancel"); onClicked: root.navigateBack() }
                            Primary {
                                iconText: "󰄬"
                                text: root.t(root.scriptId ? "Save" : "Add script")
                                enabled: !root.busy && root.scriptContentLoaded && scriptNameField.text.trim() !== ""
                                         && (root.scriptId !== "" || root.scriptFilePath !== "" || scriptContentField.text.trim() !== "")
                                onClicked: root.saveScript()
                            }
                        }
                    }

                    // ---- script file chooser
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.page === "scriptFiles"
                        spacing: Style.space(12)
                        PageHeader {
                            title: root.t("Choose script file")
                            subtitle: root.t("Only executable .sh files")
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(8)
                            IconAction {
                                iconText: "󰁝"
                                enabled: root.scriptBrowser.parent !== "" && !root.busy
                                tooltipText: root.t("Parent folder")
                                onClicked: root.call({op: "browseScripts", folder: root.scriptBrowser.parent})
                            }
                            Label {
                                text: root.scriptBrowser.folder
                                elide: Text.ElideMiddle
                                wrapMode: Text.NoWrap
                                layer.enabled: root.addressesHidden && visible
                                layer.effect: PrivacyBlur {}
                            }
                            Segmented {
                                value: root.scriptsOnly ? "sh" : "all"
                                options: [{value: "sh", label: "*.sh"}, {value: "all", label: root.t("All files")}]
                                onChanged: function(v) { root.scriptsOnly = v === "sh" }
                            }
                        }
                        Rule {}
                        Scroll {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Style.space(2)
                            enabled: !root.busy
                            Repeater {
                                model: root.scriptBrowser.files.filter(function(f) { return f.directory || !root.scriptsOnly || f.selectable })
                                Ui.CursorSurface {
                                    id: fileRow
                                    required property var modelData
                                    readonly property string path: root.scriptBrowser.folder + "/" + modelData.name
                                    readonly property bool usable: modelData.directory || modelData.selectable
                                    Layout.fillWidth: true
                                    implicitHeight: Style.space(34)
                                    hasCursor: fileMouse.containsMouse && usable
                                    current: root.selectedScriptFile === path
                                    opacity: usable ? 1 : 0.5
                                    MouseArea {
                                        id: fileMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: fileRow.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (fileRow.modelData.directory) root.call({op: "browseScripts", folder: fileRow.path})
                                            else if (fileRow.usable) root.selectedScriptFile = fileRow.path
                                        }
                                        onDoubleClicked: if (!fileRow.modelData.directory && fileRow.usable) { root.selectedScriptFile = fileRow.path; root.openScriptFile() }
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Style.space(10)
                                        anchors.rightMargin: Style.space(10)
                                        spacing: Style.space(10)
                                        Caption { Layout.fillWidth: false; text: fileRow.modelData.directory ? "󰉋" : "󰈙"; font.pixelSize: Style.font.body }
                                        Label { text: fileRow.modelData.name + (fileRow.modelData.directory ? "/" : ""); wrapMode: Text.NoWrap; elide: Text.ElideMiddle }
                                        Caption { Layout.fillWidth: false; visible: !fileRow.modelData.directory; text: fileRow.modelData.size + " B"; wrapMode: Text.NoWrap }
                                        Radio { visible: !fileRow.modelData.directory; checked: fileRow.current }
                                    }
                                }
                            }
                        }
                        Footer {
                            status: root.t("Files are copied locally, then run on the host.")
                            Action { text: root.t("Cancel"); onClicked: root.navigateBack() }
                            Primary { iconText: "󰈔"; text: root.t("Open"); enabled: root.selectedScriptFile !== "" && !scriptPreview.running; onClicked: root.openScriptFile() }
                        }
                    }
                }
            }

            // Toasts sit bottom-right of the detail pane in the wide layout and
            // above the footer of full-panel pages in the narrow one; the
            // narrow host list stacks them above its dock instead.
            ToastStack {
                visible: root.toasts.length > 0 && (root.wide || root.page !== "list")
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(root.hostDeleteId !== "" ? 130 : 60)
                width: root.wide ? Math.min(Style.space(360), parent.width / 2) : parent.width
                z: 10
            }

            // Context menu: right-click on a row, or ⋯ in the dock / detail.
            Item {
                anchors.fill: parent
                visible: root.menuHostId !== ""
                z: 15
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: root.menuHostId = ""
                }
                ContextMenu {
                    x: Math.max(0, Math.min(root.menuX, parent.width - width))
                    y: Math.max(0, Math.min(root.menuY, parent.height - height))
                }
            }

            Ui.ConfirmDialog {
                id: deleteConfirm
                anchors.fill: parent
                z: 20
                opened: root.confirmKind !== ""
                message: root.confirmKind === "discardDraft" ? root.t("Leave without saving and discard the draft?")
                    : root.t("Delete this saved script?")
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
                    else if (kind === "deleteScript") root.call({op: kind, id: root.scriptHostId, scriptId: targetId})
                }
            }
        }
    }

    function exportSampleText() {
        var preview = exportPreview
        if (!preview || !preview.sample) return "{ \"version\": 1, \"groups\": [], \"devices\": [] }"
        var d = preview.sample
        var lines = ["{ \"version\": 1,", "  \"groups\": [ …" + preview.groups + " ],", "  \"devices\": [{"]
        var keys = ["name", "host", "port", "login", "auth", "agents", "note", "keyPath", "agentFolder", "remoteFolder"]
        for (var i = 0; i < keys.length; i++) {
            var value = d[keys[i]]
            if ((keys[i] === "note" || keys[i].indexOf("Path") > 0 || keys[i].indexOf("Folder") > 0) && value === "") continue
            var shown = JSON.stringify(value)
            if (shown.length > 42) shown = shown.slice(0, 40) + "…\""
            lines.push("    \"" + keys[i] + "\": " + shown + ",")
        }
        lines.push("  }, …" + Math.max(0, preview.hosts - 1) + " ] }")
        return lines.join("\n")
    }

    // --- visual building blocks -------------------------------------------------

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
            background: root.popupSurface
            onChanged: function(v) { choice.changed(v) }
        }
    }
    component Action: Ui.Button {
        focusable: true
        bordered: false
        iconSize: Style.font.body
        opacity: enabled ? 1 : 0.45
        onActiveFocusChanged: if (activeFocus) root.ensureVisible(this)
    }
    // Small icon button; `spinning` swaps the glyph for a spinner, `active`
    // keeps the selected fill (a toggled view or a running refresh).
    component IconAction: Ui.PanelActionButton {
        id: iconAction
        property bool spinning: false
        property bool active: false
        size: Style.space(30)
        focusable: true
        opacity: enabled ? 1 : 0.45
        color: active ? Style.selectedFillFor(Color.foreground, Color.accent) : (_showFocusRing ? Style.focusFillFor(hoverColor, hoverColor) : _hot ? Style.hoverFillFor(hoverColor, hoverColor) : "transparent")
        Spinner { visible: iconAction.spinning; anchors.centerIn: parent; color: Color.foreground; font.pixelSize: Style.font.icon }
    }
    // Accent-filled primary button: one per screen, the action ↵ triggers.
    component Primary: Rectangle {
        id: primary
        property string text: ""
        property string iconText: ""
        property string tooltipText: ""
        property bool compact: false
        property color fillColor: Color.accent
        signal clicked()
        activeFocusOnTab: true
        implicitHeight: primaryRow.implicitHeight + Style.space(compact ? 10 : 16)
        implicitWidth: primaryRow.implicitWidth + Style.space(compact ? 20 : 28)
        radius: Style.cornerRadius
        color: !enabled ? Qt.rgba(fillColor.r, fillColor.g, fillColor.b, 0.35)
             : primaryMouse.pressed ? Qt.darker(fillColor, 1.15)
             : primaryMouse.containsMouse || activeFocus ? Qt.lighter(fillColor, 1.1) : fillColor
        border.width: activeFocus ? 1 : 0
        border.color: Color.foreground
        Keys.onReturnPressed: if (enabled) clicked()
        Keys.onEnterPressed: if (enabled) clicked()
        Keys.onSpacePressed: if (enabled) clicked()
        Row {
            id: primaryRow
            anchors.centerIn: parent
            spacing: Style.space(8)
            Text {
                visible: primary.iconText !== ""
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: primary.iconText
                color: Qt.rgba(root.popupSurface.r, root.popupSurface.g, root.popupSurface.b, primary.enabled ? 1 : 0.7)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }
            Text {
                visible: primary.text !== ""
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: primary.text
                color: Qt.rgba(root.popupSurface.r, root.popupSurface.g, root.popupSurface.b, primary.enabled ? 1 : 0.7)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
            }
        }
        MouseArea {
            id: primaryMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: primary.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: primary.clicked()
        }
        Ui.PanelToolTip { visible: primary.tooltipText !== "" && primaryMouse.containsMouse; text: primary.tooltipText }
    }
    component PrivacyButton: IconAction {
        iconText: root.addressesHidden ? "󰈉" : "󰈈"
        foreground: root.addressesHidden ? Color.accent : Color.foreground
        tooltipText: root.t(root.addressesHidden ? "Show logins and addresses" : "Hide logins and addresses")
        onClicked: State.PrivacyState.addressesHidden = !State.PrivacyState.addressesHidden
    }
    component Spinner: Text {
        id: spinner
        textFormat: Text.PlainText
        text: "󰑓"
        color: root.secondaryText
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        RotationAnimation on rotation { running: spinner.visible; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
    }
    component StatusDot: Item {
        id: dot
        property string kind: "unknown"
        implicitWidth: Style.space(10)
        implicitHeight: Style.space(10)
        Layout.alignment: Qt.AlignVCenter
        Rectangle {
            visible: dot.kind !== "pending"
            anchors.centerIn: parent
            width: Style.space(7)
            height: width
            radius: width / 2
            color: dot.kind === "unknown" ? "transparent" : root.statusDotColor(dot.kind)
            border.width: dot.kind === "unknown" ? 1 : 0
            border.color: root.secondaryText
        }
        Spinner { visible: dot.kind === "pending"; anchors.centerIn: parent }
    }
    component Rule: RowLayout {
        id: ruleRow
        property string title: ""
        property string trailing: ""
        Layout.fillWidth: true
        spacing: Style.space(10)
        Text {
            visible: ruleRow.title !== ""
            textFormat: Text.PlainText
            text: ruleRow.title.toUpperCase()
            color: root.secondaryText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.6
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: root.rule }
        Text {
            visible: ruleRow.trailing !== ""
            textFormat: Text.PlainText
            text: ruleRow.trailing
            color: root.faintText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }
    }
    component ColumnHead: Caption {
        property string label: ""
        Layout.fillWidth: true
        text: label.toUpperCase()
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
        font.bold: true
        font.letterSpacing: 1.6
    }
    component Scroll: Flickable {
        id: scroll
        default property alias body: scrollColumn.data
        property alias spacing: scrollColumn.spacing
        clip: true
        contentWidth: width
        contentHeight: scrollColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        implicitHeight: scrollColumn.implicitHeight
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: scroll.contentHeight > scroll.height ? Controls.ScrollBar.AsNeeded : Controls.ScrollBar.AlwaysOff }
        ColumnLayout {
            id: scrollColumn
            width: scroll.width - Style.space(8)
            spacing: Style.space(10)
        }
    }
    component Tinted: Rectangle {
        default property alias body: tintedColumn.data
        property color tone: root.tint
        Layout.fillWidth: true
        implicitHeight: tintedColumn.implicitHeight + Style.space(20)
        color: tone
        radius: Style.cornerRadius
        ColumnLayout {
            id: tintedColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
        }
    }
    // Inline status block with a left accent bar: error, warning, success, info.
    component Notice: Rectangle {
        id: notice
        property string kind: "info"
        property string iconText: kind === "error" ? "󰀦" : kind === "success" ? "󰄬" : "󰋼"
        property string title: ""
        property string text: ""
        property bool stacked: false
        default property alias trailing: noticeTrailing.data
        readonly property color tone: kind === "error" ? Color.urgent : kind === "success" ? Color.foreground : Color.accent
        Layout.fillWidth: true
        implicitHeight: noticeRow.implicitHeight + Style.space(title !== "" ? 26 : 18)
        color: kind === "error" ? root.urgentTint : root.tint
        radius: Style.cornerRadius
        Rectangle { width: Style.space(2); height: parent.height; color: notice.tone; opacity: 0.8 }
        GridLayout {
            id: noticeRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(16)
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            columns: notice.stacked ? 2 : 3
            columnSpacing: Style.space(12)
            rowSpacing: Style.space(10)
            Text {
                Layout.alignment: Qt.AlignTop
                textFormat: Text.PlainText
                text: notice.iconText
                color: notice.tone
                font.family: Style.font.family
                font.pixelSize: Style.font.title
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(4)
                Label { visible: notice.title !== ""; text: notice.title; font.bold: true }
                Label {
                    visible: notice.text !== ""
                    text: notice.text
                    color: notice.title !== "" ? root.secondaryText : (notice.kind === "error" ? Color.urgent : Color.foreground)
                    font.pixelSize: notice.title !== "" ? Style.font.caption : Style.font.bodySmall
                    lineHeight: 1.3
                }
            }
            RowLayout {
                id: noticeTrailing
                visible: children.length > 0
                Layout.fillWidth: false
                Layout.column: notice.stacked ? 1 : 2
                Layout.row: notice.stacked ? 1 : 0
                Layout.alignment: notice.stacked ? Qt.AlignRight : Qt.AlignVCenter
                spacing: Style.space(6)
            }
        }
    }
    component InfoLine: RowLayout {
        id: infoLine
        property string iconText: "󰋼"
        property string text: ""
        Layout.fillWidth: true
        spacing: Style.space(10)
        Caption { Layout.fillWidth: false; Layout.alignment: Qt.AlignTop; text: infoLine.iconText; font.pixelSize: Style.font.body }
        Caption { text: infoLine.text; lineHeight: 1.3 }
    }
    component FieldBlock: ColumnLayout {
        id: fieldBlock
        property string label: ""
        property string hint: ""
        default property alias body: fieldBody.data
        Layout.fillWidth: true
        spacing: Style.space(4)
        Caption { text: fieldBlock.label; font.pixelSize: Style.font.bodySmall }
        ColumnLayout { id: fieldBody; Layout.fillWidth: true; spacing: Style.space(4) }
        Caption { visible: fieldBlock.hint !== ""; text: fieldBlock.hint }
    }
    // Equal-width "pick one of N" built from the kit's ButtonGroup chips.
    component Segmented: Ui.ButtonGroup {
        spacing: 0
        background: root.tint
    }
    component Tab: Item {
        id: tab
        property string text: ""
        property string iconText: ""
        property int count: -1
        property bool selected: false
        signal clicked()
        implicitWidth: tabRow.implicitWidth
        implicitHeight: tabRow.implicitHeight + Style.space(10)
        Row {
            id: tabRow
            spacing: Style.space(6)
            Text {
                visible: tab.iconText !== ""
                textFormat: Text.PlainText
                text: tab.iconText
                color: tab.selected ? Color.foreground : root.secondaryText
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }
            Text {
                textFormat: Text.PlainText
                text: tab.text
                color: tab.selected || tabMouse.containsMouse ? Color.foreground : root.secondaryText
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: tab.selected
            }
            Text {
                visible: tab.count >= 0
                textFormat: Text.PlainText
                text: String(tab.count)
                color: root.faintText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                anchors.baseline: parent.children[1].baseline
            }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Style.space(2)
            color: Color.accent
            visible: tab.selected
        }
        MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tab.clicked() }
    }
    component SearchBox: Rectangle {
        id: box
        property alias field: input
        implicitHeight: Style.space(root.wide ? 36 : 42)
        color: root.tint
        radius: Style.cornerRadius
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: input.activeFocus ? Color.accent : root.rule
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(10)
            Text { textFormat: Text.PlainText; text: "󰍉"; color: input.activeFocus ? Color.accent : root.secondaryText; font.family: Style.font.family; font.pixelSize: Style.font.title }
            TextInput {
                id: input
                Layout.fillWidth: true
                text: root.query
                color: Color.foreground
                selectionColor: Style.selectionFillFor(Color.foreground, Color.accent)
                selectedTextColor: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                clip: true
                onTextEdited: root.query = text
                Text {
                    visible: input.text === ""
                    textFormat: Text.PlainText
                    text: root.wide ? root.t("Search") : root.t("Connect to… name, address, group")
                    color: root.faintText
                    font: input.font
                    elide: Text.ElideRight
                    width: input.width
                }
                Keys.onPressed: function(event) {
                    var key = event.key
                    if (key === Qt.Key_Down || key === Qt.Key_Up) {
                        root.moveSelection(key === Qt.Key_Down ? 1 : -1)
                        pageFrame.forceActiveFocus()
                        event.accepted = true
                    } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                        if (root.current) root.launchDevice(root.current.id)
                        event.accepted = true
                    } else if (key === Qt.Key_Escape) {
                        if (root.query !== "") root.query = ""
                        else root.close()
                        event.accepted = true
                    } else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
                        if (root.wide) { root.detailZone = root.current !== null; pageFrame.forceActiveFocus() }
                        else root.nextTab(key === Qt.Key_Backtab ? -1 : 1)
                        event.accepted = true
                    }
                }
            }
            IconAction {
                visible: root.query !== ""
                iconText: "󰅖"
                size: Style.space(24)
                focusable: false
                tooltipText: root.t("Clear")
                onClicked: { root.query = ""; input.forceActiveFocus() }
            }
            KeyHint { visible: root.query === ""; text: "/" }
        }
        MouseArea { anchors.fill: parent; z: -1; onClicked: input.forceActiveFocus() }
    }
    component KeyHint: Rectangle {
        id: keyHint
        property string text: ""
        property color tone: root.secondaryText
        implicitWidth: Math.max(implicitHeight, keyText.implicitWidth + Style.space(10))
        implicitHeight: keyText.implicitHeight + Style.space(4)
        color: root.tint
        radius: Style.cornerRadius
        Text {
            id: keyText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: keyHint.text
            color: keyHint.tone
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }
    }
    component ProgressLine: Item {
        implicitHeight: Style.space(2)
        Rectangle { anchors.fill: parent; color: root.rule }
        Rectangle {
            height: parent.height
            width: parent.width * (root.checkTotal > 0 ? root.checkDone / root.checkTotal : 0)
            color: Color.accent
            Behavior on width { NumberAnimation { duration: 200 } }
        }
    }
    component SectionTitle: RowLayout {
        id: sectionTitle
        property string text: ""
        property int count: -1
        property bool collapsible: false
        property bool collapsed: false
        signal toggled()
        Layout.fillWidth: true
        Layout.bottomMargin: Style.space(2)
        spacing: Style.space(8)
        Text {
            textFormat: Text.PlainText
            text: sectionTitle.text.toUpperCase()
            color: root.secondaryText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.6
            MouseArea { anchors.fill: parent; enabled: sectionTitle.collapsible; cursorShape: Qt.PointingHandCursor; onClicked: sectionTitle.toggled() }
        }
        Rectangle { visible: sectionTitle.collapsible; Layout.fillWidth: true; implicitHeight: 1; color: root.rule }
        Item { visible: !sectionTitle.collapsible; Layout.fillWidth: true }
        Text {
            visible: sectionTitle.count >= 0
            textFormat: Text.PlainText
            text: sectionTitle.collapsed ? "󰅂 " + sectionTitle.count : String(sectionTitle.count)
            color: root.faintText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            MouseArea { anchors.fill: parent; enabled: sectionTitle.collapsible; cursorShape: Qt.PointingHandCursor; onClicked: sectionTitle.toggled() }
        }
    }
    component EmptyState: ColumnLayout {
        id: empty
        property string iconText: ""
        property string title: ""
        property string body: ""
        default property alias actions: emptyActions.data
        Layout.fillWidth: true
        spacing: Style.space(12)
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Style.space(44)
            implicitHeight: Style.space(44)
            color: root.tint
            Text { anchors.centerIn: parent; textFormat: Text.PlainText; text: empty.iconText; color: root.secondaryText; font.family: Style.font.family; font.pixelSize: Style.font.iconLarge }
        }
        Label { visible: empty.title !== ""; text: empty.title; font.bold: true; font.pixelSize: Style.font.title; horizontalAlignment: Text.AlignHCenter }
        Caption { visible: empty.body !== ""; text: empty.body; font.pixelSize: Style.font.bodySmall; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.3 }
        ColumnLayout { id: emptyActions; Layout.fillWidth: true; spacing: Style.space(10) }
    }
    // One host in the list. Mouse hover and the keyboard cursor share one
    // visual; the selected row adds a 2 px accent bar.
    component HostRow: Ui.CursorSurface {
        id: hostRow
        property string rowKey: ""
        property var device: null
        property bool showPin: false
        readonly property bool selectedRow: root.currentKey === rowKey
        readonly property var status: root.rowStatus(device)
        readonly property string kind: root.statusKind(device)
        readonly property bool highlighted: root.highlightGroupId !== "" && device && device.group === root.highlightGroupId
        visible: device !== null
        Layout.fillWidth: true
        implicitHeight: root.wide ? Style.space(48) : Style.space(36)
        hasCursor: rowMouse.containsMouse && !selectedRow
        current: selectedRow || highlighted
        currentFill: Style.hoverFillFor(Color.foreground, Color.accent)
        opacity: kind === "offline" || kind === "error" ? 0.7 : 1
        onSelectedRowChanged: if (selectedRow) root.ensureVisible(hostRow)
        Rectangle {
            visible: hostRow.selectedRow
            width: Style.space(2)
            height: parent.height
            color: Color.accent
        }
        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                root.select(hostRow.rowKey)
                if (mouse.button === Qt.RightButton) {
                    var p = hostRow.mapToItem(pageFrame, mouse.x, mouse.y)
                    root.openMenu(hostRow.device, p.x, p.y, true)
                } else {
                    root.detailZone = false
                    pageFrame.forceActiveFocus()
                }
            }
            onDoubleClicked: function(mouse) { if (mouse.button === Qt.LeftButton) root.launchDevice(hostRow.device.id) }
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(10)
            StatusDot {
                kind: hostRow.kind
                HoverHandler { id: dotHover }
                Ui.PanelToolTip { visible: dotHover.hovered; text: root.statusDetails(hostRow.device) }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 1 : 2
                rowSpacing: Style.space(2)
                columnSpacing: Style.space(12)
                Text {
                    textFormat: Text.StyledText
                    text: hostRow.device ? root.highlight(hostRow.device.name, Color.accent) : ""
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.maximumWidth: root.wide ? -1 : Style.space(180)
                    Layout.fillWidth: root.wide
                }
                Text {
                    textFormat: Text.StyledText
                    text: root.highlight(root.wide ? root.endpointPort(hostRow.device) : root.endpointText(hostRow.device), Color.accent)
                    color: root.faintText
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                    layer.enabled: root.addressesHidden && visible
                    layer.effect: PrivacyBlur {}
                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.wide
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.select(hostRow.rowKey); root.copyEndpoint(hostRow.device) }
                    }
                }
            }
            Text {
                visible: hostRow.device !== null && hostRow.device.pinned && hostRow.showPin
                textFormat: Text.PlainText
                text: "󰐃"
                color: root.faintText
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }
            Spinner { visible: hostRow.status.spinner === true }
            Text {
                visible: hostRow.status.spinner !== true
                textFormat: Text.PlainText
                text: hostRow.status.text
                color: hostRow.status.color
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }
        }
    }
    component DraftRow: Ui.CursorSurface {
        Layout.fillWidth: true
        Layout.bottomMargin: Style.space(4)
        implicitHeight: Style.space(48)
        hasCursor: draftMouse.containsMouse
        current: true
        currentFill: Style.hoverFillFor(Color.foreground, Color.accent)
        Rectangle { width: Style.space(2); height: parent.height; color: Color.accent }
        MouseArea { id: draftMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.loadDraft(); root.page = "device"; root.restoreDraftFocus() } }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            spacing: Style.space(12)
            Caption { Layout.fillWidth: false; text: "󰐕"; font.pixelSize: Style.font.body }
            ColumnLayout {
                spacing: Style.space(2)
                Label { text: State.DraftState.name || root.t("New host"); font.bold: true; wrapMode: Text.NoWrap; elide: Text.ElideRight }
                Caption { text: root.t("draft · not saved") }
            }
        }
    }
    // Large launch target: icon over label in the narrow dock, icon beside
    // title + subtitle in the wide detail pane.
    component LaunchTile: Rectangle {
        id: tile
        property string target: ""
        property string iconText: ""
        property string title: ""
        property string subtitle: ""
        property string keyText: ""
        property bool primary: false
        property bool disabledReasonShown: false
        property string tooltipText: ""
        readonly property bool launching: root.busy && root.launchTarget === target && root.current && root.launchHostId === root.current.id
        readonly property bool cursor: root.wide && root.detailZone && root.detailTargetIndex(target) === root.detailCursor
        readonly property color ink: primary && enabled ? root.popupSurface : Color.foreground
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: root.wide ? Style.space(56) : Style.space(70)
        radius: Style.cornerRadius
        opacity: enabled ? 1 : 0.45
        color: primary && enabled ? (tileMouse.containsMouse || cursor ? Qt.lighter(Color.accent, 1.1) : Color.accent)
             : tileMouse.containsMouse || cursor ? Style.hoverFillFor(Color.foreground, Color.accent) : root.tint
        border.width: primary && enabled && !cursor ? 0 : 1
        border.color: cursor ? Color.accent : root.rule
        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: tile.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (tile.enabled && !root.busy) tile.clicked()
        }
        Ui.PanelToolTip { visible: tile.tooltipText !== "" && tileMouse.containsMouse; text: tile.tooltipText }
        ColumnLayout {
            visible: !root.wide
            anchors.centerIn: parent
            width: parent.width - Style.space(8)
            spacing: Style.space(4)
            Text {
                visible: !tile.launching
                Layout.alignment: Qt.AlignHCenter
                textFormat: Text.PlainText
                text: tile.iconText
                color: tile.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge
            }
            Spinner { visible: tile.launching; Layout.alignment: Qt.AlignHCenter; color: tile.ink; font.pixelSize: Style.font.iconLarge }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: parent.width
                textFormat: Text.PlainText
                text: tile.launching ? root.t("Opening…") : tile.title
                color: tile.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                textFormat: Text.PlainText
                text: tile.keyText
                color: Qt.rgba(tile.ink.r, tile.ink.g, tile.ink.b, 0.55)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }
        }
        RowLayout {
            visible: root.wide
            anchors.fill: parent
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(12)
            Text {
                visible: !tile.launching
                textFormat: Text.PlainText
                text: tile.iconText
                color: tile.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge
            }
            Spinner { visible: tile.launching; color: tile.ink; font.pixelSize: Style.font.iconLarge }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: tile.launching ? root.t("Opening…") : tile.title
                    color: tile.ink
                    font.family: Style.font.family
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: tile.subtitle
                    color: Qt.rgba(tile.ink.r, tile.ink.g, tile.ink.b, 0.7)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                }
            }
            KeyHint { text: tile.keyText; tone: tile.ink; color: tile.primary && tile.enabled ? Qt.rgba(0, 0, 0, 0.18) : root.tint }
        }
    }
    component Chip: Ui.Button {
        bordered: true
        focusable: false
        iconSize: Style.font.body
        fontSize: Style.font.bodySmall
        opacity: enabled ? 1 : 0.45
    }
    component PickerRow: Ui.CursorSurface {
        id: pickerRow
        property int number: 0
        property string iconText: ""
        property string text: ""
        property string detail: ""
        property bool cursor: false
        property bool spinning: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: Style.space(34)
        hasCursor: pickerMouse.containsMouse && !cursor
        current: cursor
        currentFill: Style.hoverFillFor(Color.foreground, Color.accent)
        Rectangle { visible: pickerRow.cursor; width: Style.space(2); height: parent.height; color: Color.accent }
        MouseArea { id: pickerMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pickerRow.clicked() }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(12)
            KeyHint { visible: pickerRow.number > 0; text: String(pickerRow.number); tone: Color.foreground }
            Text { textFormat: Text.PlainText; text: pickerRow.iconText; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.title }
            Label { text: pickerRow.text; font.bold: true; wrapMode: Text.NoWrap; elide: Text.ElideRight }
            Caption {
                Layout.fillWidth: false
                Layout.maximumWidth: Style.space(220)
                text: pickerRow.detail
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                layer.enabled: root.addressesHidden && visible
                layer.effect: PrivacyBlur {}
            }
            Spinner { visible: pickerRow.spinning }
        }
    }
    // Narrow layout: the selected host and every way to act on it.
    component Dock: ColumnLayout {
        id: dock
        readonly property var d: root.current
        readonly property bool down: d !== null && root.unreachable(d)
        Layout.fillWidth: true
        spacing: Style.space(10)
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: -panel.padding
            Layout.rightMargin: -panel.padding
            implicitHeight: 1
            color: root.dockMode === "delete" || dock.down ? Color.urgent : Color.accent
            opacity: 0.6
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(10)
            StatusDot { kind: root.statusKind(dock.d) }
            Text {
                textFormat: Text.PlainText
                text: dock.d ? dock.d.name : ""
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                Layout.maximumWidth: Style.space(170)
            }
            Caption {
                text: root.endpointPort(dock.d)
                wrapMode: Text.NoWrap
                elide: Text.ElideMiddle
                layer.enabled: root.addressesHidden && visible
                layer.effect: PrivacyBlur {}
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.copyEndpoint(dock.d) }
            }
            IconAction { iconText: "󰏫"; tooltipText: root.t("Edit host") + "  E"; onClicked: root.editDevice(dock.d) }
            IconAction {
                id: moreButton
                iconText: "󰇘"
                active: root.menuHostId !== "" && !root.menuFull
                tooltipText: root.t("More")
                onClicked: {
                    var p = moreButton.mapToItem(pageFrame, moreButton.width, 0)
                    root.openMenu(dock.d, p.x - Style.space(260), p.y - Style.space(290), false)
                }
            }
        }
        Notice {
            visible: root.dockMode === "delete"
            kind: "error"
            iconText: "󰆴"
            title: dock.d ? root.t("Delete %1 from Remote Hosts?").arg(dock.d.name) : ""
            text: dock.d ? root.deleteConsequence(dock.d) : ""
        }
        RowLayout {
            visible: root.dockMode === "delete"
            Layout.fillWidth: true
            spacing: Style.space(10)
            Item { Layout.fillWidth: true }
            Action { text: root.t("Keep") + "   Esc"; bordered: true; onClicked: { root.hostDeleteId = ""; root.dockMode = "" } }
            Primary { iconText: "󰆴"; text: root.t("Delete") + "   ↵"; fillColor: Color.urgent; enabled: !root.busy; onClicked: root.confirmHostDelete() }
        }
        Notice {
            visible: dock.down && root.dockMode !== "delete"
            kind: "error"
            iconText: "󰖪"
            title: dock.d ? root.t("%1 · SSH port %2").arg(root.pingText(dock.d)).arg(root.portText(dock.d)) : ""
            text: dock.d ? root.t("%1. You can still try to connect.").arg(root.checkAge(dock.d)) : ""
            Action { iconText: "󰑐"; text: root.t("Retry"); bordered: true; onClicked: root.refreshDevice(dock.d) }
        }
        RowLayout {
            visible: root.dockMode !== "delete"
            Layout.fillWidth: true
            spacing: Style.space(8)
            LaunchTile {
                target: "ssh"; iconText: "󰆍"; keyText: "↵"; primary: !dock.down
                title: dock.down ? root.t("SSH anyway") : "SSH"
                tooltipText: root.t("Connect in %1").arg(root.terminalName)
                onClicked: root.launchDevice(dock.d.id)
            }
            LaunchTile {
                target: "sftp"; iconText: "󰉋"; keyText: "F"; title: root.t("Files")
                enabled: dock.d !== null && root.matchingSftpState(dock.d) !== "foreign"
                tooltipText: dock.d && root.matchingSftpState(dock.d) === "mounted" ? root.t("Open mounted SFTP") : root.t("Mount SFTP using SSHFS")
                onClicked: root.launchDevice(dock.d.id, "sftp")
            }
            LaunchTile {
                target: "vscode"; iconText: "󰨞"; keyText: "C"; title: "VS Code"
                enabled: dock.d !== null && dock.d.auth === "agent"
                tooltipText: root.t("VS Code needs a key or SSH agent: Remote-SSH cannot use a saved password.")
                onClicked: root.launchDevice(dock.d.id, "vscode")
            }
            LaunchTile { target: "copy"; iconText: "󰆏"; keyText: "Y"; title: root.t("Copy"); onClicked: root.copyEndpoint(dock.d) }
        }
        ColumnLayout {
            visible: root.dockMode === "ai" && dock.d !== null
            Layout.fillWidth: true
            spacing: Style.space(2)
            Rule { title: root.t("Open AI CLI"); trailing: (dock.d && dock.d.agentFolder ? dock.d.agentFolder : "~") + " · " + root.t("Esc closes") }
            Repeater {
                model: dock.d ? dock.d.agents : []
                PickerRow {
                    required property string modelData
                    required property int index
                    number: index + 1
                    iconText: root.agentIcon(modelData)
                    text: root.agentLabel(modelData)
                    detail: "ssh → " + root.agentCommand(modelData)
                    cursor: root.dockCursor === index
                    spinning: root.busy && root.launchTarget === "agent:" + modelData
                    onClicked: { root.launchAgent(dock.d.id, modelData); root.dockMode = "" }
                }
            }
            RowLayout {
                visible: root.hostScripts(dock.d).length > 0
                Layout.fillWidth: true
                Layout.topMargin: Style.space(4)
                spacing: Style.space(10)
                Caption { Layout.fillWidth: false; text: "󰐊"; font.pixelSize: Style.font.body }
                Caption { text: root.t("Scripts: %1").arg(root.hostScripts(dock.d).map(function(s) { return s.name }).join(" · ")); wrapMode: Text.NoWrap; elide: Text.ElideRight }
                KeyHint { text: "S" }
            }
        }
        ColumnLayout {
            visible: root.dockMode === "scripts" && dock.d !== null
            Layout.fillWidth: true
            spacing: Style.space(2)
            Rule { title: root.t("Run script on %1").arg(dock.d ? dock.d.name : ""); trailing: root.t("Esc closes") }
            Repeater {
                model: root.hostScripts(dock.d)
                PickerRow {
                    required property var modelData
                    required property int index
                    number: index + 1
                    iconText: "󰐊"
                    text: modelData.name
                    detail: modelData.summary || ""
                    cursor: root.dockCursor === index
                    spinning: root.busy && root.launchTarget === "script:" + modelData.id
                    onClicked: { root.launchScript(dock.d.id, modelData); root.dockMode = "" }
                }
            }
            Caption { visible: root.hostScripts(dock.d).length === 0; text: root.t("No scripts yet. Scripts run over SSH stdin in your terminal.") }
            Action { iconText: "󰐕"; text: root.t("Add script"); onClicked: root.editScript(dock.d.id, null) }
        }
        RowLayout {
            visible: root.dockMode === ""
            Layout.fillWidth: true
            spacing: Style.space(8)
            Repeater {
                model: dock.d ? dock.d.agents.slice(0, 3) : []
                Chip {
                    required property string modelData
                    iconText: root.agentIcon(modelData)
                    text: root.agentLabel(modelData)
                    iconSpinning: root.busy && root.launchTarget === "agent:" + modelData
                    tooltipText: root.t("Connect and launch %1").arg(root.agentLabel(modelData))
                    onClicked: root.launchAgent(dock.d.id, modelData)
                }
            }
            Chip {
                visible: dock.d !== null && dock.d.agents.length > 3
                text: "+" + (dock.d ? dock.d.agents.length - 3 : 0)
                tooltipText: "AI CLI  A"
                onClicked: { root.dockMode = "ai"; root.dockCursor = 0 }
            }
            Rectangle { visible: dock.d !== null && dock.d.agents.length > 0; implicitWidth: 1; implicitHeight: Style.space(20); color: root.rule }
            Chip {
                iconText: "󰐊"
                text: root.t("Scripts") + " " + root.hostScripts(dock.d).length + "  ▾"
                onClicked: { root.dockMode = "scripts"; root.dockCursor = 0 }
            }
            Item { Layout.fillWidth: true }
        }
    }
    // Wide layout: everything about the selected host in the right pane.
    component Detail: Item {
        id: detail
        readonly property var d: root.current
        readonly property bool down: d !== null && root.unreachable(d)
        readonly property string mount: root.matchingSftpState(d)

        EmptyState {
            visible: root.loaded && root.profiles.devices.length === 0
            anchors.centerIn: parent
            width: Math.min(parent.width, Style.space(520))
            iconText: "󰒋"
            title: root.t("Add your first host")
            body: root.t("A server, NAS or another computer. Once added you get SSH, Files, VS Code, AI CLI and scripts here in one click.")
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: false
                spacing: Style.space(10)
                Primary { iconText: "󰐕"; text: root.t("Add host") + "   N"; onClicked: root.editDevice(null) }
                Action { iconText: "󰇚"; text: root.t("Import JSON"); bordered: true; onClicked: root.openTransfer("import") }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Style.space(30)
                spacing: Style.space(16)
                Repeater {
                    model: [[root.t("Address + login"), root.t("IPv4, IPv6 or domain")],
                            [root.t("Verify host key"), root.t("Compare fingerprints once")],
                            [root.t("Launch"), "SSH, " + root.t("Files") + ", VS Code, AI"]]
                    ColumnLayout {
                        id: stepColumn
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: Style.space(4)
                        Rectangle { Layout.fillWidth: true; implicitHeight: Style.space(2); color: root.rule }
                        Caption { Layout.topMargin: Style.space(8); text: String(stepColumn.index + 1); color: Color.accent; font.bold: true }
                        Label { text: stepColumn.modelData[0]; font.bold: true }
                        Caption { text: stepColumn.modelData[1] }
                    }
                }
            }
        }
        Caption {
            visible: root.loaded && root.profiles.devices.length > 0 && detail.d === null
            anchors.centerIn: parent
            width: implicitWidth
            Layout.fillWidth: false
            text: root.t("Select a host on the left")
        }

        ColumnLayout {
            visible: detail.d !== null
            anchors.fill: parent
            spacing: Style.space(14)
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(4)
                    RowLayout {
                        spacing: Style.space(12)
                        Text {
                            textFormat: Text.PlainText
                            text: detail.d ? detail.d.name : ""
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.display
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.maximumWidth: Style.space(360)
                        }
                        KeyHint { text: detail.d ? root.groupName(detail.d.group).toUpperCase() : ""; tone: root.secondaryText }
                        Text { visible: detail.d !== null && detail.d.pinned; textFormat: Text.PlainText; text: "󰐃"; color: root.faintText; font.family: Style.font.family; font.pixelSize: Style.font.body }
                    }
                    RowLayout {
                        spacing: Style.space(8)
                        Caption {
                            Layout.fillWidth: false
                            text: root.endpointPort(detail.d)
                            font.pixelSize: Style.font.body
                            wrapMode: Text.NoWrap
                            layer.enabled: root.addressesHidden && visible
                            layer.effect: PrivacyBlur {}
                        }
                        IconAction { iconText: "󰆏"; size: Style.space(24); tooltipText: root.t("Copy SSH endpoint") + "  Y"; onClicked: root.copyEndpoint(detail.d) }
                    }
                }
                Item { Layout.fillWidth: true }
                PrivacyButton {}
                IconAction { iconText: "󰏫"; tooltipText: root.t("Edit host") + "  E"; onClicked: root.editDevice(detail.d) }
                IconAction {
                    id: detailMore
                    iconText: "󰇘"
                    tooltipText: root.t("More")
                    onClicked: {
                        var p = detailMore.mapToItem(pageFrame, detailMore.width, detailMore.height)
                        root.openMenu(detail.d, p.x - Style.space(280), p.y + Style.space(4), false)
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)
                Fact { label: "Ping"; value: root.pingText(detail.d); kind: root.statusKind(detail.d) === "pending" ? "pending" : (root.matchingStatus(detail.d) ? (root.matchingStatus(detail.d).ping === "ok" ? "online" : "offline") : "unknown"); tooltipText: root.statusDetails(detail.d) }
                Fact { label: root.t("SSH port"); value: root.portText(detail.d); kind: root.statusKind(detail.d) === "pending" ? "pending" : (root.matchingStatus(detail.d) ? (root.matchingStatus(detail.d).ssh === "open" ? "online" : "offline") : "unknown"); tooltipText: root.statusDetails(detail.d) }
                Fact { label: root.t("Auth"); value: root.authText(detail.d); kind: "degraded"; blurred: detail.d !== null && detail.d.keyPath !== "" }
                Fact { label: "SFTP"; value: root.sftpText(detail.d); kind: detail.mount === "mounted" ? "online" : detail.mount === "foreign" ? "offline" : "unknown" }
            }
            Notice {
                visible: detail.down
                kind: "error"
                iconText: "󰖪"
                title: detail.d ? root.unreachableTitle(detail.d) : ""
                text: detail.d ? root.unreachableDetail(detail.d) : ""
                Action { iconText: "󰑐"; text: root.t("Retry") + "   R"; bordered: true; onClicked: root.refreshDevice(detail.d) }
            }
            Scroll {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Style.space(14)
                Rule { title: root.t("Open"); trailing: root.t("terminal: %1").arg(root.terminalName) }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(10)
                    LaunchTile {
                        target: "ssh"; iconText: "󰆍"; keyText: "↵"; primary: !detail.down
                        title: detail.down ? root.t("SSH anyway") : "SSH"
                        subtitle: root.t("Shell in %1").arg(root.terminalName)
                        onClicked: root.launchDevice(detail.d.id)
                    }
                    LaunchTile {
                        target: "sftp"; iconText: "󰉋"; keyText: "F"; title: root.t("Files")
                        enabled: detail.mount !== "foreign"
                        subtitle: detail.mount === "mounted" ? root.t("Mounted · open in Nautilus") : detail.mount === "foreign" ? root.t("Mount point is busy") : root.t("SFTP in Nautilus")
                        onClicked: root.launchDevice(detail.d.id, "sftp")
                    }
                    LaunchTile {
                        target: "vscode"; iconText: "󰨞"; keyText: "C"; title: "VS Code"
                        enabled: detail.d !== null && detail.d.auth === "agent"
                        subtitle: enabled ? "Remote-SSH" : root.t("Needs a key or SSH agent")
                        tooltipText: enabled ? "" : root.t("VS Code needs a key or SSH agent: Remote-SSH cannot use a saved password.")
                        onClicked: root.launchDevice(detail.d.id, "vscode")
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(28)
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        spacing: Style.space(2)
                        Rule { title: "AI CLI"; trailing: detail.d && detail.d.agentFolder ? detail.d.agentFolder : root.t("home dir") }
                        Repeater {
                            model: detail.d ? detail.d.agents : []
                            TargetRow {
                                required property string modelData
                                target: "agent:" + modelData
                                iconText: root.agentIcon(modelData)
                                text: root.agentLabel(modelData)
                                trailingText: root.agentCommand(modelData)
                                actionIcon: "󰁜"
                                onClicked: root.launchAgent(detail.d.id, modelData)
                            }
                        }
                        Tinted {
                            visible: detail.d !== null && detail.d.agents.length === 0
                            Layout.topMargin: Style.space(4)
                            Label { text: root.t("No AI CLI selected for this host") }
                            Text {
                                textFormat: Text.PlainText
                                text: root.t("Choose agents in Edit host") + "  ›"
                                color: Color.accent
                                font.family: Style.font.family
                                font.pixelSize: Style.font.body
                                font.bold: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.editDevice(detail.d) }
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        spacing: Style.space(2)
                        Rule { title: root.t("Scripts"); trailing: String(root.hostScripts(detail.d).length) }
                        Repeater {
                            model: root.hostScripts(detail.d)
                            TargetRow {
                                required property var modelData
                                target: "script:" + modelData.id
                                iconText: "󰐊"
                                text: modelData.name
                                detailText: modelData.summary || ""
                                actionIcon: "󰏫"
                                actionTooltip: root.t("Edit script")
                                onClicked: root.launchScript(detail.d.id, modelData)
                                onActionClicked: root.editScript(detail.d.id, modelData)
                            }
                        }
                        Caption {
                            visible: root.hostScripts(detail.d).length === 0
                            Layout.topMargin: Style.space(4)
                            text: root.t("No scripts yet. Scripts run over SSH stdin in your terminal.")
                        }
                        Action { Layout.fillWidth: true; Layout.topMargin: Style.space(6); iconText: "󰐕"; text: root.t("Add script"); bordered: true; onClicked: root.editScript(detail.d.id, null) }
                    }
                }
                Tinted {
                    visible: detail.d !== null && detail.d.note !== ""
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(12)
                        Caption { Layout.fillWidth: false; Layout.alignment: Qt.AlignTop; text: "󰈙"; font.pixelSize: Style.font.body }
                        Label { text: detail.d ? detail.d.note : ""; color: root.secondaryText; lineHeight: 1.3 }
                    }
                }
            }
            Rule {}
            RowLayout {
                visible: root.hostDeleteId === ""
                Layout.fillWidth: true
                spacing: Style.space(6)
                Action { iconText: "󰒃"; text: root.t("Verify host key"); onClicked: root.inspectHostKey(detail.d.id) }
                Action { iconText: "󰆏"; text: root.t("Copy endpoint"); onClicked: root.copyEndpoint(detail.d) }
                Action {
                    iconText: "󰅖"
                    text: root.t("Disconnect SFTP")
                    enabled: detail.mount === "mounted"
                    tooltipText: enabled ? "" : root.t("Nothing is mounted")
                    onClicked: root.call({op: "unmountSftp", id: detail.d.id})
                }
                Item { Layout.fillWidth: true }
                Action { iconText: "󰆴"; text: root.t("Delete"); foreground: Color.urgent; onClicked: root.requestHostDelete(detail.d.id) }
            }
            Notice {
                visible: root.hostDeleteId !== "" && detail.d !== null
                kind: "error"
                iconText: "󰆴"
                title: detail.d ? root.t("Delete %1 from Remote Hosts?").arg(detail.d.name) : ""
                text: detail.d ? root.deleteConsequence(detail.d) : ""
                Action { text: root.t("Keep") + "   Esc"; bordered: true; onClicked: { root.hostDeleteId = ""; root.dockMode = "" } }
                Primary { iconText: "󰆴"; text: root.t("Delete") + "   ↵"; fillColor: Color.urgent; enabled: !root.busy; onClicked: root.confirmHostDelete() }
            }
        }
    }
    component Fact: Rectangle {
        id: fact
        property string label: ""
        property string value: ""
        property string kind: "unknown"
        property bool blurred: false
        property string tooltipText: ""
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: factColumn.implicitHeight + Style.space(22)
        color: root.tint
        HoverHandler { id: factHover }
        Ui.PanelToolTip { visible: fact.tooltipText !== "" && factHover.hovered; text: fact.tooltipText }
        ColumnLayout {
            id: factColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            Caption { text: fact.label.toUpperCase(); font.bold: true; font.letterSpacing: 1.6; wrapMode: Text.NoWrap }
            RowLayout {
                spacing: Style.space(6)
                StatusDot { kind: fact.kind }
                Label {
                    text: fact.value
                    font.bold: true
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    layer.enabled: fact.blurred && root.addressesHidden && visible
                    layer.effect: PrivacyBlur {}
                }
            }
        }
    }
    component TargetRow: Ui.CursorSurface {
        id: targetRow
        property string target: ""
        property string iconText: ""
        property string text: ""
        property string detailText: ""
        property string trailingText: ""
        property string actionIcon: ""
        property string actionTooltip: ""
        readonly property bool cursor: root.detailZone && root.detailTargetIndex(target) === root.detailCursor
        readonly property bool launching: root.busy && root.launchTarget === target
        signal clicked()
        signal actionClicked()
        Layout.fillWidth: true
        implicitHeight: detailText !== "" ? Style.space(54) : Style.space(40)
        hasCursor: targetMouse.containsMouse && !cursor
        current: cursor
        currentFill: Style.hoverFillFor(Color.foreground, Color.accent)
        Rectangle { visible: targetRow.cursor; width: Style.space(2); height: parent.height; color: Color.accent }
        MouseArea { id: targetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (!root.busy) targetRow.clicked() }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(12)
            Text { textFormat: Text.PlainText; text: targetRow.iconText; color: root.secondaryText; font.family: Style.font.family; font.pixelSize: Style.font.title }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)
                Label { text: targetRow.text; font.bold: true; font.pixelSize: Style.font.subtitle; wrapMode: Text.NoWrap; elide: Text.ElideRight }
                Caption {
                    visible: targetRow.detailText !== ""
                    text: targetRow.detailText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    layer.enabled: root.addressesHidden && visible
                    layer.effect: PrivacyBlur {}
                }
            }
            Caption { visible: targetRow.trailingText !== ""; Layout.fillWidth: false; text: targetRow.trailingText; color: root.faintText; wrapMode: Text.NoWrap }
            Spinner { visible: targetRow.launching }
            IconAction {
                visible: !targetRow.launching && targetRow.actionIcon !== ""
                iconText: targetRow.actionIcon
                size: Style.space(26)
                focusable: false
                tooltipText: targetRow.actionTooltip
                onClicked: targetRow.actionTooltip !== "" ? targetRow.actionClicked() : targetRow.clicked()
            }
        }
    }
    component ToastStack: ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)
        Repeater {
            model: root.toasts
            Rectangle {
                id: toastItem
                required property var modelData
                readonly property color tone: modelData.kind === "error" || modelData.kind === "warning" ? Color.urgent
                                            : modelData.kind === "success" ? Color.foreground : Color.accent
                Layout.fillWidth: true
                implicitHeight: toastRow.implicitHeight + Style.space(20)
                color: Qt.lighter(root.popupSurface, 1.35)
                radius: Style.cornerRadius
                Rectangle { width: Style.space(2); height: parent.height; color: toastItem.tone; opacity: 0.8 }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toastAction(toastItem.modelData)
                }
                RowLayout {
                    id: toastRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Style.space(16)
                    anchors.rightMargin: Style.space(14)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(14)
                    Text {
                        textFormat: Text.PlainText
                        text: toastItem.modelData.kind === "progress" ? "󰑓"
                            : toastItem.modelData.kind === "success" ? "󰄬"
                            : toastItem.modelData.kind === "warning" ? "󰒃"
                            : toastItem.modelData.kind === "error" ? "󰀦" : "󰆏"
                        color: toastItem.modelData.kind === "error" || toastItem.modelData.kind === "warning" ? Color.urgent : root.secondaryText
                        font.family: Style.font.family
                        font.pixelSize: Style.font.title
                        RotationAnimation on rotation { running: toastItem.modelData.kind === "progress"; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(2)
                        Label { text: toastItem.modelData.title; font.bold: true; maximumLineCount: 3; elide: Text.ElideRight }
                        Caption {
                            visible: toastItem.modelData.detail !== ""
                            text: toastItem.modelData.detail
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                            layer.enabled: root.addressesHidden && visible
                            layer.effect: PrivacyBlur {}
                        }
                    }
                    Text {
                        visible: toastItem.modelData.action === "verify"
                        textFormat: Text.PlainText
                        text: root.t("Verify") + "  K"
                        color: Color.urgent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                    }
                }
            }
        }
    }
    component ContextMenu: Rectangle {
        id: menu
        readonly property var items: root.menuItems()
        readonly property var host: root.deviceById(root.menuHostId)
        width: Style.space(300)
        height: menuColumn.implicitHeight + Style.space(12)
        color: Qt.lighter(root.popupSurface, 1.2)
        border.width: 1
        border.color: root.rule
        radius: Style.cornerRadius
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        ColumnLayout {
            id: menuColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(6)
            spacing: 0
            Caption {
                visible: root.menuFull
                Layout.leftMargin: Style.space(10)
                Layout.bottomMargin: Style.space(4)
                text: menu.host ? menu.host.name.toUpperCase() : ""
                font.bold: true
                font.letterSpacing: 1.2
            }
            Repeater {
                model: menu.items
                ColumnLayout {
                    id: menuEntry
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 0
                    Ui.CursorSurface {
                        readonly property bool usable: menuEntry.modelData.enabled !== false
                        Layout.fillWidth: true
                        implicitHeight: Style.space(34)
                        hasCursor: usable && root.menuIndex === menuEntry.index
                        fill: Style.hoverFillFor(Color.foreground, Color.accent)
                        opacity: usable ? 1 : 0.45
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onContainsMouseChanged: if (containsMouse) root.menuIndex = menuEntry.index
                            onClicked: root.runMenuItem(menuEntry.modelData)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Style.space(10)
                            anchors.rightMargin: Style.space(10)
                            spacing: Style.space(12)
                            Text {
                                textFormat: Text.PlainText
                                text: menuEntry.modelData.icon
                                color: menuEntry.modelData.danger ? Color.urgent : root.secondaryText
                                font.family: Style.font.family
                                font.pixelSize: Style.font.title
                            }
                            Label { text: menuEntry.modelData.label; color: menuEntry.modelData.danger ? Color.urgent : Color.foreground; wrapMode: Text.NoWrap }
                            Caption { Layout.fillWidth: false; text: menuEntry.modelData.key; color: root.faintText; wrapMode: Text.NoWrap }
                        }
                    }
                    Rectangle {
                        visible: menuEntry.modelData.separator === true
                        Layout.fillWidth: true
                        Layout.topMargin: Style.space(3)
                        Layout.bottomMargin: Style.space(3)
                        implicitHeight: 1
                        color: root.rule
                    }
                }
            }
        }
    }
    component PageHeader: RowLayout {
        id: header
        property string title: ""
        property string subtitle: ""
        property bool blurSubtitle: false
        property bool showPrivacy: true
        default property alias trailing: headerTrailing.data
        Layout.fillWidth: true
        spacing: Style.space(10)
        IconAction {
            Layout.alignment: Qt.AlignTop
            iconText: root.wide ? "󰅖" : "󰁍"
            enabled: !root.busy
            tooltipText: root.wide ? root.t("Close") : root.t("Back")
            onClicked: root.navigateBack()
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Label { text: header.title; font.bold: true; font.pixelSize: Style.font.display * 0.75; wrapMode: Text.NoWrap; elide: Text.ElideRight }
            Caption {
                visible: header.subtitle !== ""
                text: header.subtitle.toUpperCase()
                font.letterSpacing: 1.6
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                layer.enabled: header.blurSubtitle && root.addressesHidden && visible
                layer.effect: PrivacyBlur {}
            }
        }
        RowLayout { id: headerTrailing; Layout.alignment: Qt.AlignTop; spacing: Style.space(10) }
        PrivacyButton { visible: header.showPrivacy; Layout.alignment: Qt.AlignTop }
    }
    component Footer: ColumnLayout {
        id: footer
        property string status: ""
        default property alias actions: footerActions.data
        Layout.fillWidth: true
        spacing: Style.space(10)
        Rule {}
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(14)
            Caption { text: footer.status; wrapMode: Text.NoWrap; elide: Text.ElideRight }
            RowLayout { id: footerActions; spacing: Style.space(10) }
        }
    }
    component CheckRow: Item {
        id: checkRow
        property bool checked: false
        property bool locked: false
        property string text: ""
        property string detail: ""
        signal toggled()
        Layout.fillWidth: true
        implicitHeight: checkLayout.implicitHeight + Style.space(8)
        opacity: enabled ? 1 : 0.45
        activeFocusOnTab: !locked
        Keys.onSpacePressed: if (!checkRow.locked) checkRow.toggled()
        MouseArea { anchors.fill: parent; enabled: !checkRow.locked; cursorShape: Qt.PointingHandCursor; onClicked: checkRow.toggled() }
        RowLayout {
            id: checkLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(12)
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: Style.space(20)
                implicitHeight: Style.space(20)
                radius: Style.cornerRadius
                color: checkRow.locked ? root.tint : checkRow.checked ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.6) : "transparent"
                border.width: checkRow.checked && !checkRow.locked ? 0 : 1
                border.color: checkRow.activeFocus ? Color.accent : root.secondaryText
                Text {
                    anchors.centerIn: parent
                    visible: checkRow.checked
                    textFormat: Text.PlainText
                    text: checkRow.locked ? "󰌾" : "󰄬"
                    color: checkRow.locked ? root.secondaryText : Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(2)
                Label { text: checkRow.text; color: checkRow.locked ? root.secondaryText : Color.foreground; font.pixelSize: Style.font.subtitle }
                Caption { visible: checkRow.detail !== ""; text: checkRow.detail; color: root.faintText }
            }
        }
    }
    component Radio: Rectangle {
        property bool checked: false
        property bool danger: false
        implicitWidth: Style.space(18)
        implicitHeight: Style.space(18)
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: checked ? (danger ? Color.urgent : Color.accent) : root.secondaryText
        Rectangle {
            visible: parent.checked
            anchors.centerIn: parent
            width: parent.width / 2
            height: width
            radius: width / 2
            color: parent.danger ? Color.urgent : Color.accent
        }
    }
    component Step: RowLayout {
        id: step
        property int number: 1
        property string text: ""
        property bool done: false
        property bool current: false
        spacing: Style.space(10)
        KeyHint {
            text: String(step.number)
            tone: step.done ? root.popupSurface : root.faintText
            color: step.done ? Color.accent : root.tint
        }
        Label {
            Layout.fillWidth: false
            text: step.text
            color: step.done ? Color.foreground : root.faintText
            font.bold: step.current
            wrapMode: Text.NoWrap
        }
    }
    component Stat: Rectangle {
        id: stat
        property string sign: "+"
        property int value: 0
        property string label: ""
        property color valueColor: Color.foreground
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: statColumn.implicitHeight + Style.space(20)
        color: root.tint
        ColumnLayout {
            id: statColumn
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Label { Layout.fillWidth: false; text: stat.sign + stat.value; color: stat.valueColor; font.bold: true; font.pixelSize: Style.font.heading }
            Caption { Layout.fillWidth: false; text: stat.label }
        }
    }
    component ImportRow: Ui.CursorSurface {
        id: importRow
        required property var modelData
        readonly property string mark: modelData.action === "added" ? "+" : modelData.action === "replaced" ? "~" : "="
        readonly property bool skipped: modelData.action === "skipped"
        Layout.fillWidth: true
        implicitHeight: root.wide ? Style.space(38) : Style.space(50)
        hasCursor: importHover.hovered
        current: modelData.action === "replaced"
        opacity: skipped ? 0.55 : 1
        HoverHandler { id: importHover }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(10)
            Caption { Layout.fillWidth: false; Layout.preferredWidth: Style.space(16); text: importRow.mark; font.pixelSize: Style.font.body; font.bold: true }
            Label { visible: root.wide; Layout.preferredWidth: 3; text: importRow.modelData.name; font.bold: true; wrapMode: Text.NoWrap; elide: Text.ElideRight }
            Caption { visible: root.wide; Layout.preferredWidth: 2; text: importRow.modelData.group; font.pixelSize: Style.font.body; wrapMode: Text.NoWrap; elide: Text.ElideRight }
            Caption {
                visible: root.wide
                Layout.preferredWidth: 5
                text: importRow.modelData.login + "@" + importRow.modelData.host + ":" + importRow.modelData.port
                font.pixelSize: Style.font.body
                wrapMode: Text.NoWrap
                elide: Text.ElideMiddle
                layer.enabled: root.addressesHidden && visible
                layer.effect: PrivacyBlur {}
            }
            Caption {
                visible: root.wide
                Layout.preferredWidth: 2
                text: (importRow.modelData.auth === "password" ? root.t("password") : root.t("key")) + (importRow.modelData.action === "replaced" ? " → " + root.t("kept") : "")
                font.pixelSize: Style.font.body
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
            Caption {
                visible: root.wide
                Layout.preferredWidth: 2
                text: importRow.modelData.agents.length ? importRow.modelData.agents.map(root.agentLabel).join(", ") : "—"
                font.pixelSize: Style.font.body
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
            ColumnLayout {
                visible: !root.wide
                Layout.fillWidth: true
                spacing: Style.space(2)
                Label { text: importRow.modelData.name; font.bold: true; wrapMode: Text.NoWrap; elide: Text.ElideRight }
                Caption {
                    text: importRow.modelData.login + "@" + importRow.modelData.host + ":" + importRow.modelData.port
                    wrapMode: Text.NoWrap
                    elide: Text.ElideMiddle
                    layer.enabled: root.addressesHidden && visible
                    layer.effect: PrivacyBlur {}
                }
            }
            Caption { visible: !root.wide; Layout.fillWidth: false; text: importRow.modelData.group.toUpperCase(); font.letterSpacing: 1.6; wrapMode: Text.NoWrap }
        }
    }
    component NewGroupField: Field {
        id: newGroup
        placeholderText: root.t("New group name, e.g. work")
        maximumLength: 100
        enabled: !root.busy
        Keys.onReturnPressed: root.addGroup(newGroup)
        Keys.onEnterPressed: root.addGroup(newGroup)
        Keys.onEscapePressed: { text = ""; pageFrame.forceActiveFocus() }
    }
    component GroupRow: ColumnLayout {
        id: groupRow
        required property var modelData
        readonly property var members: root.groupDevices(modelData.id)
        readonly property bool editing: root.groupEditId === modelData.id
        readonly property bool confirming: root.groupDeleteId === modelData.id
        readonly property string reason: root.groupDeleteReason(modelData)
        Layout.fillWidth: true
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Style.space(groupRow.editing ? 56 : 52)
            color: groupRow.confirming ? root.urgentTint
                 : groupRow.editing || root.highlightGroupId === groupRow.modelData.id || groupHover.hovered ? root.tint : "transparent"
            HoverHandler { id: groupHover }
            Rectangle {
                visible: groupRow.editing || groupRow.confirming || root.highlightGroupId === groupRow.modelData.id
                width: Style.space(2)
                height: parent.height
                color: groupRow.confirming || groupRow.editing && root.groupEditInvalid ? Color.urgent : Color.accent
            }
            MouseArea {
                anchors.fill: parent
                enabled: root.wide && !groupRow.editing
                cursorShape: Qt.PointingHandCursor
                onClicked: root.highlightGroupId = root.highlightGroupId === groupRow.modelData.id ? "" : groupRow.modelData.id
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)
                Label {
                    visible: !groupRow.editing
                    Layout.fillWidth: !root.wide
                    Layout.preferredWidth: root.wide ? Style.space(236) : -1
                    text: groupRow.modelData.name
                    font.bold: true
                    font.pixelSize: Style.font.subtitle
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
                Field {
                    id: groupNameEdit
                    visible: groupRow.editing
                    Layout.fillWidth: !root.wide
                    Layout.preferredWidth: root.wide ? Style.space(236) : -1
                    maximumLength: 100
                    rightPadding: Style.space(64)
                    accent: root.groupEditInvalid ? Color.urgent : Color.accent
                    onVisibleChanged: if (visible) { text = groupRow.modelData.name; forceActiveFocus(); selectAll() }
                    onTextChanged: { root.groupEditName = text; if (text.trim() !== "") root.groupEditInvalid = false }
                    Keys.onReturnPressed: root.commitGroupEdit()
                    Keys.onEnterPressed: root.commitGroupEdit()
                    Keys.onEscapePressed: { root.groupEditId = ""; pageFrame.forceActiveFocus() }
                    Text {
                        visible: groupNameEdit.text.length >= 80 || root.groupEditInvalid
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: groupNameEdit.text.length + "/100"
                        color: root.groupEditInvalid ? Color.urgent : root.faintText
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }
                }
                Flow {
                    visible: root.wide
                    Layout.fillWidth: true
                    spacing: Style.space(6)
                    Repeater {
                        model: groupRow.members.slice(0, 4)
                        KeyHint {
                            required property var modelData
                            text: "● " + modelData.name
                            tone: root.secondaryText
                        }
                    }
                    Caption { visible: groupRow.members.length > 4; width: implicitWidth; text: "+" + (groupRow.members.length - 4) }
                    Caption { visible: groupRow.members.length === 0; width: implicitWidth; text: root.t("empty"); color: root.faintText }
                }
                Caption {
                    visible: !root.wide && !groupRow.editing
                    Layout.fillWidth: false
                    text: groupRow.members.length === 0 ? root.t("empty") : groupRow.members.length === 1 ? root.t("1 host") : root.t("%1 hosts").arg(groupRow.members.length)
                    wrapMode: Text.NoWrap
                }
                IconAction { visible: groupRow.editing; iconText: "󰄬"; enabled: !root.busy; tooltipText: root.t("Save") + "  ↵"; onClicked: root.commitGroupEdit() }
                IconAction { visible: groupRow.editing; iconText: "󰅖"; tooltipText: root.t("Cancel") + "  Esc"; onClicked: root.groupEditId = "" }
                Action {
                    visible: !groupRow.editing
                    iconText: "󰏫"
                    text: root.wide ? root.t("Rename") : ""
                    enabled: !root.busy
                    tooltipText: root.wide ? "" : root.t("Rename")
                    onClicked: { root.groupDeleteId = ""; root.groupEditId = groupRow.modelData.id; root.groupEditInvalid = false }
                }
                IconAction {
                    visible: !groupRow.editing
                    iconText: groupRow.reason === "" ? "󰆴" : "󰌾"
                    hoverColor: Color.urgent
                    foreground: groupRow.reason === "" ? Color.urgent : root.faintText
                    enabled: !root.busy
                    tooltipText: groupRow.reason === "" ? root.t("Delete") : groupRow.reason
                    onClicked: if (groupRow.reason === "") { root.groupEditId = ""; root.groupDeleteId = groupRow.modelData.id; pageFrame.forceActiveFocus() }
                }
            }
        }
        Caption {
            visible: groupRow.editing && root.groupEditInvalid
            Layout.leftMargin: Style.space(14)
            Layout.topMargin: Style.space(4)
            text: "󰀦  " + root.t("Enter a group name")
            color: Color.urgent
        }
        Notice {
            visible: groupRow.confirming
            stacked: !root.wide
            kind: "error"
            iconText: "󰆴"
            text: root.t("Delete “%1” permanently? It has no hosts.").arg(groupRow.modelData.name)
            Action { text: root.t("Keep") + "   Esc"; bordered: true; onClicked: root.groupDeleteId = "" }
            Primary {
                iconText: "󰆴"
                text: root.t("Delete") + "   ↵"
                fillColor: Color.urgent
                enabled: !root.busy
                onClicked: { root.groupDeleteId = ""; root.call({op: "deleteGroup", id: groupRow.modelData.id}) }
            }
        }
        Rectangle { visible: !root.wide; Layout.fillWidth: true; implicitHeight: 1; color: root.rule; opacity: 0.5 }
    }
}
