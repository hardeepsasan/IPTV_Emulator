import json

file_path = '/Users/hardeepsasan/Documents/AppleTVEmulator Data/com.hardeepsasan.IPTV-Emulator 2026-02-08 21:52.33.071.xcappdata/AppData/Library/Caches/IPTVLink_Cache/search_index.json'

with open(file_path, 'r') as f:
    data = json.load(f)

c6 = [x for x in data if str(x.get('category_id')) == '6']

print("Searching for descriptions >= 1000 chars...")
for x in c6:
    desc = str(x.get('description', ''))
    if len(desc) >= 1000:
        print(f"FOUND: '{x.get('name')}' (ID: {x.get('id')}) has {len(desc)} characters.")
        print(f"First 100 chars: {desc[:100]}...")
