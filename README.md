# apis

Multi-SQLite search API for a VPS, exposed publicly via Cloudflare Tunnel (no domain needed).

## Folder structure
apis/
├── app.py
├── requirements.txt
├── deploy.sh
├── users_0.db        <- your .db file(s), keep them in the root
└── office.db

## Run
chmod +x deploy.sh
./deploy.sh

At the end, the terminal prints the public API URL and a ready-to-use search link.

## Usage
GET /                              -> status + which db(s)/columns are loaded
GET /search?key=KEY&q=rahul        -> searches across all columns (min 3 characters)
GET /reload?key=KEY                -> reloads .db files after adding new ones, without restarting

## Updating
- After changing code:     sudo systemctl restart apis
- After adding a new .db:  curl "<URL>/reload?key=<KEY>"
- Logs:                    sudo journalctl -u apis -f
                           sudo journalctl -u cf-tunnel -f

## Environment setup

No manual setup needed — `deploy.sh` automatically generates a random
API key and saves it to `.env` on first run. The key is printed in the
terminal at the end of deployment, inside the ready-to-use search link.

To use your own key instead, copy the sample file and edit it before
running `deploy.sh`:

    cp sample.env .env

See `sample.env` for the expected format.

## Notes
- The trycloudflare.com URL changes if the tunnel service restarts.
- `.env` holds `API_KEYS` — never commit or share this file publicly.
