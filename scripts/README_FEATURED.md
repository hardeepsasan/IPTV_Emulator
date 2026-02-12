# Featured Movies Automation

This script fetches "Trending Movies" from TMDB and updates `featured.json`.

## Setup
1.  **Get a TMDB API Key**: [Sign up here](https://www.themoviedb.org/settings/api) (It's free).
2.  **Install Python Requests**: `pip install requests`

## Manual Run
```bash
export TMDB_API_KEY="your_api_key"
python3 generate_featured_json.py
```
This will create `featured.json`.

## GitHub Action Automation (Recommended)
To run this **daily** automatically and host the JSON on GitHub Gist (or this repo):

1.  Create `.github/workflows/update_featured.yml`:

```yaml
name: Update Featured Movies
on:
  schedule:
    - cron: '0 0 * * *' # Daily at midnight
  workflow_dispatch:

jobs:
  update-featured:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.9'
      - name: Install dependencies
        run: pip install requests
      - name: Run script
        env:
          TMDB_API_KEY: ${{ secrets.TMDB_API_KEY }}
        run: python3 scripts/generate_featured_json.py
      - name: Commit and Push
        run: |
          git config --global user.name 'GitHub Action'
          git config --global user.email 'action@github.com'
          git add featured.json
          git commit -m "Update featured movies" || exit 0
          git push
```

2.  Add `TMDB_API_KEY` to your **GitHub Repository Secrets**.
3.  The JSON will be available at:
    `https://raw.githubusercontent.com/[YOUR_USERNAME]/[REPO_NAME]/main/featured.json`
4.  Update `FeaturedContentManager.swift` with this URL.
