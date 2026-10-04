"""Assemble Blender's twelve walk preview renders into a looping GIF (requires Pillow)."""
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
paths = sorted((root / 'art/previews/salvage_robot_walk').glob('*.png'))
if len(paths) != 12:
    raise RuntimeError('Run tools/build_player_robot.py first; expected twelve preview frames.')
frames = [Image.open(path).convert('RGB') for path in paths]
out = root / 'art/previews/salvage_robot_walk.gif'
frames[0].save(out, save_all=True, append_images=frames[1:], duration=[70, 60, 70]*4,
               loop=0, disposal=2)
for frame in frames:
    frame.close()
print(out)
