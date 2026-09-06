pragma Singleton
import QtQuick

// One in-memory draft shared by every per-monitor bar-widget instance.
// Never persisted: closing/reopening or switching monitors keeps the form,
// while restarting Omarchy Shell discards it (including the password).
QtObject {
    property bool active: false
    property string editId: ""
    property string name: ""
    property string host: ""
    property string port: "22"
    property string login: ""
    property string group: ""
    property string note: ""
    property string auth: "agent"
    property string keyPath: ""
    property string client: "ghostty"
    property var agents: []
    property string agentFolder: ""
    property string remoteFolder: ""
    property string password: ""
    property string focusKey: "name"
    property bool aiExpanded: false
    property bool advancedExpanded: false

    function clear() {
        active = false
        editId = ""
        name = ""
        host = ""
        port = "22"
        login = ""
        group = ""
        note = ""
        auth = "agent"
        keyPath = ""
        client = "ghostty"
        agents = []
        agentFolder = ""
        remoteFolder = ""
        password = ""
        focusKey = "name"
        aiExpanded = false
        advancedExpanded = false
    }
}
