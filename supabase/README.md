# Supabase setup

This migration prepares the first account-backed data the game needs:

- `profiles`: one profile per Supabase Auth user, with a generated unique username.
- `decks`: user-owned deck documents in the same `name` / `leader` / `cards` format as `data/decks/prebuilt/*.json`.
- Row Level Security (RLS): a signed-in user can only read and change their own profile and decks.

## Configure a Supabase project

1. Create a Supabase project and enable **Google** under Authentication → Sign In / Providers.
2. Configure the Google OAuth client and add the game's deployed URL to Supabase Auth's allowed redirect URLs. The Google provider callback is the Supabase Auth callback URL shown in the provider setup. For the desktop build, also add `http://127.0.0.1:54321/**` to the redirect URLs (the game opens the browser and listens on that loopback port for the login to finish).
3. Run migrations in order in the Supabase SQL Editor (or with the Supabase CLI): `202610250001_profiles_and_decks.sql`, `202610250002_harden_public_grants.sql`, `202610250003_deck_limit.sql`, and `202611040001_deck_match_stats.sql`.
4. The browser client is configured in `scripts/net/supabase_auth.gd` with the project URL and publishable key.

The publishable/anon key is expected to be visible in a web client; the RLS policies are the access boundary. Never put a `service_role` or secret key in a Godot export, browser script, or repository.

The game has a Google sign-in on both targets (browser OAuth on the web, a browser round-trip through `scripts/net/supabase_desktop_auth.gd` on desktop) and a guest mode. The "MEUS DECKS" screen (`scripts/ui/deck_builder.gd`, storage in `scripts/net/deck_store.gd`) lets players build, validate, duplicate and delete decks: signed-in players save them to the `decks` table, guests keep them on the device (browser localStorage or `user://decks.json`) and can import them to the cloud after signing in.

Each account (or guest device) can own at most **24 decks**. The limit is enforced three times: the deck screen refuses a 25th deck, `DeckStore.MAX_DECKS` checks it before every save and import, and the `decks_enforce_limit` trigger from `202610250003_deck_limit.sql` is the authority in the database (a hand-made request is rejected with `deck_limit_reached`). Accounts that already hold more than 24 keep their decks but cannot add new ones until they are back under the limit.

Complete player decks appear in the match hub (against the AI, hot-seat and online) as a third section, "MEUS DECKS". For online rooms the client sends the deck's full contents; the match server re-validates it with `DeckDB.check_incoming` and hands both clients the contents under `room:<code>:<seat>` ids, so the opponent can see the deck without it ever being stored. A profile editor does not exist yet.

## Online deck statistics

The deck tiles alternate between their names and the signed-in account's online record. Only completed human-versus-human online matches count, including concessions and draws; AI, hot-seat, guest seats and development-mode matches do not. An authenticated player can still record their result against a guest. Wins, losses and draws sum to total games, and win-rate is wins divided by total games (including draws). A deck with no games has no percentage. Prebuilt decks have separate records by deck id; saved decks have separate records by their database id, so edits keep the history, while a duplicate starts its own. Deleting a deck does not transfer its history to a new deck.

The match server validates each account's access token against Supabase and verifies that a saved deck belongs to the account and matches the played list. Only the authoritative server records the result; RLS lets accounts read only their own rows. Each result is idempotent by match and seat. The server attempts to persist a retry queue before announcing the result and retries failed database writes, including after a server restart. If the queue cannot be written, players are warned and the server retries while the room remains in memory. Place the queue on persistent storage and monitor server errors; losing it before a retry succeeds loses the pending results.

The match server reads these settings from its environment variables or, when a variable is not set, from the git-ignored `.env` file next to `project.godot` (so `servir_web.bat`, `atualizar_e_servir.bat` and a manual start all behave the same). Restart the server after changing them:

- `SUPABASE_URL` (optional): defaults to the project the game client signs in to. A `.env` whose `SUPABASE_URL` names a different project is ignored with a warning, so a stale file never sends tokens or the service key to the wrong project.
- `SUPABASE_PUBLISHABLE_KEY` (optional): defaults to the client's publishable key, which is almost always what you want; used for token and deck validation. Not a secret. The old `SUPABASE_ANON_KEY` name is ignored (a stale value made Supabase refuse every account), so remove it from `.env`.
- `SUPABASE_SERVICE_ROLE_KEY`: the server-only service role key of **that same project**, used to record results. Never include it in a client export, repository, browser code or public logs. Without it accounts are still validated and rooms work, but results stay in the pending queue until the key is set.
- `MATCH_STATS_QUEUE_PATH` (optional): absolute path to the persistent pending-results file. The default is `user://match_stats_pending.json` under Godot's application data directory.

Apply the migration before starting the updated server. A database outage leaves completed results queued and shows a pending warning; the server retries them. Players may see a loading or unavailable state until their account data can be refreshed.

Focused checks: `godot --headless --path . -s tests/deck_stats_ui.gd`, `godot --headless --path . -s tests/deck_stats_queue.gd`, and `node tests/deck_stats_online.mjs`. The last test starts a temporary local fake Supabase and match server; if the Godot executable is not on PATH, set `GODOT_BIN` to its executable path first.
