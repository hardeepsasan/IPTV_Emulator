import json
import os
from collections import Counter

file_path = '/Users/hardeepsasan/Library/Developer/CoreSimulator/Devices/DEBAD790-AE65-4B0B-ABE2-9A3E87AAD8F0/data/Containers/Data/Application/BE48EAE3-9331-48E5-B1AC-6BB338C8074D/Library/Caches/IPTVLink_Cache/search_index.json'

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
    
    empty_desc = sum(1 for x in items if not x.get('description'))
    empty_actors = sum(1 for x in items if not x.get('actors'))
    empty_genres = sum(1 for x in items if not x.get('genres_str'))
    
    unique_images = len(set(x.get('screenshot_uri','') for x in items if x.get('screenshot_uri')))
    
    # Check for long words (rendering bottleneck)
    max_word_len = 0
    for x in items:
        for text in [x.get('name',''), x.get('description','')]:
            for word in str(text).split():
                max_word_len = max(max_word_len, len(word))
    
    # Duration
    try:
        durations = [float(x.get('duration', 0) or 0) for x in items]
        avg_dur = sum(durations) / count
        max_dur = max(durations)
    except:
        avg_dur = 0
        max_dur = 0
    
    # Unicode counts
    def has_non_ascii(s): return any(ord(c) > 127 for c in str(s))
    non_ascii = sum(1 for x in items if has_non_ascii(x.get('name','')) or has_non_ascii(x.get('description','')))

    # Added dates
    added_dates = [str(x.get('added',''))[:10] for x in items]
    most_common_date = Counter(added_dates).most_common(5)

    return {
        "label": name,
        "count": count,
        "avg_desc_len": round(avg_desc, 1),
        "avg_name_len": round(avg_name, 1),
        "avg_actors_len": round(avg_actors, 1),
        "empty_desc": empty_desc,
        "empty_actors": empty_actors,
        "empty_genres": empty_genres,
        "unique_images": f"{unique_images}/{count}",
        "max_word_len": max_word_len,
        "avg_duration": round(avg_dur, 1),
        "max_duration": max_dur,
        "non_ascii_count": non_ascii,
        "top_dates": most_common_date
    }

print("=== ANALYSIS START ===")
print(json.dumps(analyze(c6, "Category 6 (Bollywood)"), indent=2))
print(json.dumps(analyze(c45, "Category 45 (International)"), indent=2))
print("=== ANALYSIS END ===")
