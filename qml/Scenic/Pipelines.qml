pragma Singleton
import QtQuick
import Scenic

// Device settings shared by the node types.
QtObject {
    //! A string as a quoted gst-launch value, e.g. a file path.
    function quoted(s) {
        return "\"" + String(s ?? "").replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\""
    }

    //! A string reduced to characters that need no quoting anywhere in a
    //! pipeline description, caps structures included.
    function token(s) {
        return String(s ?? "").replace(/[^A-Za-z0-9_.-]/g, "_")
    }

    //! The STUN and TURN properties of a webrtcsink or webrtcsrc, from the
    //! settings. The credentials are percent-encoded into the TURN URI, where
    //! a '/' or ':' in a password would otherwise end its user info.
    function iceServers() {
        let s = ""
        if (SettingsStore.stunServer !== "")
            s += " stun-server=" + quoted(SettingsStore.stunServer)
        const turn = SettingsStore.turnServer
        const m = /^(turns?):\/\/(.+)$/.exec(turn)
        if (m) {
            const user = SettingsStore.turnUser
            const auth = user === "" ? ""
                       : encodeURIComponent(user) + ":"
                         + encodeURIComponent(SettingsStore.turnPassword) + "@"
            s += " turn-servers=" + quoted("<\"" + m[1] + "://" + auth + m[2] + "\">")
        } else if (turn !== "") {
            console.error("Pipelines: a TURN server is turn://host:port or turns://host:port, not",
                          turn)
        }
        return s
    }

    //! A GStreamer device with a video appsink or appsrc named "video".
    function gstVideo(pipeline, w, h) {
        return { Pipeline: pipeline, Width: w ?? 1280, Height: h ?? 720,
                 Rate: 30, AudioChannels: 0, InputTransfer: 13 }
    }
    //! A GStreamer device with an F32LE appsink named "audio".
    function gstAudioIn(pipeline) {
        return { Pipeline: pipeline, Width: 0, Height: 0, Rate: 0,
                 AudioChannels: 2, InputTransfer: 13 }
    }
    //! A GStreamer audio output: `tail` follows the appsrc, which score
    //! feeds with the engine's floats at the engine's rate.
    function gstAudioOut(tail, channels) {
        const ch = channels ?? 2
        return { Pipeline: "appsrc name=audio ! audioconvert ! audioresample ! " + tail,
                 Width: 0, Height: 0, Rate: 0,
                 AudioChannels: ch, InputTransfer: 13 }
    }
    //! Window capture settings; every key is required.
    //! mode: 0 = window, 1 = all screens, 2 = one screen, 3 = region.
    function windowCapture(mode, title, screen, region) {
        region = region ?? ({})
        return { Mode: mode, WindowTitle: title ?? "", WindowId: 0,
                 ScreenId: 0, ScreenName: screen ?? "",
                 RegionX: region.x ?? 0, RegionY: region.y ?? 0,
                 RegionW: region.w ?? 0, RegionH: region.h ?? 0, FPS: 30 }
    }
    //! "preset=veryfast, crf=23" as the [[key, value]] pairs of the Libav
    //! device's Options. Entries without '=' are dropped.
    function options(text: string): var {
        const out = []
        for (const part of String(text ?? "").split(",")) {
            const eq = part.indexOf("=")
            if (eq <= 0)
                continue
            out.push([part.substring(0, eq).trim(), part.substring(eq + 1).trim()])
        }
        return out
    }

    //! A Libav input: anything libavformat opens (file, URL, lavfi graph).
    function libavVideoIn(path, options) {
        return { Direction: 0, Path: path, Width: 1280, Height: 720, Rate: 30,
                 AudioChannels: 2, Threads: 0,
                 AudioEncoderShort: "", AudioEncoderLong: "", AudioSmpFmt: "",
                 AudioSampleRate: 48000,
                 VideoEncoderShort: "", VideoEncoderLong: "",
                 VideoRenderPixFmt: "rgba", VideoConvertedPixFmt: "yuv420p",
                 Muxer: "", MuxerLong: "", Options: options ?? [],
                 InputTransfer: 13 }
    }

    //! A Libav output to a file or URL.
    function libavVideoOut(path, muxer, venc, options) {
        return { Direction: 1, Path: path, Width: 1280, Height: 720, Rate: 30,
                 AudioChannels: 0, Threads: 0,
                 AudioEncoderShort: "", AudioEncoderLong: "", AudioSmpFmt: "",
                 AudioSampleRate: 48000,
                 VideoEncoderShort: venc, VideoEncoderLong: "",
                 VideoRenderPixFmt: "rgba", VideoConvertedPixFmt: "yuv420p",
                 Muxer: muxer, MuxerLong: "", Options: options,
                 InputTransfer: 13 }
    }
}
