# XLX_Dark_Dashboard
Custom dashboard with improvements and dark theme for XLX reflectors

The dashboard here is a fork of the default one that is installed together with XLXD Reflector but with a series of changes that improve the user experience.
In addition to the standard information, the following improvements were made:

---

## Core Features

1. **Dark theme** — along with changes to the page layout, the dark theme makes it easier to read information on screen;
2. **User database integration** — adds operator name and city to the *Recent Activity* and *Connected Stations* tabs, fetched from a local SQLite database;
3. **Improved layout** — columns were reordered for better readability, and users connected to each module are now displayed below the main table to optimize screen utilization;
4. **Hidden tabs support** — the *Links* tab can now be hidden the same way as *Network* and *Traffic*; the adjustment is made in `config.inc.php`;
5. **Redesigned Network tab** — now displays more information in a readable format, including a 30-day date history and additional node details;
6. **Dual-network Traffic tab** — now shows both networks: legacy ircddb and the main QuadNet, which is currently the most widely used and registered as default in Pi-Star;
7. **Minor customizations** — various data points are entered during installation and can be updated later in the settings file.

---

## Recent Improvements

### Interface & Layout
- **Responsive layout** — page content and menu bar are now centrally aligned and properly bounded on wide screens and mobile devices;
- **jQuery upgraded** to version 3.7.1 via CDN;
- **Browser tab badge** — the page title now shows the number of connected stations in parentheses, e.g. `(18) XLX123 by PU5KOD`, updating automatically on every refresh;
- **Interface in English** — all labels, buttons and filter controls across all tabs are in English.

### Connected Stations Tab
- **Live connection duration counter** — the connection time for each node in the *Connected Stations* tab now updates every second in real time, without requiring a page reload.

### Recent Activity Tab — Live TX Detection
- **Active transmission detection via log** — instead of relying on the 10-second heartbeat, the system now reads `/var/log/xlx.log` in real time to detect when a transmission starts (`Opening stream`) and ends (`Closing stream`), providing accurate start timestamps;
- **TX row highlight** — the row of the station currently transmitting is highlighted with a pulsing amber background animation;
- **Live TX timer** — the *Last Activity* field for a transmitting station is replaced by a live counter in the format `TXing 02:34s`, counting up from the exact moment the transmission started;
- **Simultaneous multi-module TX support** — the system detects active transmissions across different modules simultaneously; each module's first station in the list receives its own independent counter;
- **TX displayed in browser tab** — while a transmission is active, the browser tab title changes to show the transmitting operator's callsign and elapsed time, e.g. `(18) PU5KOD TXing 02:34s...`; when multiple modules are transmitting simultaneously, the most recent one is shown in the tab;
- **TX timeout protection** — any transmission detected in the log that exceeds 5 minutes without a closing entry is automatically discarded, preventing phantom TX indicators caused by log corruption or missed closing events;
- **Interval leak prevention** — the JavaScript timer is properly destroyed before each AJAX page reload, ensuring no background timers accumulate over time.

### Page Refresh & Filters
- **Filter-aware auto-refresh** — the automatic page refresh is paused whenever a callsign or module filter is active, preserving the filtered view; the refresh resumes automatically after the filter is cleared;
- **Active modules excluded from auto-refresh** — the *Active Modules* tab is excluded from the page auto-refresh cycle to avoid interference with the chart's independent update timer.

### Module Activity Chart
- **Transmission history chart** — a stacked bar chart is displayed below the module table in the *Active Modules* tab, showing the number of transmissions per module over the last 24 hours, aggregated by hour;
- **Data sourced from log** — the chart parses `/var/log/xlx.log` directly on the server side, with no external dependencies;
- **Colorblind-safe palette** — module colors follow the Paul Tol / IBM accessibility standard to ensure readability for users with color vision deficiencies;
- **Independent 60-second refresh** — the chart updates itself every 60 seconds via AJAX, independently of the main page refresh cycle; a status line shows the last update time and countdown to the next update.

---

## File Structure

Complete list of all project files organized by directory. Files marked with ✏️ were modified from the original XLX dashboard; ✨ marks files added by this fork.

