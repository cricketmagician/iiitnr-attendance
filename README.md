# IIITNR Scholar Attendance & Leave module

Code for the PhD/MTech attendance and leave feature in the IIITNR app, built to the
specification "IIITNR App – Scholar Attendance & Leave Module".

- `backend/`: a small service (Python, FastAPI) that works with the institute's existing SQL server
  (MySQL/MariaDB or PostgreSQL). Its tables are all prefixed `att_` / `leave_`.
- `flutter/lib/scholar_attendance/`: screens to drop into the existing Flutter app (Android and iOS).

## What it does

| Rule | Where it is enforced |
| --- | --- |
| Institute-email login only | Backend checks the app's existing login token (`@iiitnr.edu.in`) |
| One phone per scholar, one scholar per phone | Phone key registered on first login; every request is signed with it. A new phone needs central-admin approval, which switches the old phone off |
| Face check | Phone's own Face ID / face unlock (fingerprint if no face unlock), biometric only |
| Anywhere on campus, any campus Wi-Fi | Server checks the request came from a campus network range |
| Windows 9:30–10:00, 12:45–1:30, 5:45–6:30, Mon–Fri except holidays | Server time only; windows and holidays editable by the admin |
| Reminders | Local notifications at each window's start and 10 min before it closes; skipped on weekends, holidays, leave days and sessions already marked |
| At least 2 of 3 sessions = present | Day close at 6:35 pm sends days with fewer to the central admin, who marks Present (remark required, shown P*) or Absent |
| Leave: supervisor approves, central admin confirms | Dean (R&I) step added only for academic duty beyond 30 days |
| Leave rules (same for PhD and MTech) | 30 days per leave year from joining (≤15 medical); ≤15 per semester; institute scholars ≤5 days at a stretch; maternity 180 / paternity 15 once; academic duty 30, up to 60 with the Dean; weekends and holidays not counted; no carry-forward, admin can add days by hand |

All rule numbers are admin settings (`PUT /admin/settings/rules`), so a rule change needs no code change.

## Backend setup (on the institute server)

```bash
cd backend
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env        # fill in the database URL, login-token secret/key, SMTP
python -m scripts.init_db   # creates att_* and leave_* tables
python -m scripts.import_people people.csv   # scholars and staff, see scripts/people_example.csv
uvicorn app.main:app --host 127.0.0.1 --port 8040 --workers 2
```

Day close (creates the admin's review list and e-mails it), Monday to Friday after the evening window:

```cron
35 18 * * 1-5  cd /srv/att/backend && .venv/bin/python -m app.jobs close-day
```

nginx in front (the client IP must come from nginx, not from the phone):

```nginx
location /attendance/ {
    proxy_pass http://127.0.0.1:8040/;          # trailing slash strips /attendance
    proxy_set_header X-Forwarded-For $remote_addr;  # overwrite, never append
    proxy_set_header Authorization $http_authorization;
    client_max_body_size 8m;
}
```

### Campus networks
The server accepts marking only from campus network ranges. Add them in the app (Admin > More >
Campus networks) or via `POST /admin/settings/campus-networks`:
- If phones on campus Wi-Fi reach the server directly over the LAN, add the Wi-Fi subnets (e.g. `10.20.0.0/16`).
- If they reach it through the institute's public address (NAT), add that public IP (e.g. `203.x.x.x/32`).
- Do not add the VPN range, or scholars could mark from home over the VPN.

Check with a phone on each campus Wi-Fi: a refused attempt shows its IP under `GET /admin/attempts?date=`.

### People
`scripts/import_people.py` reads a CSV (re-runnable, matches on email). Roles: `scholar`, `supervisor`,
`hod`, `dean_ri`, `admin`. `joining_date` starts each scholar's leave year; `funding`
(`institute`/`external`) decides whether the 5-days-at-a-stretch rule applies. If the IIITNR database
already has this data, a database view or a nightly export to this CSV keeps it in step.

## Flutter setup
See `flutter/PLATFORM_SETUP.md`: copy the folder, add the packages in `flutter/pubspec_additions.yaml`,
add the Android/iOS permission lines, and open `ScholarAttendanceEntry` from a menu item.
The module shows scholars: Today (mark), Month, Leave. Staff see only what their roles allow:
Approve leave (supervisor), Dean (R&I), Confirm leave, Day reviews and More (central admin), Register.

## API summary
| Method | Path | Who |
| --- | --- | --- |
| GET | /att/me | anyone |
| GET | /att/device/status, POST /att/device/register | scholar |
| GET | /att/today, /att/schedule, /att/month?m=YYYY-MM, /att/reviews | scholar |
| POST | /att/mark, /att/reviews/{id}/reason | scholar |
| GET/POST | /leave/types, /leave/mine, /leave, /leave/{id}/withdraw | scholar |
| GET | /leave/queue?role=supervisor\|dean\|admin | approvers |
| POST | /leave/{id}/approve, /leave/{id}/dean, /leave/{id}/confirm, /leave/{id}/cancel | supervisor, Dean (R&I), admin |
| GET/POST | /admin/reviews, /admin/reviews/{id}, /admin/run-day-close | admin |
| GET/POST | /admin/devices, /admin/devices/{id}, /admin/devices/{id}/revoke | admin |
| POST/GET | /admin/leave-adjustments | admin |
| GET/PUT/POST/DELETE | /admin/settings, /settings/rules, /settings/windows, /settings/campus-networks, /admin/holidays | admin |
| GET | /admin/register?m=YYYY-MM[&format=csv] | admin (all), HoD (department), supervisor (own scholars) |

Interactive API docs: `http://<server>:8040/docs`.

## What was tested
- Backend: 34 automated tests pass (`cd backend && pytest`). They cover the device lock (second
  phone, shared phone, revoked phone, proof of key), unsigned, tampered, replayed and stale requests,
  off-campus and spoofed IP headers, window edges, weekends and holidays, the two-session day rule and
  admin review, every leave rule, the supervisor → (Dean) → admin flow, late leave turning a review into
  leave, cancellation, balance adjustments, settings, register visibility and CSV.
- The setup scripts, day-close job and server were also run end to end on SQLite.
- **Not compiled here:** the Flutter code could not be built in this environment (no Flutter SDK
  available). Expect small fixes on the first `flutter build` if package versions differ. Then test on
  real phones during the pilot (see PLATFORM_SETUP.md).

## Known limits
- The phone's face unlock proves the phone's owner is holding it, not a match against an institute
  photo. A scholar could add someone else's face to their own phone's unlock.
- A scholar anywhere on campus can mark (as decided). Rooted phones are not blocked in this version;
  add a root/jailbreak check (e.g. the `freerasp` package) if needed.
- Leave is in whole days; one skipped session in a day needs no leave under the two-session rule.
- The private key is kept in the phone's secure storage (Keystore-encrypted / Keychain), not in a
  hardware-only key. Uninstalling the app means registering the phone again, with admin approval.
