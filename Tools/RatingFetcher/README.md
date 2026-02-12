# OMDb Rating Fetcher

This tool fetches IMDb and Rotten Tomatoes ratings for a list of movies and saves them to a JSON file.

## Setup

1.  **Install Python 3** (if not installed).
2.  **Install Dependencies:**
    ```bash
    pip3 install -r requirements.txt
    ```

## Usage

1.  **Edit `movies.txt`:**
    Add the names of the movies you want to fetch ratings for, one per line.
    
2.  **Run the Script:**
    ```bash
    python3 rating_fetcher.py
    ```
    
3.  **Enter API Key:**
    copy-paste your OMDb API Key when prompted.

4.  **Result:**
    A `ratings.json` file will be generated. Upload this file to your Google Drive!
