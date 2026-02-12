import json
import os
import math

# CORRECT PATH FOUND VIA DEBUG
source_path = "/Users/hardeepsasan/Library/Developer/CoreSimulator/Devices/DEBAD790-AE65-4B0B-ABE2-9A3E87AAD8F0/data/Containers/Data/Application/F48C5E92-D3AE-4634-9015-242E984042CA/Library/Caches/IPTVLink_Cache/search_index.json"
output_dir = "SplitCacheSimulator"

if not os.path.exists(output_dir):
    os.makedirs(output_dir)

try:
    print(f"Reading {source_path}...")
    with open(source_path, 'r') as f:
        data = json.load(f)
    
    if not isinstance(data, list):
        print("Error: Root JSON is not a list. It is:", type(data))
        exit(1)

    total_items = len(data)
    print(f"Total items: {total_items}")
    
    chunk_size = math.ceil(total_items / 10)
    
    for i in range(10):
        start = i * chunk_size
        end = start + chunk_size
        chunk = data[start:end]
        
        filename = f"{output_dir}/chunk_{i+1}.json"
        with open(filename, 'w') as f:
            json.dump(chunk, f, indent=2)
        print(f"Wrote {len(chunk)} items to {filename}")

    print("Done.")

except Exception as e:
    print(f"Error: {e}")
