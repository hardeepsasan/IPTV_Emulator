import requests
import json
import os
import time
from tqdm import tqdm

# Configuration
INPUT_FILE = "movies.txt"
OUTPUT_FILE = "ratings.json"
OMDB_BASE_URL = "http://www.omdbapi.com/"

def get_api_key():
    """Ask user for API Key if not set in env."""
    api_key = os.environ.get("OMDB_API_KEY")
    if not api_key:
        print("\n=== OMDb Rating Fetcher ===")
        print("Please enter your OMDb API Key (Get one at http://www.omdbapi.com/apikey.aspx)")
        api_key = input("API Key: ").strip()
    return api_key

def fetch_rating(movie_name, api_key):
    """Fetch rating for a single movie."""
    params = {
        "apikey": api_key,
        "t": movie_name
    }
    
    try:
        response = requests.get(OMDB_BASE_URL, params=params, timeout=10)
        response.raise_for_status()
        data = response.json()
        
        if data.get("Response") == "True":
            # Extract Ratings
            imdb = data.get("imdbRating", "N/A")
            rt = "N/A"
            
            for source in data.get("Ratings", []):
                if source["Source"] == "Rotten Tomatoes":
                    rt = source["Value"]
                    break
            
            return {
                "imdb": imdb,
                "rt": rt,
                "year": data.get("Year", ""),
                "poster": data.get("Poster", "")
            }
        else:
            return None # Not found
            
    except Exception as e:
        print(f"Error fetching '{movie_name}': {e}")
        return None

def main():
    api_key = get_api_key()
    
    # Read Movie List
    if not os.path.exists(INPUT_FILE):
        print(f"Error: {INPUT_FILE} not found!")
        return

    with open(INPUT_FILE, "r") as f:
        movies = [line.strip() for line in f if line.strip()]

    print(f"\nFetching ratings for {len(movies)} movies...")
    
    ratings_db = {}
    
    # Progress Bar Loop
    for movie in tqdm(movies):
        data = fetch_rating(movie, api_key)
        if data:
            ratings_db[movie] = data
        time.sleep(0.1) # Be nice to the API

    # Save JSON
    with open(OUTPUT_FILE, "w") as f:
        json.dump(ratings_db, f, indent=2)
        
    print(f"\nDone! Ratings saved to {OUTPUT_FILE}")
    print(f"Success Rate: {len(ratings_db)}/{len(movies)}")

if __name__ == "__main__":
    main()
