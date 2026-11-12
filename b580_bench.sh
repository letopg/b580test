#!/usr/bin/env bash
# HEVC Main10 hardware-encode throughput on Intel Arc (VA-API), at 2840x1700, with 1-7 parallel sessions.
# Each session decodes the first 30 clip frames once, holds them in GPU memory and encodes them in a loop,
# so the video engines spend ~95% of their time encoding. No files are written except results/.
#
#   ./b580_bench.sh [render node]        default: the first Intel render node (/dev/dri/renderD*)
#
# Output: results/<gpu>.tsv (one row per quality level x session count), results/<gpu>.sysinfo.txt
set -uo pipefail
cd "$(dirname "$0")"
CLIP=clip_2840x1700_p010.mkv
FRAMES=${FRAMES:-630}                   # encoded frames per session
HOLD=30                                 # decoded frames held in GPU memory (~14.5 MB each)
MP=$(awk 'BEGIN{print 2840*1700/1e6}')

for t in ffmpeg vainfo awk lspci; do command -v $t >/dev/null || { echo "missing: $t"; exit 1; }; done
DEV=${1:-}
if [[ -z $DEV ]]; then
  for d in /dev/dri/renderD*; do
    [[ $(cat /sys/class/drm/$(basename $d)/device/vendor 2>/dev/null) == 0x8086 ]] && { DEV=$d; break; }
  done
fi
[[ -n $DEV ]] || { echo "no Intel render node found"; exit 1; }

PCI=$(basename "$(readlink -f /sys/class/drm/$(basename $DEV)/device)")
GPU=$(lspci -s "$PCI" | cut -d: -f3- | sed 's/^ *//')
TAG=$(echo "$GPU" | sed 's/[^A-Za-z0-9]\+/_/g; s/_$//')
mkdir -p results
OUT=results/$TAG.tsv
{
  echo "date:   $(date -Is)"
  echo "device: $DEV ($PCI)"
  echo "gpu:    $GPU"
  echo "kernel: $(uname -r)  driver: $(basename "$(readlink -f /sys/class/drm/$(basename $DEV)/device/driver)")"
  echo "ffmpeg: $(ffmpeg -version | head -1)"
  lspci -vv -s "$PCI" 2>/dev/null | grep -E "LnkSta:|Region 0|Resizable" | sed 's/^\s*/link:   /'
  vainfo --display drm --device "$DEV" 2>/dev/null | grep -E "Driver version|HEVCMain10"
  # xe: dri/N/gtN/hw_engines; i915: dri/N/i915_engine_info
  VCS=$(cat /sys/kernel/debug/dri/*/gt*/hw_engines /sys/kernel/debug/dri/*/i915_engine_info 2>/dev/null \
        | grep -oE '^vcs[0-9]+' | sort -u | tr '\n' ' ')
  echo "video engines: ${VCS:-unknown (run as root for debugfs, or: dmesg | grep -iE 'vcs[0-9]')}"
} | tee results/$TAG.sysinfo.txt

# Arc encodes HEVC only on the low-power (VDENC) entry point; older iGPUs only on the full one
LP=0; vainfo --display drm --device "$DEV" 2>/dev/null | grep -q "HEVCMain10.*EncSliceLP" && LP=1
vainfo --display drm --device "$DEV" 2>/dev/null | grep -q "HEVCMain10.*EncSlice" \
  || { echo "!! no HEVC Main10 encode entry point on $DEV"; exit 1; }

one() {  # $1 quality level (1 best quality .. 7 fastest), $2 log
  ffmpeg -hide_banner -nostats -hwaccel vaapi -hwaccel_device "$DEV" -hwaccel_output_format vaapi \
    -extra_hw_frames $((HOLD + 8)) -i "$CLIP" -vf loop=loop=-1:size=$HOLD -frames:v $FRAMES \
    -c:v hevc_vaapi -low_power $LP -profile:v main10 -compression_level "$1" -rc_mode CQP -qp 22 \
    -f null - > "$2" 2>&1
}

TMP=$(mktemp -d)
SESSIONS="1 2 3 4 7"

echo -e "level\tsessions\tframes\twall_s\tfps_per_session\tgpix_s" | tee "$OUT"
for q in 1 4 7; do
  for n in $SESSIONS; do
    t0=$(date +%s.%N)
    for i in $(seq $n); do one $q $TMP/$i.log & done
    wait
    t1=$(date +%s.%N)
    if ! grep -qP "frame=\s*[1-9]" $TMP/1.log; then echo "!! ffmpeg failed (level $q x$n):"; tail -8 $TMP/1.log; exit 1; fi
    f=$(grep -oP 'frame=\s*\K[0-9]+' $TMP/1.log | tail -1)
    awk -v q=$q -v n=$n -v f=$f -v a=$t0 -v b=$t1 -v mp=$MP \
      'BEGIN{w=b-a; printf "%s\t%d\t%d\t%.1f\t%.0f\t%.2f\n", q, n, f, w, f/w, n*f*mp/w/1000}' | tee -a "$OUT"
  done
done
rm -rf "$TMP"
echo "wrote $OUT and results/$TAG.sysinfo.txt"