```
/var/www/
├── restricted/                         ← Protected credentials area
│   ├── .htpasswd                         Hashed user credentials
│   └── pendentes.txt                     Pending first-login password list
│
└── html/
    └── xlxd/                           ← Main dashboard root
        ├── index.php ✏️                   Main dashboard controller
        ├── change_password.php ✨         Forced first-login password change
        │
        ├── css/                        ← Defines page styles
        │   └── layout.css ✏️             Dark theme stylesheet
        │
        ├── img/                        ← Images and icons displayed on the site
        │
        ├── log/                        ← Log viewer (restricted access)
        │   ├── index.php ✨              XLX Log Viewer (real-time)
        │   ├── fetch_log.php ✨          Log streaming AJAX endpoint
        │   └── export_log.php ✨         Log download endpoint
        │
        └── pgs/                        ← Tab pages, classes and utilities
            ├── config.inc.php             Central configuration
            ├── functions.php              Shared utility library
            ├── country.csv                Country/prefix reference data
            ├── users.php ✏️               Recent Activity tab
            ├── repeaters.php ✏️           Connected Stations tab
            ├── modules.php ✏️             Active Modules tab + chart embed
            ├── chart.php ✨               Module activity chart (AJAX endpoint)
            ├── peers.php ✏️               Peers tab
            ├── reflectors.php             Reflectors tab (global XLX list)
            ├── traffic.php ✏️             Traffic tab (VNStat bandwidth)
            ├── liveccs.php                Live CCS tab (iframe embed)
            ├── liveircddb.php ✨          Live ircddb tab (iframe embed)
            ├── ircddb_proxy.php ✨        Transparent proxy for live.ircddb.net
            ├── class.reflector.php        xReflector — top-level data model
            ├── class.node.php             Node — connected station object
            ├── class.station.php          Station — recent activity entry
            ├── class.peer.php             Peer — peer reflector object
            ├── class.interlink.php        Interlink — direct interlink object
            └── class.parsexml.php         ParseXML — XML decoder utility
```

---

### `/var/www/html/xlxd/` — Main dashboard root

| File | Role |
|---|---|
| `index.php` ✏️ | Main dashboard controller — bootstraps the page, loads all tab includes, manages the AJAX auto-refresh cycle, handles session state, filter-aware refresh logic and browser tab title updates |
| `change_password.php` ✨ | First-login password change page — intercepts users listed in `pendentes.txt` after authentication and requires them to set a new password meeting strength requirements (min. 8 chars, upper/lowercase, digit, special char) before proceeding; updates `.htpasswd` and removes the user from `pendentes.txt` on success |

---

### `/var/www/html/xlxd/css/` — Stylesheet

| File | Role |
|---|---|
| `layout.css` ✏️ | Core stylesheet — dark theme colors, page layout, responsive breakpoints for desktop and mobile, TX row pulse animation and all UI component styles |

---

### `/var/www/html/xlxd/img/` — Static assets

| File | Role |
|---|---|
| *(images and icons)* | All images and icons displayed across the dashboard pages |

---

### `/var/www/html/xlxd/log/` — Log viewer

| File | Role |
|---|---|
| `index.php` ✨ | **XLX Log Viewer** — password-protected real-time viewer for `/var/log/xlx.log` with text filtering, colour-coded log levels (ERROR/WARNING), adjustable refresh interval, log clearing and CSRF protection |
| `fetch_log.php` ✨ | Log streaming AJAX endpoint — reads the last lines of `/var/log/xlx.log` server-side and returns them to the log viewer; session-gated to prevent unauthenticated access |
| `export_log.php` ✨ | Log export endpoint — serves the current log content as a downloadable text file; CSRF-token validated |

---

### `/var/www/html/xlxd/pgs/` — Tab pages, classes and utilities

**Configuration and shared utilities**

| File | Role |
|---|---|
| `config.inc.php` | Central configuration — reflector identity, sysop callsign, contact email, country, custom header text, footnote, dashboard version, page refresh settings, VNStat interface, visible/hidden tab flags and other runtime options |
| `functions.php` | Shared utility library — system uptime, time parsing, seconds formatting, VNStat data retrieval and traffic value formatting used across multiple tabs |
| `country.csv` | Country reference data — maps country names to ISO codes and amateur radio prefixes; used for flag display and country lookups across the dashboard |

**Tab pages**

