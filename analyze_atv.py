import json
import os
from collections import Counter

file_path = '/Users/hardeepsasan/Documents/AppleTVEmulator Data/com.hardeepsasan.IPTV-Emulator 2026-02-08 21:52.33.071.xcappdata/AppData/Library/Caches/IPTVLink_Cache/search_index.json'

with open(file_path, 'r') as f:
    data = json.load(f)

c6 = [x for x in data if x.get('category_id') == '6']
c45 = [x for x in data if x.get('category_id') == '45']

def analyze(items, name):
    if not items: return {"label": name, "error": "No items"}
    
    count = len(items)
    avg_desc = sum(len(str(x.get('description', ''))) for x in items) / count
    avg_actors = sum(len(str(x.get('actors', ''))) for x in items) / count
    avg_name = sum(len(str(x.get('name', ''))) for x in items) / count
    
    # Check for long words
    max_word_len = 0
    for x in items:
        for text in [x.get('name',''), x.get('description','')]:
            for word in str(text).split():
                max_word_len = max(max_word_len, len(word))
    
    # Unicode counts
    def has_non_ascii(s): return any(ord(c) > 127 for c in str(s))
    non_ascii = sum(1 for x in items if has_non_ascii(x.get('name','')) or has_non_ascii(x.get('description','')))

    # Null images
    null_images = sum(1 for x in items if not x.get('screenshot_uri'))

    return {
        "label": name,
        "count": count,
        "avg_desc_len": round(avg_desc, 1),
        "avg_name_len": round(avg_name, 1),
        "avg_actors_len": round(avg_actors, 1),
        "max_word_len": max_word_len,
        "non_ascii_count": non_ascii,
        "null_images": null_images
    }

print(json.dumps(analyze(c6, "ATV Cat 6"), indent=2))
print(json.dumps(analyze(c45, "ATV Cat 45"), indent=2))
