import json
import re
import os

def fix_catalogs():
    source_file = 'data/localization/zh_TW.json'
    with open(source_file, 'r', encoding='utf-8') as f:
        zh_tw = json.load(f)
    
    locales = ['zh_CN', 'en', 'ja', 'ko']
    for loc in locales:
        file_path = f'data/localization/{loc}.json'
        if not os.path.exists(file_path):
            continue
        with open(file_path, 'r', encoding='utf-8') as f:
            catalog = json.load(f)
        
        for k in catalog:
            if '{0}' in catalog[k] or '{1}' in catalog[k]:
                # Extract all format specifiers from the key
                formats = re.findall(r'%(?:\+|0\d+)?[sdf]', k)
                if not formats:
                    # Maybe it's %% ?
                    continue
                
                translated = catalog[k]
                for i, fmt in enumerate(formats):
                    translated = translated.replace(f'{{{i}}}', fmt)
                
                catalog[k] = translated
        
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(catalog, f, ensure_ascii=False, indent=2)

if __name__ == '__main__':
    fix_catalogs()
    print("Catalogs fixed.")
