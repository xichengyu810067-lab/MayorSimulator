import os, re

def search():
    for root, _, files in os.walk('scripts/app'):
        for f in files:
            if f.endswith('.gd'):
                path = os.path.join(root, f)
                with open(path, 'r', encoding='utf-8') as file:
                    for i, line in enumerate(file):
                        if re.search(r'\.(?:text|tooltip_text|placeholder_text)\s*=\s*"[^"]*[\u4e00-\u9fa5]', line):
                            print(f'{path}:{i+1}:{line.strip()}')

    for root, _, files in os.walk('ui'):
        for f in files:
            if f.endswith('.gd'):
                path = os.path.join(root, f)
                with open(path, 'r', encoding='utf-8') as file:
                    for i, line in enumerate(file):
                        if re.search(r'\.(?:text|tooltip_text|placeholder_text)\s*=\s*"[^"]*[\u4e00-\u9fa5]', line):
                            print(f'{path}:{i+1}:{line.strip()}')
search()
