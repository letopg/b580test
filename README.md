# b580test

Measures how much HEVC Main10 video an Intel Arc B580 can hardware-encode in real time, with several streams at once.

The question behind it: can one GPU encode 7 camera streams of 2840×1700 at 100 fps live? That is **3.4 Gpixel/s** in total. For a 4-camera machine it is 1.9 Gpixel/s.

## Run

Needs Linux with the `xe` kernel driver (kernel 6.12 or newer for Battlemage), the Intel iHD VA-API driver (`intel-media-va-driver-non-free` on Debian/Ubuntu), `ffmpeg` built with VA-API, and `vainfo`.

```bash
git clone https://github.com/letopg/b580test.git && cd b580test
sudo ./b580_bench.sh       # or: sudo ./b580_bench.sh /dev/dri/renderD129 to pick the GPU
                           # root only to read the video engine count from debugfs; plain ./b580_bench.sh works too
```

It takes 5–15 minutes. Each session decodes the first 30 frames of the bundled clip once, keeps them in GPU memory and encodes them in a loop, 630 frames per session. It runs 1, 2, 3, 4 and 7 parallel sessions at three quality levels (1 = best quality, 4 = middle, 7 = fastest). Nothing is written to disk except `results/`.

Intel GPUs decode and encode on the same video engines. Encoding from GPU memory keeps the clip's decode to ~5% of the engine time. In real use the frames come from a compute shader, with no decode at all. The frames held in memory take ~0.5 GB of GPU memory per session, ~4 GB at 7 sessions.

## Output

`results/<gpu>.tsv`, one row per quality level and session count:

| column | meaning |
|---|---|
| level | VA-API quality level (1 best … 7 fastest) |
| sessions | parallel encodes |
| fps_per_session | frames per second each session reached |
| gpix_s | total encoded pixels per second, all sessions (Gpixel/s) |

`results/<gpu>.sysinfo.txt` records the GPU, kernel driver, PCIe link, VA driver version, video engine count (when run as root) and whether the card offers HEVC Main10 encode.

Please send back both files.

## Pass marks

| Use | Needs |
|---|---|
| One machine, 7 cameras | ≥ 3.4 Gpixel/s at a usable quality level |
| Two machines, 4 cameras each | ≥ 1.9 Gpixel/s |

Reference results (Gpixel/s, saturated rows):

| GPU | video engines | level 1 | level 4 | level 7 | script |
|---|---|---|---|---|---|
| UHD 630 (Gen9.5 iGPU) | 1 | 0.14 | 0.25 | 0.54 | current |
| Core Ultra 200V iGPU (Lunar Lake, Xe2, iHD 26.1.5) | 1 | 0.29 | 0.73 | 1.09 | earlier, decode included |

The earlier script decoded the whole clip in every session. On the UHD 630 that cost almost nothing: the old and current scripts agree within 8 %, so decode and encode overlap on the engine rather than taking turns. Whether Xe2 behaves the same is open until the Lunar Lake row is rerun.

The total stays flat as sessions are added once the engines are saturated, and a single engine saturates with one session. The B580 has two Xe2 media engines. If the engine count shows as unknown, `sudo dmesg | grep -iE 'vcs[0-9]'` lists the fused-off ones.

## The clip

`clip_2840x1700_p010.mkv` is synthetic: 90 frames of ffmpeg's `testsrc2` pattern with per-frame noise added, HEVC Main10, 2840×1700. Checked against real footage on the UHD 630 with the earlier, decode-included script (interleaved A/B, two rounds, identical results): the synthetic clip encodes 3–10 % **slower** than a real multi-camera clip of a performer at the same size, because its per-frame noise is harder to encode. Real 100 fps sensor footage is noisy too, so the synthetic clip errs on the conservative side.

| level | real footage | synthetic |
|---|---|---|
| 1 | 0.154 Gpixel/s | 0.139 |
| 4 | 0.251 | 0.243 |
| 7 | 0.500 | 0.474 |
