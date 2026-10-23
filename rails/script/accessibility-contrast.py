"""QA: compose computed foreground against rendered background under glyph locations.
No foreground color is inferred from antialiased glyph pixels. No dependencies added.
"""
import json
import math
import sys
from pathlib import Path
from PIL import Image, ImageChops


def luminance(rgb):
    values = [v / 255 for v in rgb]
    linear = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in values]
    return sum(v * k for v, k in zip(linear, [.2126, .7152, .0722]))


def contrast(a, b):
    lo, hi = sorted([luminance(a), luminance(b)])
    return (hi + .05) / (lo + .05)


def analyze(base):
    data = json.loads(base.with_suffix('.json').read_text())
    before = Image.open(base.with_suffix('.png')).convert('RGB')
    background = Image.open(base.with_name(base.name + '-background.png')).convert('RGB')
    assert before.size == background.size == (data['viewport']['width'], data['viewport']['height']), 'DPR/size mismatch'
    changed = ImageChops.difference(before, background)
    output = []
    for node in data['nodes']:
        result = {k: node.get(k) for k in ['kind', 'selector', 'text', 'required', 'rgba']}
        if node.get('disabled'):
            result.update(status='not_applicable', reason='inactive control exception')
        elif node['opacity'] != 1 or node['unknown'] or node.get('placeholderOpacity', 1) != 1:
            result.update(status='inconclusive', reason='group opacity/filter requires separate composition')
        elif node['kind'] in ['boundary', 'focus']:
            # Native widgets, focus corners and control boundary semantics need directed review.
            # Keep them separate from text, rather than reporting a speculative success.
            result.update(status='manual_review', reason='boundary/focus directed measurement required')
        else:
            samples = []
            for r in node['rects']:
                left, top = max(0, math.ceil(r['x'])), max(0, math.ceil(r['y']))
                right, bottom = min(before.width, math.floor(r['x'] + r['width'])), min(before.height, math.floor(r['y'] + r['height']))
                for y in range(top, bottom):
                    for x in range(left, right):
                        if max(changed.getpixel((x, y))) < 3:
                            continue
                        bg = background.getpixel((x, y))
                        alpha = node['rgba'][3] / 255
                        fg = [alpha * c + (1 - alpha) * b for c, b in zip(node['rgba'][:3], bg)]
                        samples.append((contrast(fg, bg), bg))
            if samples:
                minimum, bg = min(samples)
                result.update(status='fail' if minimum < node['required'] else 'measured_pass', minimum=round(minimum, 3),
                              samples=len(samples), background_at_worst=list(bg), method='computed foreground + rendered background at changed glyph/stroke positions')
            else:
                result.update(status='inconclusive', reason='no isolated glyph/stroke pixels')
        output.append(result)
    return {'viewport': data['viewport'], 'theme': data['theme'], 'wallpaper': data['wallpaper'], 'accent': data['accent'], 'measurements': output}


if __name__ == '__main__':
    for name in sys.argv[1:]:
        base = Path(name).with_suffix('')
        result = analyze(base)
        base.with_name(base.name + '-contrast.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
        failures = [r for r in result['measurements'] if r['status'] == 'fail']
        print(json.dumps({'capture': base.name, 'measured_failures': len(failures), 'minimum': min([r['minimum'] for r in result['measurements'] if 'minimum' in r], default=None)}))
