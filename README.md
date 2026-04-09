# check_websites.sh

A Bash script that checks the availability and SSL certificate status of multiple websites in parallel, with color-coded terminal output and persistent logging.

## Features

- Checks HTTP status and response time for each website
- Verifies SSL certificate expiry (in days)
- Runs all checks in parallel for fast results
- Color-coded terminal output (green = UP, red = DOWN, yellow = warning)
- Appends results to a log file (`website_check.log`) in the same directory as the script
- Prints a summary of UP/DOWN counts and any SSL issues

## Requirements

- **Linux** (uses GNU `date -d` for date parsing — not compatible with macOS out of the box)
- `bash` 4+
- `curl`
- `openssl`

## Usage

```bash
chmod +x check_websites.sh
./check_websites.sh
```

## Configuration

Edit the `WEBSITES` array near the top of the script to list the domains you want to monitor:

```bash
WEBSITES=(
  "google.com"
  "yahoo.com"
  "example.com"
)
```

Entries should be **hostnames only** (no `https://` prefix). The script prepends `https://` automatically.

## Output

### Terminal

```
=========================================
Website Availability Checker
Started at: 2024-01-15 10:30:00
=========================================

[✓] google.com — UP (HTTP: 200, 0.25s) | SSL: 87 days
[✓] yahoo.com  — UP (HTTP: 200, 0.41s) | SSL: WARNING 28 days
[✗] example.com — DOWN (HTTP: 000, timeout)

=========================================
Summary:
Total sites checked: 3
UP:   2
DOWN: 1
SSL issues (expired or expiring ≤30 days): 1
Log saved to: /path/to/website_check.log
=========================================
```

### SSL Status indicators

| Status | Meaning |
|---|---|
| `SSL: N days` | Certificate valid for N days |
| `SSL: WARNING N days` | Certificate expires within 30 days |
| `SSL: EXPIRED` | Certificate has expired |
| `SSL: CHECK FAILED` | Could not retrieve certificate info |

### Log file

Each run appends one line per site to `website_check.log`:

```
[2024-01-15 10:30:01] google.com - UP (HTTP: 200, 0.25s, SSL: 87 days)
[2024-01-15 10:30:01] example.com - DOWN (HTTP: 000, timeout)
```

## How It Works

1. All website checks are launched as background jobs simultaneously.
2. Each check writes its result to a temp file under `/tmp/website_check_<PID>/`.
3. After all jobs complete (`wait`), results are read in the original site order.
4. Log entries are appended sequentially (no concurrent writes).
5. The temp directory is cleaned up automatically on exit via `trap`.

## License

MIT