| File | Role |
|---|---|
| `users.php` ✏️ | **Recent Activity** tab — displays last transmissions with operator name and city from the SQLite database; includes live TX detection from `/var/log/xlx.log`, pulsing row highlight, live TX timer, callsign/module filters and active TX indicator in the browser tab title |
| `repeaters.php` ✏️ | **Connected Stations** tab — lists all nodes currently linked to the reflector with operator name and city lookups; features live connection duration counters that update every second without page reload |
| `modules.php` ✏️ | **Active Modules** tab — shows the module status table with active connection counts and protocol addresses per module; embeds the 24-hour activity chart; excluded from the main auto-refresh cycle |
| `chart.php` ✨ | **Module Activity Chart** — server-side AJAX endpoint that parses `/var/log/xlx.log` and returns Chart.js stacked bar data for the last 24 hours of transmissions per module; uses a colorblind-safe palette and refreshes independently every 60 seconds |
| `peers.php` ✏️ | **Peers** tab — lists reflectors currently interlinked with this node, fetched in real time from the XLX server's reflector list endpoint |
| `reflectors.php` | **Reflectors** tab — displays the global list of registered XLX reflectors retrieved from the central calling-home server |
| `traffic.php` ✏️ | **Traffic** tab — shows server bandwidth usage (inbound, outbound and total) by day and month, parsed from VNStat; embeds the live ircddb network activity page via the local proxy |
| `liveccs.php` | **Live CCS** tab — embeds the live CCS activity page from `ccs001.xreflector.net` via iframe for real-time cross-mode connection monitoring |
| `liveircddb.php` ✨ | **Live ircddb** tab — embeds the live ircddb network activity page via iframe, served through the local proxy to avoid browser content restrictions |
| `ircddb_proxy.php` ✨ | Transparent HTTP proxy for `live.ircddb.net` — fetches and rewrites the ircddb live page server-side to avoid CSP and mixed-content browser restrictions when embedded via `liveircddb.php` |

**OOP data model**

| File | Role |
|---|---|
| `class.reflector.php` | `xReflector` class — top-level reflector object; holds collections of nodes, peers and interlinks and exposes query methods used by all tab pages |
| `class.node.php` | `Node` class — represents a single connected station with callsign, module, protocol, connection time and related metadata |
| `class.station.php` | `Station` class — represents a station entry in the recent activity list with transmission details |
| `class.peer.php` | `Peer` class — represents a peer reflector in the interlink or peers list with its identification and status fields |
| `class.interlink.php` | `Interlink` class — represents a direct interlink connection between reflectors, distinct from a regular peer |
| `class.parsexml.php` | `ParseXML` class — XML parser utility used to decode the data returned by the XLX server's calling-home and reflector list endpoints |

---

### `/var/www/restricted/` — Protected credentials area

| File | Role |
|---|---|
| `.htpasswd` | User credentials file — stores hashed passwords for all dashboard users; managed by `reflector_user_manager.sh` |
| `pendentes.txt` | Pending password list — one callsign per line; users present here are redirected to `change_password.php` and required to set a new password before accessing the dashboard |

---

## Dependencies

- **Chart.js 4.4.1** — loaded via CDN, used for the module activity chart
- **jQuery 3.7.1** — loaded via CDN, used for AJAX page refresh
- **SQLite3** — local database for operator name and city lookup
- **PHP** — server-side log parsing and data rendering

---

## 👥 User Manager

The dashboard access (`.htpasswd` authentication) is managed by `reflector_user_manager.sh`, a unified terminal tool included with the [XLX Installer](https://github.com/PU5KOD/XLX_Installer). It handles the full user lifecycle from a single interactive menu — no need to run separate scripts.

**Location:** `/xlxd/users_db/reflector_user_manager.sh`

```bash
sudo /xlxd/users_db/reflector_user_manager.sh
```

### Access Control features

| Option | Description |
|--------|-------------|
| **Add user** | Adds the callsign to the reflector whitelist and/or creates dashboard credentials, generating a secure 12-character initial password |
| **Reset password** | Generates a new password for an existing dashboard user and flags them as pending |
| **Remove user** | Independently removes the user from the dashboard and/or the whitelist |
| **Look up user** | Shows the current status across whitelist, dashboard access and pending list |
| **List pending** | Lists users who received an initial or reset password but have not yet changed it |
| **List whitelist** | Displays all active whitelist entries sorted alphabetically in auto-sized columns |

### RadioID database management

The tool also manages the `users_base.csv` database that feeds the dashboard's operator name and city lookup:

- Add, edit and delete records with pre-filled field editing
- Search across 300 000+ entries by callsign, DMRID, name, city or country with paginated results
- Trigger the PHP script that rebuilds the SQLite database from the CSV after bulk changes

> For full documentation see [REFLECTOR_USER_MANAGER.md](users_db/REFLECTOR_USER_MANAGER.md).
