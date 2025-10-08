# AlmaLinux Mirror Propagation Report - AI Agent Instructions

## Project Overview
This is a static site generator that creates an AlmaLinux mirror status dashboard. The core workflow is a Bash script (`run.sh`) that probes mirror servers, generates an HTML report, and deploys to Cloudflare Pages via GitHub Actions.

## Architecture & Data Flow
1. **Mirror Discovery**: Fetches mirror list from `https://mirrors.almalinux.org/debug/json/all_mirrors`
2. **Time Synchronization**: Checks primary mirrors (Atlanta/Seattle) for reference timestamp via `/TIME` endpoints
3. **Mirror Probing**: Tests each public mirror's `/TIME` endpoint to calculate drift from primary
4. **Report Generation**: Template substitution in `index.html` using sed replacements
5. **Notification System**: Email alerts via Brevo API for mirrors >3 hours behind (configurable in `notification-list.json`)
6. **Deployment**: Automated hourly via GitHub Actions to Cloudflare Pages

## Key Files & Patterns

### `run.sh` - Core Logic
- **Template Placeholders**: Uses `${PLACEHOLDER}_RESPONSE` pattern for HTML substitution
- **Mirror Categorization**: `in_sync`, `behind`, `unavailable` arrays with custom record functions
- **Time Calculations**: `time_ago_in_words()` converts seconds to human-readable format
- **Sorting Logic**: Behind mirrors sorted by drift time (shortest first)
- **Error Handling**: 5-second timeout, follows max 2 redirects, validates numeric TIME responses

### `index.html` - Static Template
- **Tabler CSS Framework**: Uses specific classes like `table-selectable`, `nav-link disabled`
- **Tab System**: Three states (in-sync, behind, unavailable) with conditional tab disabling
- **Template Variables**: `SOURCE_TIME`, `REPORT_TIME`, `*_RESPONSE` placeholders

### `notification-list.json` - Configuration
- Simple array format: `{"mirror_name": "domain", "email": "contact"}`
- Used by `notify()` function to send Brevo API emails for degraded mirrors

## Development Workflow

### Local Testing
```bash
# Test full pipeline (requires BREVO_API_KEY for notifications)
./run.sh

# Check generated output
ls -la site/
```

### Deployment Process
- **Trigger**: Hourly cron (`0 * * * *`) or manual dispatch
- **Build**: Single job runs `bash run.sh` on ubuntu-latest
- **Deploy**: Cloudflare Pages action publishes `site/` directory
- **Dependencies**: curl, jq, sed (available in GitHub Actions runner)

## Project Conventions
- **Code Style**: EditorConfig enforces 2-space indentation, bash shell variant with specific shfmt rules
- **File Structure**: Build artifacts go to `site/` (gitignored), source stays in root
- **Error Thresholds**: 3 hours for notifications (line 147), 5 seconds curl timeout
- **Mirror Filtering**: Only tests `status: "ok"` and `private: false` mirrors

## Critical Integration Points
- **AlmaLinux API**: Depends on `/debug/json/all_mirrors` endpoint structure
- **Mirror TIME Files**: Expects Unix timestamp at `{mirror_url}/TIME`
- **Brevo API**: Email service requires `BREVO_API_KEY` secret in GitHub Actions
- **Cloudflare Pages**: Deployment requires `CLOUDFLARE_API_TOKEN` and specific account/project IDs

## Debugging Common Issues
- **Mirror Probe Failures**: Check curl exit codes and timeout values in while loop
- **Template Rendering**: Verify sed replacement patterns match placeholder format exactly
- **Notification Problems**: Ensure JSON structure matches Brevo API schema in `notify()` function
- **Deployment Issues**: Check Cloudflare Pages action logs and verify `site/` directory generation
