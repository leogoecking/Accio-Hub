"""Summarize preserved F4 measurements; never turn axe incomplete into approval."""
import json
from collections import Counter
from pathlib import Path

root = Path(__file__).resolve().parents[2] / 'docs/assets/p1.2f/f4'
phases = ['before-measured', 'palette-before', 'after-reviewed',
          'palette-reviewed', 'additional', 'errors', 'hover']
final = phases[2:]
summary = {}
for phase in phases:
    matrix = json.loads((root / phase / 'matrix.json').read_text())
    axe, statuses, failures = Counter(), Counter(), []
    for row in matrix:
        axe.update(row['axe'])
    for file in sorted((root / phase).glob('*-contrast.json')):
        for node in json.loads(file.read_text())['measurements']:
            statuses[node['status']] += 1
            if node['status'] != 'fail':
                continue
            text, selector = node.get('text'), node['selector']
            exception = ((text == 'hub' and 'wordmark' in selector)
                         or (text == '.' and 'title-stop' in selector)
                         or (text == '·' and 'board-foot' in selector))
            failures.append({'capture': file.stem, 'text': text,
                             'selector': selector, 'ratio': node.get('minimum'),
                             'exception_reviewed': exception})
    summary[phase] = {'states': len(matrix), 'axe': dict(axe),
                      'horizontal_overflow': sum(row['overflow'] for row in matrix),
                      'contrast': dict(statuses), 'failures': failures}
    if phase in final:
        assert axe['violations'] == 0, phase
        assert all(row['exception_reviewed'] for row in failures), phase
assert sum(summary[phase]['states'] for phase in final) == 335
(root / 'summary.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False) + '\n')
print('335 directed states: zero axe violations; incomplete, manual review and exceptions preserved.')
