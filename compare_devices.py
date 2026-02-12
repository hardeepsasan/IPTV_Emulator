import json
import os
import hashlib

sim_path = '/Users/hardeepsasan/Library/Developer/CoreSimulator/Devices/DEBAD790-AE65-4B0B-ABE2-9A3E87AAD8F0/data/Containers/Data/Application/BE48EAE3-9331-48E5-B1AC-6BB338C8074D/Library/Caches/IPTVLink_Cache/search_index.json'
atv_path = '/Users/hardeepsasan/Documents/AppleTVEmulator Data/com.hardeepsasan.IPTV-Emulator 2026-02-08 21:52.33.071.xcappdata/AppData/Library/Caches/IPTVLink_Cache/search_index.json'

def load_json(path):
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except Exception as e:
        return f"Error loading {path}: {e}"

print(f"Loading Simulator cache...")
sim_data = load_json(sim_path)
print(f"Loading Apple TV cache...")
atv_data = load_json(atv_path)

if isinstance(sim_data, str) or isinstance(atv_data, str):
    print("One or both loads failed.")
    print(sim_data)
    print(atv_data)
else:
    print(f"Simulator Total Items: {len(sim_data)}")
    print(f"Apple TV Total Items: {len(atv_data)}")
    
    sim_c6 = [x for x in sim_data if str(x.get('category_id')) == '6']
    atv_c6 = [x for x in atv_data if str(x.get('category_id')) == '6']
    
    print(f"\n--- Category 6 Comparison ---")
    print(f"Simulator C6 Count: {len(sim_c6)}")
    print(f"Apple TV C6 Count: {len(atv_c6)}")
    
    sim_ids = set(str(x.get('id','')) for x in sim_c6)
    atv_ids = set(str(x.get('id','')) for x in atv_c6)
    
    only_sim = sim_ids - atv_ids
    only_atv = atv_ids - sim_ids
    
    print(f"IDs only in Simulator: {len(only_sim)}")
    print(f"IDs only in Apple TV: {len(only_atv)}")
    
    if only_sim: print(f"Sample missing IDs in ATV: {list(only_sim)[:5]}")
    if only_atv: print(f"Sample extra IDs in ATV: {list(only_atv)[:5]}")
    
    # Check for content differences in shared IDs
    shared_ids = sim_ids & atv_ids
    diff_count = 0
    
    sim_lookup = {str(x.get('id','')): x for x in sim_c6}
    atv_lookup = {str(x.get('id','')): x for x in atv_c6}
    
    for rid in list(shared_ids)[:500]: # Check first 500 shared
        s_item = sim_lookup[rid]
        a_item = atv_lookup[rid]
        if s_item != a_item:
            diff_count += 1
            if diff_count == 1:
                print(f"\nFirst difference found in ID {rid}:")
                for k in set(s_item.keys()) | set(a_item.keys()):
                    if s_item.get(k) != a_item.get(k):
                        print(f"  Field '{k}': Simulator='{s_item.get(k)}' | ATV='{a_item.get(k)}'")
    
    print(f"\nTotal differences in first 500 checked shared items: {diff_count}")
    
    # Check for corruption (null bytes or strange chars)
    atv_raw = open(atv_path, 'rb').read()
    if b'\x00' in atv_raw:
        print("\nWARNING: Apple TV cache contains NULL bytes!")
    
    # Check if one is a subset or if they are just shifted
    if sim_ids == atv_ids and diff_count == 0:
        print("\nCategory 6 data is IDENTICAL between Simulator and Apple TV device.")
    else:
        print("\nCategory 6 data DIFFERENCES detected.")
