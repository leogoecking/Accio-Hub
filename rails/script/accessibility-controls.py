import json
import sys
sys.dont_write_bytecode = True
from pathlib import Path
from PIL import Image
import importlib.util

spec = importlib.util.spec_from_file_location('contrast', Path(__file__).with_name('accessibility-contrast.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
contrast = module.contrast
folder = Path(sys.argv[1])
results = []
for name in json.loads((folder / 'captures.json').read_text()):
    data = json.loads((folder / (name + '.json')).read_text())
    image = Image.open(folder / (name + '-background.png')).convert('RGB')
    for node in data['controls'] + data['focus']:
        r = node['rects'][0]
        if node['kind'] == 'boundary':
            offset = 0
            points = [(r['x'] + r['width'] * q, r['y'] + .5) for q in [.4, .5, .6]]
        else:
            offset = node['offset'] + node['width'] / 2
            points = [(r['x'] + r['width'] / 2, r['y'] - offset), (r['x'] + r['width'] / 2, r['y'] + r['height'] + offset)]
        ratios = []
        for x, y in points:
            if not (0 <= x < image.width and 2 <= y < image.height - 2):
                continue
            bg = image.getpixel((int(x), int(y)))
            alpha = node['rgba'][3] / 255
            fg = [c * alpha + b * (1 - alpha) for c, b in zip(node['rgba'][:3], bg)]
            # Border contrasts with its immediately adjacent outer surface too.
            outer = image.getpixel((int(x), max(0, int(y) - 2))) if node['kind'] == 'boundary' else bg
            ratios.append(min(contrast(fg, bg), contrast(fg, outer)))
        results.append({'capture': name, 'kind': node['kind'], 'selector': node['selector'], 'color': node['rgba'],
                        'minimum': round(min(ratios), 3) if ratios else None, 'required': 3,
                        'status': ('measured_pass' if min(ratios) >= 3 else 'fail') if ratios else 'inconclusive'})
(folder / 'measurements.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({'measurements': len(results), 'failures': sum(r['status'] == 'fail' for r in results)}))
