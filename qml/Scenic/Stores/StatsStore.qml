pragma Singleton
import QtQuick

// CPU, memory and network use, sampled from /proc (Linux only; elsewhere the
// values stay at zero).
QtObject {
    id: root

    property real cpuPercent: 0
    property real memPercent: 0
    property string netInterface: ""
    property real netRxKBps: 0
    property real netTxKBps: 0

    property var prevCpu: null
    property var prevNet: null
    // a new interface needs a new baseline
    onNetInterfaceChanged: { prevNet = null; prevNetTime = 0 }
    property double prevNetTime: 0

    property Timer timer: Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: root.sample()
    }

    function sample() {
        const stat = String(Util.readFile("/proc/stat"))
        const mem = String(Util.readFile("/proc/meminfo"))
        const net = String(Util.readFile("/proc/net/dev"))
        if (stat.length > 0)
            parseCpu(stat)
        if (mem.length > 0)
            parseMem(mem)
        if (net.length > 0)
            parseNet(net)
    }

    function parseCpu(stat) {
        const line = stat.split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
        if (line.length < 4)
            return
        const idle = line[3] + (line[4] ?? 0)
        const total = line.reduce((a, b) => a + b, 0)
        if (prevCpu) {
            const dTotal = total - prevCpu.total
            const dIdle = idle - prevCpu.idle
            if (dTotal > 0)
                cpuPercent = 100 * (1 - dIdle / dTotal)
        }
        prevCpu = { total, idle }
    }

    function parseMem(mem) {
        const get = k => {
            const m = mem.match(new RegExp(k + ":\\s+(\\d+)"))
            return m ? Number(m[1]) : 0
        }
        const total = get("MemTotal")
        const avail = get("MemAvailable")
        if (total > 0)
            memPercent = 100 * (1 - avail / total)
    }

    function parseNet(dev) {
        const lines = dev.split("\n").slice(2)
        let rx = 0, tx = 0
        for (const l of lines) {
            const m = l.trim().match(/^(\S+):\s*(\d+)(?:\s+\d+){7}\s+(\d+)/)
            if (!m) continue
            const name = m[1]
            if (name === "lo") continue
            if (netInterface === "" || name === netInterface) {
                rx = Number(m[2]); tx = Number(m[3])
                if (netInterface === "") netInterface = name
            }
        }
        const now = Date.now()
        if (prevNet && prevNetTime > 0) {
            const dt = (now - prevNetTime) / 1000
            if (dt > 0) {
                netRxKBps = Math.max(0, (rx - prevNet.rx) / 1024 / dt)
                netTxKBps = Math.max(0, (tx - prevNet.tx) / 1024 / dt)
            }
        }
        prevNet = { rx, tx }
        prevNetTime = now
    }
}
