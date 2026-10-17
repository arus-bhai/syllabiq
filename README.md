# Syllabus selection + session init

Drop the `lib/` contents into your existing Flutter project's `lib/` folder
(merge folders if you already have `models/`, `services/`, etc).

## 1. Add dependencies

In `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
  sqflite: ^2.3.0
  path: ^1.9.0
```

Then:

```bash
flutter pub get
```

## 2. Set your API base URL

Edit `kApiBaseUrl` in `lib/main.dart`:
- Android emulator → host machine: `http://10.0.2.2:8000`
- iOS simulator: `http://localhost:8000`
- Physical device: your machine's LAN IP, e.g. `http://192.168.1.20:8000`

## 3. What this gives you

- `models/syllabus.dart` — shared model for API JSON and sqlite rows.
- `db/database_helper.dart` — local sqlite cache (`syllabi` table).
- `services/api_service.dart` — calls `GET /api/admin/syllabi` and
  `POST /api/session/init`.
- `repositories/syllabus_repository.dart` — network-first, sqlite-fallback
  loading logic (works offline once syllabi have been fetched once).
- `screens/syllabus_list_screen.dart` — list UI, pull-to-refresh, tap to
  initialize a session, shows a banner when serving from cache.
- `screens/session_screen.dart` — placeholder landing screen after a
  session is created; this is where the record button + `/api/session/ask/stream`
  integration goes next.

## Notes

- The repository only overwrites the cache on a *successful* fetch, so a
  temporary network failure never wipes out previously cached syllabi.
- `SyllabusRepository.apiService` is exposed publicly so
  `SyllabusListScreen` can reuse the same `ApiService` instance for
  `initSession` without constructing a second one.
