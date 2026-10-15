"""Joins the two reels into the final ad -> testflight/biomap-final-ad.mp4.

The rename story (evolve.py) is cut just before its own end card, then crossfades into the TestFlight
walkthrough (testflight.py), whose closing card carries the link. Both reels use the same background,
so the join is a plain 0.6 s crossfade of picture and sound. Run evolve.py and testflight.py first.

  python3 final_ad.py
"""
import pathlib, shutil, subprocess

HERE = pathlib.Path(__file__).parent
D = HERE / 'testflight'
A, B = D / 'birdmap-is-now-biomap.mp4', D / 'testflight-is-live.mp4'
OUT = D / 'biomap-final-ad.mp4'
CUT, FADE = 20.9, 0.6      # keep the story up to 20.9 s (just after "New name." fades), crossfade 0.6 s


def main():
    fc = (f'[0:v]trim=0:{CUT},setpts=PTS-STARTPTS[v0];[1:v]setpts=PTS-STARTPTS[v1];'
          f'[v0][v1]xfade=transition=fade:duration={FADE}:offset={CUT - FADE}[v];'
          f'[0:a]atrim=0:{CUT},asetpts=PTS-STARTPTS[a0];[1:a]asetpts=PTS-STARTPTS[a1];[a0][a1]acrossfade=d={FADE}[a]')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', str(A), '-i', str(B), '-filter_complex', fc, '-map', '[v]', '-map', '[a]',
                    '-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-profile:v', 'high', '-pix_fmt', 'yuv420p',
                    '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
                    '-c:a', 'aac', '-b:a', '192k', '-ar', '44100', '-movflags', '+faststart', str(OUT)], check=True)
    shutil.copy(D / 'birdmap-is-now-biomap-cover.png', D / 'biomap-final-ad-cover.png')   # cover = the name reveal
    r = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(OUT)], capture_output=True, text=True)
    print(OUT.name, r.stdout.strip(), 's', f'{OUT.stat().st_size / 1e6:.1f} MB')


if __name__ == '__main__':
    main()
