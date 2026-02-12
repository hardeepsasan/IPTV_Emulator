import os
import json
import shutil

# Paths
source_dir = "/Users/hardeepsasan/Documents/GravityProjects/IPTV_Emulator/IPTV_Emulator"
assets_dir = "/Users/hardeepsasan/Documents/GravityProjects/IPTV_Emulator/IPTV Link iOS/Assets.xcassets"

# 1. Ensure assets_dir exists
if not os.path.exists(assets_dir):
    os.makedirs(assets_dir)

# 2. Add Posters (1-15)
for i in range(1, 16):
    asset_name = f"poster_{i}"
    imageset_path = os.path.join(assets_dir, f"{asset_name}.imageset")
    
    # Create directory
    if not os.path.exists(imageset_path):
        os.makedirs(imageset_path)
    
    # Locate source file (try webp, then jpg)
    src_file = os.path.join(source_dir, f"{asset_name}.webp")
    if not os.path.exists(src_file):
        src_file = os.path.join(source_dir, f"{asset_name}.jpg")
        
    if os.path.exists(src_file):
        # Convert to PNG using sips
        dest_filename = f"{asset_name}.png"
        dest_file = os.path.join(imageset_path, dest_filename)
        
        os.system(f"sips -s format png '{src_file}' --out '{dest_file}' > /dev/null 2>&1")
        
        # Create Contents.json (Simplified)
        contents = {
            "images": [
                {
                    "idiom": "universal",
                    "filename": dest_filename,
                    "scale": "1x"
                },
                {
                    "idiom": "universal",
                    "scale": "2x"
                },
                {
                    "idiom": "universal",
                    "scale": "3x"
                }
            ],
            "info": {
                "version": 1,
                "author": "xcode"
            }
        }
        
        with open(os.path.join(imageset_path, "Contents.json"), "w") as f:
            json.dump(contents, f, indent=2)
        print(f"Created PNG imageset for {asset_name}")
    else:
        print(f"Warning: Could not find source for {asset_name}")

print("Done generating poster assets.")
