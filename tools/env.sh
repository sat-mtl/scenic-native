# Where the engine and GStreamer come from. Sourced by run.sh and the test
# scripts, after they cd to the repository root.
#
#   SCORE_BIN       the ossia-score binary; default: ossia-score on the PATH
#   SCENIC_GST_SDK  optional prefix of a GStreamer build to use instead of the
#                   system's (bin/, lib/<triplet>/, libexec/), e.g. one with
#                   gst-plugins-rs for WebRTC. Unset: system GStreamer.
#
# After sourcing: SCORE_BIN is set (or empty, see require_score), the SDK's
# environment is exported when there is one, and GST_BIN is the prefix of the
# gst-launch-1.0 & co. to run ("" for the ones on the PATH).
# shellcheck disable=SC2034  # GST_BIN is read by the scripts sourcing this

SCORE_BIN="${SCORE_BIN:-$(command -v ossia-score 2>/dev/null || true)}"

# score built with AddressSanitizer reports Qt symbols defined twice
export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_odr_violation=0}"

# The suites cover the NDI / Spout / Syphon node types, which the basic edition
# does not offer: NodeCatalog gates them on this flag, so tests and local runs
# always see the full node set.
export SAT_ADVANCED_IO="${SAT_ADVANCED_IO:-1}"

GST_BIN=""
if [ -n "${SCENIC_GST_SDK:-}" ]; then
    if [ ! -d "$SCENIC_GST_SDK" ]; then
        echo "SCENIC_GST_SDK is not a directory: $SCENIC_GST_SDK" >&2
        exit 1
    fi
    gst_lib="$SCENIC_GST_SDK/lib/$(uname -m)-linux-gnu"
    [ -d "$gst_lib" ] || gst_lib="$SCENIC_GST_SDK/lib"
    export LD_LIBRARY_PATH="$gst_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export GST_PLUGIN_SYSTEM_PATH_1_0="$gst_lib/gstreamer-1.0"
    export GST_PLUGIN_SCANNER="$SCENIC_GST_SDK/libexec/gstreamer-1.0/gst-plugin-scanner"
    # a registry of its own: the system's describes other plugins
    export GST_REGISTRY_1_0="${TMPDIR:-/tmp}/scenic-gst-sdk-registry.bin"
    GST_BIN="$SCENIC_GST_SDK/bin/"
fi

# require_score: stop with a message when there is no score binary.
require_score() {
    if [ -z "$SCORE_BIN" ] || [ ! -x "$SCORE_BIN" ]; then
        echo "ossia-score not found: put it on the PATH or set SCORE_BIN" \
             "to an ossia score build with score-addon-ndi and score-addon-ltc." >&2
        exit 1
    fi
}
