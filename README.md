# b580test

Measures how much HEVC Main10 video an Intel Arc B580 can hardware-encode in real time, with several streams at once.

The question behind it: can one GPU encode 7 camera streams of 2840×1700 at 100 fps live? That is **3.4 Gpixel/s** in total. For a 4-camera machine it is 1.9 Gpixel/s.

## Run

Needs Linux with the `xe` kernel driver (kernel 6.12 or newer for Battlemage), the Intel iHD VA-API driver (`intel-media-va-driver-non-free` on Debian/Ubuntu), `ffmpeg` built with VA-API, and `vainfo`.

```bash
git clone https://github.com/letopg/b580test.git && cd b580test
./b580_bench.sh            # or: ./b580_bench.sh /dev/dri/renderD129 to pick the GPU
```

It takes a few minutes. It decodes the bundled clip on the GPU and encodes it again with 1, 2, 3, 4 and 7 parallel sessions at three quality levels (1 = best quality, 4 = middle, 7 = fastest). Nothing is written to disk except `results/`.

## Output

`results/<gpu>.tsv`, one row per quality level and session count:

| column | meaning |
|---|---|
| level | VA-API quality level (1 best … 7 fastest) |
| sessions | parallel encodes |
| fps_per_session | frames per second each session reached |
| gpix_s | total encoded pixels per second, all sessions (Gpixel/s) |

`results/<gpu>.sysinfo.txt` records the GPU, kernel driver, PCIe link, VA driver version and whether the card offers HEVC Main10 encode.

Please send back both files.

## Pass marks

| Use | Needs |
|---|---|
| One machine, 7 cameras | ≥ 3.4 Gpixel/s at a usable quality level |
| Two machines, 4 cameras each | ≥ 1.9 Gpixel/s |

Reference results, same script:

| GPU | video engines | level 1 | level 4 | level 7 |
|---|---|---|---|---|
| Core Ultra 200V iGPU (Lunar Lake, Xe2, iHD 26.1.5) | 1 | 0.28 | 0.73 | 1.10 |
| UHD 630 (Gen9.5 iGPU) | 1 | 0.15 | 0.24 | 0.41–0.50 |

The B580 has two Xe2 media engines. Please include the engine count with your results: `sudo cat /sys/kernel/debug/dri/*/gt1/hw_engines | grep -E '^vcs'` (xe driver), or `sudo dmesg | grep -iE 'vcs[0-9]'`.

Reference, Intel UHD 630 (Gen9.5 iGPU, one media engine), same script: 0.15 Gpixel/s at level 1, 0.24 at level 4, 0.41–0.50 at level 7. The total stays flat as sessions are added, because one engine is already saturated.

## The clip

`clip_2840x1700_p010.mkv` is synthetic: 90 frames of ffmpeg's `testsrc2` pattern with per-frame noise added, HEVC Main10, 2840×1700. Checked against real footage on the UHD 630 (interleaved A/B, two rounds, identical results): the synthetic clip encodes 3–10 % **slower** than a real multi-camera clip of a performer at the same size, because its per-frame noise is harder to encode. Real 100 fps sensor footage is noisy too, so the synthetic clip errs on the conservative side.

| level | real footage | synthetic |
|---|---|---|
| 1 | 0.154 Gpixel/s | 0.139 |
| 4 | 0.251 | 0.243 |
| 7 | 0.500 | 0.474 |
