import json

file_path = '/Users/hardeepsasan/Documents/AppleTVEmulator Data/com.hardeepsasan.IPTV-Emulator 2026-02-08 21:52.33.071.xcappdata/AppData/Library/Caches/IPTVLink_Cache/search_index.json'

with open(file_path, 'r') as f:
    data = json.load(f)

c6 = [x for x in data if str(x.get('category_id')) == '6']

def sanitize(d):
    if not d: return ""
    d_str = str(d)
    idx = d_str.find("http")
    if idx != -1:
        d_str = d_str[:idx]
    
    max_chars = 600
    if len(d_str) > max_chars:
        d_str = d_str[:max_chars] + "..."
    return d_str.strip()

old_lens = [len(str(x.get('description',''))) for x in c6]
new_lens = [len(sanitize(x.get('description',''))) for x in c6]

avg_old = sum(old_lens) / len(old_lens)
avg_new = sum(new_lens) / len(new_lens)
max_old = max(old_lens)
max_new = max(new_lens)

print(f"Items processed: {len(c6)}")
print(f"Average Description Length: {avg_old:.1f} -> {avg_new:.1f}")
print(f"Maximum Description Length: {max_old} -> {max_new}")

# Sample check for the long one
pushpa = [x for x in c6 if x.get('id') == '22365'][0]
print(f"\nExample 'Pushpavalli' (ID: 22365):")
print(f"  Original Length: {len(str(pushpa.get('description')))}")
print(f"  Sanitized Length: {len(sanitize(pushpa.get('description')))}")

# Sample check for URL one
hasratein = [x for x in c6 if x.get('id') == '47548'][0]
print(f"\nExample 'Hasratein' (URL outlier ID: 47548):")
print(f"  Original: {hasratein.get('description')}")
print(f"  Sanitized: {sanitize(hasratein.get('description'))}")
