import requests
import json
import os
from datetime import datetime

# CONFIGURATION
# You need a free TMDB API Key: https://www.themoviedb.org/settings/api
TMDB_API_KEY = os.environ.get("TMDB_API_KEY", "YOUR_API_KEY_HERE") 
OUTPUT_FILE = "featured.json"

def fetch_trending_movies():
    url = f"https://api.themoviedb.org/3/trending/movie/week?api_key={TMDB_API_KEY}"
    
    try:
        response = requests.get(url)
        response.raise_for_status()
        data = response.json()
        
        movies = []
        for item in data.get("results", [])[:20]: # Top 20
            # Filter Logic: Only highly rated, skip adult
            if item.get("vote_average", 0) < 6.0 or item.get("adult"):
                continue
                
            movies.append({
                "title": item.get("title"),
                "year": item.get("release_date", "")[:4],
                "vote_average": item.get("vote_average"),
                "poster_path": item.get("poster_path") # Optional: We use local fuzzy match, but this is good debug info
            })
            
        return movies
    except Exception as e:
        print(f"Error fetching TMDB: {e}")
        return []

def generate_json(movies):
    output = {
        "last_updated": datetime.utcnow().isoformat() + "Z",
        "movies": [m["title"] for m in movies] # Simple list of strings for our app matcher
    }
    
    with open(OUTPUT_FILE, "w") as f:
        json.dump(output, f, indent=2)
        
    print(f"✅ Generated {OUTPUT_FILE} with {len(movies)} movies.")

if __name__ == "__main__":
    print("🎬 Fetching Trending Movies from TMDB...")
    trending = fetch_trending_movies()
    if trending:
        generate_json(trending)
    else:
        print("❌ No movies found. Check API Key.")
