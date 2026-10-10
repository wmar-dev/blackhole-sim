#!/usr/bin/env bash
# Regenerates the images and the movie shown in README.md into docs/images/.
#
#   tools/make_readme_assets.sh            # everything
#   tools/make_readme_assets.sh stills     # default.png and spin09-cool-disk.png (CPU, about 1.5 minutes)
#   tools/make_readme_assets.sh movie      # inclination-sweep.mp4 and .webp (GPU, about 5 minutes)
#
# Needs a release build of bhsim (built here), an Apple-silicon GPU for the movie, and for the movie also ffmpeg
# and img2webp (brew install ffmpeg webp). The stills are byte-identical on a given machine; the movie file is
# byte-identical for the same ffmpeg version. Work files go to out/readme-assets/ (not tracked).
set -euo pipefail

cd "$(dirname "$0")/.."
BHSIM=.build/release/bhsim
WORK=out/readme-assets
IMAGES=docs/images
what="${1:-all}"
case "$what" in all|stills|movie) ;; *) echo "usage: $0 [all|stills|movie]" >&2; exit 2 ;; esac

need() { command -v "$1" >/dev/null || { echo "error: $1 is required (brew install $2)" >&2; exit 1; }; }

echo "== building bhsim (release)"
swift build -c release 2>&1 | tail -1
mkdir -p "$WORK" "$IMAGES"

if [[ "$what" == all || "$what" == stills ]]; then
    echo "== default.png: the default scene"
    $BHSIM render --width 1600 --height 900 --samples 9 --out "$WORK/default" >/dev/null
    cp "$WORK/default.png" "$IMAGES/default.png"

    echo "== spin09-cool-disk.png: a = 0.9, 1e9 solar masses, low accretion rate, 80 degrees"
    $BHSIM render --width 1600 --height 900 --samples 9 --spin 0.9 --inclination 80 \
        --mass 1e9 --accretion-rate 1e-4 --out "$WORK/cool" >/dev/null
    cp "$WORK/cool.png" "$IMAGES/spin09-cool-disk.png"
fi

if [[ "$what" == all || "$what" == movie ]]; then
    need ffmpeg ffmpeg
    need img2webp webp

    echo "== inclination-sweep.mp4: 85 to 20 degrees, 5 s, 1280x720, 9 samples per pixel, GPU (resumable)"
    $BHSIM movie animate --sweep inclination --from 85 --to 20 --duration 5 --fps 24 \
        --width 1280 --height 720 --backend metal --encoder ffmpeg --force --out "$WORK/sweep.mp4"
    cp "$WORK/sweep.mp4" "$IMAGES/inclination-sweep.mp4"

    echo "== inclination-sweep.webp: 800 px, 15 fps, quality 80, from the movie"
    rm -rf "$WORK/webp-frames" && mkdir "$WORK/webp-frames"
    ffmpeg -v error -y -i "$WORK/sweep.mp4" -vf "fps=15,scale=800:-1:flags=lanczos" "$WORK/webp-frames/f_%03d.png"
    img2webp -loop 0 -lossy -q 80 -d 66 "$WORK/webp-frames"/f_*.png -o "$IMAGES/inclination-sweep.webp" >/dev/null
fi

echo "== done"
ls -l "$IMAGES" | awk 'NR>1 {printf "%8.2f MB  %s\n", $5/1e6, $9}'
git status --short "$IMAGES" | sed 's/^/changed: /'
