# PaperSync

PaperSync keeps a digital copy of handwriting from the tablet. The phone app is a quiet notes tool: a library, live capture, a page editor, handwriting search, and pen pairing.

## Layout

- `app/` is the Flutter project.
- `docs/` records the v1 pen protocol and the decisions later phases build on.
- `app/env/example.json` is the template for local defines. Other `app/env/*.json` files stay off the repo.

## Run

```bash
cd app
flutter pub get
flutter run
```

To back notebooks up, copy `app/env/example.json` to `app/env/dev.json`, fill in the project URL and the anon key, and run:

```bash
cd app
flutter run --dart-define-from-file=env/dev.json
```

Without those two values, sync stays off and notes remain on the phone. The service role key is not part of the app.

## Storage

On a phone, notebooks are encrypted. The key is created on first launch and kept in the iOS Keychain or the Android Keystore. Android backup is off, so a restore cannot bring the boxes back without that key.

The web demo stores the same boxes in the browser without encryption. It is for trying the app, not for private notes.
