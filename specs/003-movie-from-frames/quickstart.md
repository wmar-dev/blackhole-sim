# Quickstart: Validate the Movie Feature

Prerequisites: an Apple-silicon Mac (reference: Apple M4), macOS 14+, Swift 6.x, the repository built with
`swift build -c release`. All commands run from the repository root. Expected values are the targets from
[spec.md](spec.md); measured results are recorded in [research.md](research.md) as the work proceeds. The checks use
`ffprobe` (part of ffmpeg) only to inspect the result. The commands use ffmpeg for encoding when it is installed; add `--encoder avfoundation` to every `movie` command to repeat the checks with the built-in encoder.

## 1. Assemble existing frames (User Story 1)

```bash
for i in $(seq 1 48); do
  .build/release/bhsim render --width 640 --height 360 --samples 1 --inclination $((90 - i)) --out out/frames/frame_$(printf %04d $i)
done
.build/release/bhsim movie assemble --frames out/frames --fps 24 --out out/assembled.mp4
ffprobe -v error -show_entries stream=codec_name,width,height,nb_frames,r_frame_rate,duration -of default=nw=1 out/assembled.mp4
```

Expected: 48 frames, 640×360, 24 fps, duration 2.0 s, `h264`; the command printed the same numbers. Open the file in QuickTime Player: it plays smoothly.

Repeat with each encoder and compare reproducibility:

```bash
.build/release/bhsim movie assemble --frames out/frames --out out/a1.mp4 --encoder ffmpeg
.build/release/bhsim movie assemble --frames out/frames --out out/a2.mp4 --encoder ffmpeg
cmp out/a1.mp4 out/a2.mp4 && echo "ffmpeg: identical files"
.build/release/bhsim movie assemble --frames out/frames --out out/b1.mp4 --encoder avfoundation
.build/release/bhsim movie assemble --frames out/frames --out out/b2.mp4 --encoder avfoundation
ffmpeg -v error -i out/b1.mp4 -f framemd5 - | tail -n +5 > out/b1.md5; ffmpeg -v error -i out/b2.mp4 -f framemd5 - | tail -n +5 > out/b2.md5
cmp out/b1.md5 out/b2.md5 && echo "avfoundation: identical decoded frames"
PATH=/usr/bin:/bin .build/release/bhsim movie assemble --frames out/frames --out out/c.mp4 --encoder ffmpeg; echo "exit $?"   # ffmpeg hidden: exit 6, no fallback
```

Expected: the ffmpeg files are byte-identical, the AVFoundation files decode to identical frames, and the last command exits with 6 (with `auto`, the same command would use AVFoundation).

## 2. Unpadded numbering and errors

```bash
mkdir -p out/odd && cp out/frames/frame_0002.png out/odd/shot_2.png && cp out/frames/frame_0010.png out/odd/shot_10.png
.build/release/bhsim movie assemble --frames out/odd --out out/odd.mp4   # shot_2 then shot_10
.build/release/bhsim movie assemble --frames out/nothing --out out/x.mp4; echo "exit $?"   # names the folder and pattern, exit 2
.build/release/bhsim movie assemble --frames out/frames --out out/assembled.mp4; echo "exit $?"   # exists: exit 2 without --force
```

## 3. Render and assemble an animation (User Story 2)

```bash
.build/release/bhsim movie animate --sweep inclination --from 85 --to 20 --duration 3 --fps 24 \
    --width 640 --height 360 --samples 4 --backend metal --out out/sweep.mp4
```

Expected: `frame k/72` progress, 72 frames in `out/sweep_frames/`, a 3 s movie, `out/sweep.mp4.json`. First and last
frames equal single renders:

```bash
.build/release/bhsim render --inclination 85 --width 640 --height 360 --samples 4 --backend metal --out out/first
cmp out/first.png out/sweep_frames/frame_0001.png && echo identical
```

## 4. Invalid sweep is rejected before rendering (SC-007)

```bash
time .build/release/bhsim movie animate --sweep distance --from 100 --to 1.2 --duration 2 --out out/bad.mp4; echo "exit $?"
```

Expected: under 2 s, exit 2, a message naming the frame, the distance and the valid range; no frames written.

## 5. Resume (SC-006)

Start the animation of step 3 and interrupt it with Ctrl-C part-way, then run the same command again. Expected: the
message says how many frames were kept; only the rest are rendered; `cmp` of every frame with an uninterrupted run
shows no differences.

## 6. Spin sweep keeps brightness consistent (D5)

```bash
.build/release/bhsim movie animate --sweep spin --from 0 --to 0.99 --duration 2 --width 480 --height 270 --out out/spin.mp4
```

Expected: the record shows one `referenceRadiance` for all frames and a brightness change between frames that follows the physics (the disk reaches inward and brightens), with no sudden steps.

## 7. Tests

```bash
swift test
```

Expected: all tests pass; encoder-dependent tests are skipped (not failed) on a machine without the encoder. See
[contracts/cli.md](contracts/cli.md), [contracts/movie-record.schema.json](contracts/movie-record.schema.json) and
[data-model.md](data-model.md).
