"""Normalise and repair the user-supplied line-6.

Two problems with the incoming file:
  1. Its RIFF/data size fields are 0xFFFFFFFF (ffmpeg pipe output), so any
     spec-compliant parser reports a bogus ~26843 s duration.
  2. Its active-RMS sits 2.4 dB below the five real-voice assets, which the
     player feeds through one shared gain, so it would sound thin.

This rewrites a clean, correctly-sized 16-bit PCM WAV at the same sample rate
and channel count, with the measured gain applied.
"""

import os
import sys
import struct
import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(_HERE, "..", "lib", "assets", "line-6.wav")
DST = os.path.join(_HERE, "final-voice", "line-6-user-normalized.wav")

GAIN_DB = float(sys.argv[1]) if len(sys.argv) > 1 else 2.4


def read_lenient_wav(path):
    raw = open(path, "rb").read()
    if raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
        raise ValueError("not a RIFF/WAVE file")
    pos = 12
    fmt = None
    data = None
    while pos + 8 <= len(raw):
        cid = raw[pos:pos + 4]
        size = struct.unpack("<I", raw[pos + 4:pos + 8])[0]
        body = pos + 8
        if cid == b"fmt ":
            fmt = raw[body:body + min(size, 16)]
        elif cid == b"data":
            end = len(raw) if size == 0xFFFFFFFF or body + size > len(raw) else body + size
            data = raw[body:end]
            if size == 0xFFFFFFFF:
                break
        if size == 0xFFFFFFFF:
            break
        pos = body + size + (size & 1)
    if fmt is None or data is None:
        raise ValueError("missing fmt or data chunk")
    audio_format, channels, rate, _, _, bits = struct.unpack("<HHIIHH", fmt)
    return audio_format, channels, rate, bits, data


def write_wav(path, channels, rate, bits, pcm_bytes):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    block = channels * bits // 8
    with open(path, "wb") as fh:
        fh.write(b"RIFF")
        fh.write(struct.pack("<I", 36 + len(pcm_bytes)))
        fh.write(b"WAVE")
        fh.write(b"fmt ")
        fh.write(struct.pack("<IHHIIHH", 16, 1, channels, rate, rate * block, block, bits))
        fh.write(b"data")
        fh.write(struct.pack("<I", len(pcm_bytes)))
        fh.write(pcm_bytes)


def active_rms_dbfs(samples):
    threshold = 10 ** (-45 / 20)
    active = samples[np.abs(samples) > threshold]
    if active.size == 0:
        return -np.inf
    return 20 * np.log10(np.sqrt(np.mean(active ** 2)))


fmt_code, channels, rate, bits, data = read_lenient_wav(SRC)
if bits != 16 or fmt_code != 1:
    raise SystemExit("expected 16-bit PCM, got format=%d bits=%d" % (fmt_code, bits))

samples = np.frombuffer(data, dtype="<i2").astype(np.float64) / 32768.0
before_peak = 20 * np.log10(max(np.max(np.abs(samples)), 1e-12))
before_rms = active_rms_dbfs(samples)
duration = len(samples) / channels / rate

gain = 10 ** (GAIN_DB / 20)
out = samples * gain
peak = np.max(np.abs(out))
if peak >= 1.0:
    raise SystemExit("would clip: peak %.3f" % peak)

pcm = np.clip(np.rint(out * 32767.0), -32768, 32767).astype("<i2").tobytes()
write_wav(DST, channels, rate, bits, pcm)
after = np.frombuffer(pcm, dtype="<i2").astype(np.float64) / 32768.0

print("source      : %d Hz, %d ch, %d bit, %.3f s" % (rate, channels, bits, duration))
print("before      : peak %.1f dBFS, active-RMS %.1f dB" % (before_peak, before_rms))
print("gain        : %+.1f dB" % GAIN_DB)
print("after       : peak %.1f dBFS, active-RMS %.1f dB" % (
    20 * np.log10(max(np.max(np.abs(after)), 1e-12)), active_rms_dbfs(after)))
print("written     : %s (%d bytes)" % (DST, os.path.getsize(DST)))
