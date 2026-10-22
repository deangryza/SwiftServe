from pathlib import Path
import re

root = Path(r'C:\Users\User\my_first\first\MyFirstApp\firstapp\my_app')
backup = Path(__file__).parent / 'before'
pattern = re.compile(r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"")
for original in backup.rglob('*.dart'):
    relative = original.relative_to(backup)
    before = original.read_text(encoding='utf-8')
    after = (root / relative).read_text(encoding='utf-8')
    strings = lambda text: [s for s in pattern.findall(text)
        if 'shared/theme/app_theme.dart' not in s]
    if strings(before) != strings(after):
        raise SystemExit(f'Content changed: {relative}')
    print(f'Content preserved: {relative}')
print('All original screen strings, assets, and import paths preserved.')
