
import requests
import json
import urllib.parse
import time

# Exact headers from StalkerClient.swift
USER_AGENT = "Mozilla/5.0 (Unknown; Linux) AppleWebKit/538.1 (KHTML, like Gecko) MAG200 stbapp ver: 4 rev: 734 Mobile Safari/538.1"
X_USER_AGENT = "Model: MAG322; Link: Ethernet"
REFERER = "https://ipro4k.rocd.cc/stalker_portal/c/index.html"

# Configuration from Logs
BASE_URL = "https://ipro4k.rocd.cc/stalker_portal/server/load.php"
MAC = "00:1A:79:7D:7B:F4"

# Encode MAC for Cookie: 00:1A... -> 00%3A1A...
ENCODED_MAC = urllib.parse.quote(MAC)

HEADERS = {
    "User-Agent": USER_AGENT,
    "X-User-Agent": X_USER_AGENT,
    "Referer": REFERER,
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate",
    "Cookie": f"mac={MAC.lower()}; stb_lang=en; timezone=America/Toronto"
}

# Values from Logs
DEVICE_ID = "2734F8111495CB904C3045D58C6EF37BD0F19084F7528F3DAE455287E1688031"
DEVICE_ID2 = "BF73E1F44C0DB1F39A183B9CCB6340ED5897A73EF78606D5DF2180CC4888562D"
SIGNATURE = "63A32EB6C1F804FD0621B840341C12CEDC5F6AFCFC98F0F4C1576BB0A3C8115A"
SN = "686F73JAE8F30"

def do_handshake():
    print("Performing Handshake...")
    params = {
        "type": "stb",
        "action": "handshake",
        "mac": MAC,
        "token": "", 
        "stb_type": "MAG322",
        "sn": SN,
        "device_id": DEVICE_ID,
        "device_id2": DEVICE_ID2,
        "signature": SIGNATURE,
    }
    try:
        response = requests.get(BASE_URL, params=params, headers=HEADERS)
        response.raise_for_status()
        data = response.json()
        
        if "js" in data and "token" in data["js"]:
             token = data["js"]["token"]
             print(f"Handshake Success! Token: {token}")
             return token
        else:
             print("Handshake Failed: Token not found")
             print(data)
             return None
    except Exception as e:
        print(f"Handshake Error: {e}")
        return None

def fetch_categories(token):
    print("\nFetching Categories...")
    params = {
        "type": "vod",
        "action": "get_categories",
        "mac": MAC,
        "token": token,
        "stb_type": "MAG322",
        "sn": SN,
        "device_id": DEVICE_ID,
        "device_id2": DEVICE_ID2,
        "signature": SIGNATURE,
    }
    
    req_headers = HEADERS.copy()
    req_headers["Authorization"] = f"Bearer {token}"
            
    try:
        r = requests.get(BASE_URL, params=params, headers=req_headers)
        data = r.json()
        
        if "js" in data:
            cats = data["js"]
            print(f"Found {len(cats)} categories.")
            
            # Print Formatted Table
            print(f"{'ID':<6} {'Title':<40} {'Alias'}")
            print("-" * 60)
            
            def safe_int(i):
                try: 
                    return int(i)
                except: 
                    return -1
                    
            sorted_cats = sorted(cats, key=lambda x: safe_int(x.get('id', 0)))
            for c in sorted_cats:
                print(f"{c.get('id', '?'):<6} {c.get('title', 'Unknown'):<40} {c.get('alias', '')}")
                
        else:
            print("No categories found in 'js' field.")
            print(data)
            
    except Exception as e:
        print(f"Error fetching categories: {e}")
        try:
            print(f"Status Code: {r.status_code}")
            print(f"Response: {r.text[:500]}") # First 500 chars
        except:
            pass

def do_get_profile(token):
    print("Fetching Profile (Auth Confirmation)...")
    params = {
        "type": "stb",
        "action": "get_profile",
        "mac": MAC,
        "token": token,
        "stb_type": "MAG322",
        "sn": SN,
        "device_id": DEVICE_ID,
        "device_id2": DEVICE_ID2,
        "signature": SIGNATURE,
    }
    req_headers = HEADERS.copy()
    req_headers["Authorization"] = f"Bearer {token}"
            
    try:
        r = requests.get(BASE_URL, params=params, headers=req_headers)
        # print("Profile Response:", r.text[:100])
    except Exception as e:
        print(f"Profile Error: {e}")

# Main Execution
token = do_handshake()
if token:
    do_get_profile(token)
    fetch_categories(token)
