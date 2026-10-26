# Supabase setup

This migration prepares the first account-backed data the game needs:

- `profiles`: one profile per Supabase Auth user, with a generated unique username.
- `decks`: user-owned deck documents in the same `name` / `leader` / `cards` format as `data/decks/prebuilt/*.json`.
- Row Level Security (RLS): a signed-in user can only read and change their own profile and decks.

## Configure a Supabase project

1. Create a Supabase project and enable **Google** under Authentication → Sign In / Providers.
2. Configure the Google OAuth client and add the game's deployed URL to Supabase Auth's allowed redirect URLs. The Google provider callback is the Supabase Auth callback URL shown in the provider setup. For the desktop build, also add `http://127.0.0.1:54321/**` to the redirect URLs (the game opens the browser and listens on that loopback port for the login to finish).
3. Run migrations in order in the Supabase SQL Editor (or with the Supabase CLI): `202610250001_profiles_and_decks.sql`, then `202610250002_harden_public_grants.sql`, then `202610250003_deck_limit.sql`.
4. The browser client is configured in `scripts/net/supabase_auth.gd` with the project URL and publishable key.

The publishable/anon key is expected to be visible in a web client; the RLS policies are the access boundary. Never put a `service_role` or secret key in a Godot export, browser script, or repository.

The game has a Google sign-in on both targets (browser OAuth on the web, a browser round-trip through `scripts/net/supabase_desktop_auth.gd` on desktop) and a guest mode. The "MEUS DECKS" screen (`scripts/ui/deck_builder.gd`, storage in `scripts/net/deck_store.gd`) lets players build, validate, duplicate and delete decks: signed-in players save them to the `decks` table, guests keep them on the device (browser localStorage or `user://decks.json`) and can import them to the cloud after signing in.

Each account (or guest device) can own at most **24 decks**. The limit is enforced three times: the deck screen refuses a 25th deck, `DeckStore.MAX_DECKS` checks it before every save and import, and the `decks_enforce_limit` trigger from `202610250003_deck_limit.sql` is the authority in the database (a hand-made request is rejected with `deck_limit_reached`). Accounts that already hold more than 24 keep their decks but cannot add new ones until they are back under the limit.

Complete player decks appear in the match hub (against the AI, hot-seat and online) as a third section, "MEUS DECKS". For online rooms the client sends the deck's full contents; the match server re-validates it with `DeckDB.check_incoming` and hands both clients the contents under `room:<code>:<seat>` ids, so the opponent can see the deck without it ever being stored. A profile editor does not exist yet. The match server also does not yet validate access tokens, so room creation and matchmaking are still anonymous. It must validate Supabase user access tokens before trusting an account identity.

