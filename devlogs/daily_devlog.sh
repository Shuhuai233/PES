#!/usr/bin/env bash
# daily_devlog.sh — Generate and push a daily devlog for the PES project
# Intended to run via cron at 06:00 every day.
# If no commits in the last 24 hours, exits silently.

set -euo pipefail

PROJECT_DIR="/home/shli2/PES"
DEVLOG_DIR="$PROJECT_DIR/devlogs"
DATE=$(date +%Y-%m-%d)
DEVLOG_FILE="$DEVLOG_DIR/$DATE.md"
LOG_FILE="$DEVLOG_DIR/.cron.log"

# Ensure devlogs directory exists
mkdir -p "$DEVLOG_DIR"

# Redirect all output to log file for debugging
exec >> "$LOG_FILE" 2>&1
echo "=== devlog cron run: $(date) ==="

cd "$PROJECT_DIR"

# Check if there are any commits in the last 24 hours
COMMIT_COUNT=$(git log --since="24 hours ago" --oneline 2>/dev/null | wc -l)
if [ "$COMMIT_COUNT" -eq 0 ]; then
    echo "No commits in the last 24 hours. Skipping devlog."
    exit 0
fi

# Skip if devlog for today already exists
if [ -f "$DEVLOG_FILE" ]; then
    echo "Devlog for $DATE already exists. Skipping."
    exit 0
fi

echo "Found $COMMIT_COUNT commits. Generating devlog..."

# Build the prompt with git data embedded
COMMIT_LOG=$(git log --since="24 hours ago" --stat --format="--- commit %H%nAuthor: %an%nDate: %ad%nSubject: %s%n%b" --date=iso)
DIFF_STAT=$(git diff --stat "$(git log --since='24 hours ago' --reverse --format='%H' | head -1)^"..HEAD 2>/dev/null || echo "stat unavailable")

PROMPT=$(cat <<ENDPROMPT
You are writing a devlog entry for the PES project (a 3D FPS extraction shooter in Godot 4.6).
Today's date: $DATE

Here are all the git commits from the last 24 hours (chronological):

$COMMIT_LOG

Overall diff stats:
$DIFF_STAT

Write a devlog markdown file. Format:
1. Start with "# Devlog — $DATE"
2. A 2-3 sentence summary paragraph
3. A bold line with total commits / lines added / lines removed
4. Group the work into logical phases (chronological), each with a ## heading
5. Under each phase, use bullet points explaining what was done and why
6. End with "## Architecture Decisions" (table if applicable) and "## Next Steps"

Keep it technical but readable. Focus on the WHY behind decisions, not just listing commits.
Write ONLY the markdown content, nothing else. No code fences around it.
ENDPROMPT
)

# Use opencode to generate the devlog
opencode run "$PROMPT" --print-logs 2>/dev/null | sed '/^$/N;/^\n$/d' > "$DEVLOG_FILE.tmp"

# Verify the file is not empty and looks like valid markdown
if [ -s "$DEVLOG_FILE.tmp" ] && head -1 "$DEVLOG_FILE.tmp" | grep -q "^# Devlog"; then
    mv "$DEVLOG_FILE.tmp" "$DEVLOG_FILE"
    echo "Devlog written to $DEVLOG_FILE"
else
    # If opencode output doesn't look right, fall back to a simple structured log
    echo "opencode output didn't look right, generating fallback devlog..."
    {
        echo "# Devlog — $DATE"
        echo ""
        echo "## Commits ($COMMIT_COUNT)"
        echo ""
        git log --since="24 hours ago" --format="- **%s** (%ad)" --date=short
        echo ""
        echo "## Files Changed"
        echo ""
        echo '```'
        echo "$DIFF_STAT"
        echo '```'
    } > "$DEVLOG_FILE"
    rm -f "$DEVLOG_FILE.tmp"
    echo "Fallback devlog written to $DEVLOG_FILE"
fi

# Commit and push
cd "$PROJECT_DIR"
git add "$DEVLOG_FILE"
git commit -m "devlog: $DATE"
git push origin master

echo "Devlog committed and pushed."
echo "=== done ==="
