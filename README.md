# Linux CRT Overscan

A small command line tool that compensates for CRT overscan on Linux by shrinking the
desktop into the visible tube area with an `xrandr --transform`. It changes only the
screen mapping, not the resolution, so window layouts are unaffected.

Built for an AMD `amdgpu` box driving a 4:3 standard definition CRT over a
HDMI to component scaler, but it works with any X output and any resolution.

## How it works

CRTs overscan, so the outer edge of the image falls behind the bezel. This tool
applies a centered scale plus translate transform that pulls the desktop inward
until the edges clear the bezel. The center is derived from the framebuffer size,
so the math is correct at any resolution. Separate horizontal and vertical fill
fractions and pixel offsets handle tubes that overscan unevenly or sit off center.

## Install

Copy the script somewhere on your `PATH` and make it executable:

```bash
scp overscan.sh user@host:~/bin/overscan
ssh user@host 'chmod +x ~/bin/overscan'
```

It auto resolves `DISPLAY` and `XAUTHORITY` and auto detects the first connected
output, so it can be run over SSH or from a login autostart.

## Usage

```
overscan <fill>            apply uniform fill, e.g. 0.85 (85% of the tube)
overscan save <fill>       apply and persist via autostart (login replay)
overscan restore           apply the saved settings (what autostart runs)
overscan reset | none      remove the live transform (saved values kept)
overscan unsave | clear    remove the persisted config and autostart
```

### Options

```
-x FX   horizontal fill fraction (overrides <fill> for X)
-y FY   vertical fill fraction (overrides <fill> for Y)
-r WxH  set framebuffer and mode to this resolution (default: current)
-o OUT  xrandr output name (default: first connected output)
-d DX   horizontal offset in pixels, positive is right
-e DY   vertical offset in pixels, positive is down
-f FILT bilinear or nearest (default: bilinear)
-n      dry run: print the command, do not execute
```

`<fill>` is a fraction between 0 and 1. Lower values shrink the image more.
Use `-x` and `-y` when the tube overscans differently on each axis, and
`-d` and `-e` to recenter the picture.

## Examples

```bash
overscan reset                          # baseline, observe the raw overscan
overscan -n 0.85                        # dry run, print the computed matrix
overscan 0.85                           # 85% on both axes
overscan -x 0.86 -y 0.82 0.85           # different horizontal and vertical fill
overscan -d 10 -e 8 0.895               # nudge 10 px right, 8 px down
overscan save -x 0.86 -y 0.82 -d 10 0.895   # apply and persist
```

## Calibration

1. `overscan reset` to see how much each edge is cut off.
2. Apply a fill fraction and adjust until the edges just clear the bezel.
3. Add `-x` / `-y` if one axis overscans more than the other.
4. Add `-d` / `-e` if the picture sits off center.
5. `overscan save ...` with the final flags to persist it.

To verify persistence: `overscan reset` then `overscan restore` should reproduce
the saved result.

## Persistence

`save` writes the resolved parameters to `~/.config/overscan.conf` and installs an
autostart entry that runs `overscan restore` at login. The script is the single
source of truth, so to change persisted values just run `save` again. `unsave`
removes the config and the autostart.

## Notes

- When a transform plus offset pushes the logical output rectangle past the
  framebuffer, xrandr prints `specified screen not large enough`. With panning set
  this is a warning, not a failure, and the transform still applies. The region
  that spills past the framebuffer is the off screen overscan area you do not want.
- This assumes a single display. It sets the framebuffer and panning to one
  output, which would disrupt a multi monitor layout. Use `-o` and take care.
- `-r` can only select a resolution the output already advertises. To use a mode
  the hardware does not expose, add it first with `cvt` and `xrandr --newmode`
  and `--addmode`.

## Wayland

This tool is X11 only. It is built entirely on `xrandr --transform`, and under
Wayland `xrandr` talks only to XWayland, so it cannot affect the real output. It
will silently do nothing on a Wayland session.

There is also no drop in replacement, and the reason is worth understanding.

- The affine transform this script depends on is not exposed by any compositor.
  The Wayland output protocols define only 8 discrete transforms, the rotations
  and flips. There is no protocol or config knob for an arbitrary scale plus
  translate matrix anywhere in the ecosystem.
- This is a missing feature, not a missing capability. Every Wayland compositor
  is already a GPU compositor and applies transforms to surfaces every frame, so
  shrinking and centering an output is trivial for it to do. Nobody exposes it
  because the common cases, rotation and scaling, are already covered and CRT
  overscan is niche.
- It is this way by design. X had a single global server with a neutral config
  surface that any tool could poke. Wayland removed that on purpose: the
  compositor owns all output policy, and the protocols standardize only what is
  common across compositors, so there is no neutral place to inject a transform.

If you are on Wayland, the realistic routes to overscan compensation are:

1. Push the shrink out of the display server, into the HDMI to component scaler
   (most have a zoom or underscan control) or the TV service menu (horizontal and
   vertical size). This is compositor independent and works everywhere, including
   X, Wayland, and a bare console, with no script at all. Recommended.
2. Use the amdgpu KMS underscan connector properties (`underscan`,
   `underscan hborder`, `underscan vborder`), which shrink the scanout in
   hardware below the display server. Compositor support for setting them varies:
   KDE and KWin are the most likely to expose a built in overscan control, while
   wlroots based compositors and GNOME generally do not. These borders are
   symmetric, so they can shrink but cannot recenter an off center tube the way
   the `-d` and `-e` offsets here can.
