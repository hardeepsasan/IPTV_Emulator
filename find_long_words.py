import json

file_path = '/Users/hardeepsasan/Documents/AppleTVEmulator Data/com.hardeepsasan.IPTV-Emulator 2026-02-08 21:52.33.071.xcappdata/AppData/Library/Caches/IPTVLink_Cache/search_index.json'

with open(file_path, 'r') as f:
    data = json.load(f)

c6 = [x for x in data if str(x.get('category_id')) == '6']

print("Searching for words >= 50 chars...")
for x in c6:
    for text in [x.get('name', ''), x.get('description', '')]:
        words = str(text).split()
        for w in words:
            if len(w) >= 50:
                print(f"FOUND: '{w}' (length {len(w)}) in item '{x.get('name')}' (ID: {x.get('id')})")
