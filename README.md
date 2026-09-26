# PaperSync

PaperSync keeps a digital copy of handwriting from the tablet. The phone app is a quiet notes tool: a library, live capture, a page editor, handwriting search, and pen pairing.

## Layout

- `app/` is the Flutter project.
- `docs/protocol-v1.md` is the v1 pen protocol. `docs/decisions.md` records the choices later phases follow.
- `docs/plans/` is the software build plan (start at [docs/plans/00-index.md](docs/plans/00-index.md)).
- `supabase/migrations/0001_init.sql` is the cloud schema for a new database. `0002_phase4_lockdown.sql` upgrades an existing PaperSync database to those same rules.
- `app/env/example.json` is the template for local defines. Other `app/env/*.json` files stay off the repo.

The earlier files `supabase/migrations/20260926041814_papersync_schema.sql` and `supabase/migrations/20260926041931_papersync_grants_and_fk_indexes.sql` are the previous schema. Apply `0002_phase4_lockdown.sql` to that database. Do not apply `0001_init.sql` and those earlier files to the same empty database.

## Run

```bash
cd app
flutter pub get
flutter run
```

## Cloud backup

The cloud database is the Supabase project [PaperSync](https://supabase.com/dashboard/project/adsemxgqqzefhnqsdbbx/editor). Signed-in users can read and write only their own rows. Writing without an account stays on the phone.

Sign-in is an emailed 6-digit code. The app holds only the project URL and the anon key. The service role key stays on the server.

To back notebooks up, copy `app/env/example.json` to `app/env/dev.json`, fill in the project URL and the anon key, and run:

```bash
cd app
flutter run --dart-define-from-file=env/dev.json
```

Without those two values, sync stays off and notes remain on the phone.

| Table | What it stores |
| --- | --- |
| `notebooks` | Notebook name and default ink color |
| `pages` | Sheets in a notebook, ordered by `page_index`, plus the paper rectangle |
| `strokes` | Pen strokes. `points` is packed bytes, 16 bytes per point |
| `page_text` | Recognized handwriting for search on another device |

## Storage

On a phone, notebooks are encrypted. The key is created on first launch and kept in the iOS Keychain or the Android Keystore. Android backup is off, so a restore cannot bring the boxes back without that key.

The web demo stores the same boxes in the browser without encryption. It is for trying the app, not for private notes.
