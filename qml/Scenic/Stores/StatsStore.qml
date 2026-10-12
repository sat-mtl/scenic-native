pragma Singleton
import QtQuick
import Scenic

// CPU, memory and network use, read from score-addon-sysinfo's device: one
// address tree on every platform. The meters stay at zero on a score built
// without the addon, and hwinfo enumerates no interface at all on macOS, where
// the network block is therefore hidden.
QtObject {
    id: root

    property real cpuPercent: 0
    property real memPercent: 0
    property string netInterface: ""
    property real netRxKBps: 0
    property real netTxKBps: 0

    readonly property string deviceName: "sysinfo"
    readonly property int rate: 2000

    property Timer timer: Timer {
        interval: root.rate
        repeat: true
        running: true
        onTriggered: root.sample()
    }

    //! Called from Main.qml: there is no document yet when the singleton is
    //! built, and createDevice needs one.
    function init() {
        if (!Score.device(deviceName))
            Score.createDevice(deviceName, Uuids.sysinfo,
                               { Rate: rate, PerThreadCpu: false })
    }

    function sample() {
        if (!Score.device(deviceName))
            return
        const net = {}
        Score.iterateDevice(deviceName, (addr, v) => {
            const a = addr.substring(deviceName.length + 1)
            if (a === "/cpu/usage")
                root.cpuPercent = 100 * v.value
            else if (a === "/memory/usage")
                root.memPercent = 100 * v.value
            else {
                const m = a.match(/^\/network\/(\d+)\/(description|ipv4|rx|tx|rx_total|tx_total)$/)
                if (m) {
                    if (!net[m[1]])
                        net[m[1]] = {}
                    net[m[1]][m[2]] = v.value
                }
            }
        })
        applyNetwork(net)
    }

    // Scenic routes plenty over the loopback, so the aggregate /network/rx says
    // nothing about the link: report the busiest real interface instead.
    function applyNetwork(net) {
        let pick = null, bytes = -1
        for (const i in net) {
            const n = net[i]
            if (String(n.ipv4 ?? "").startsWith("127."))
                continue
            const total = (n.rx_total ?? 0) + (n.tx_total ?? 0)
            if (total > bytes) {
                bytes = total
                pick = n
            }
        }
        netInterface = pick ? String(pick.description ?? "") : ""
        netRxKBps = pick ? (pick.rx ?? 0) / 1024 : 0
        netTxKBps = pick ? (pick.tx ?? 0) / 1024 : 0
    }
}
