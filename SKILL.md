---
name: github-actions-apk-build
description: Autonomous 10/10 cloud APK builder using GitHub Actions with automatic Telegram delivery, zero 50 MB size limit (auto-splitting & direct GitHub Release fallback for large APKs), auto-healing, JDK detection, and live log diagnostics. Trigger whenever the user types `/github actions`, `/github actions build apk`, `github actions apk build`, `build apk`, `/git github actions apk build`, or asks to push/locate an Android project and compile an APK in the cloud.
---
# GitHub Actions APK Build (Cloud + Unlimited Telegram Delivery)

Autonomous 7-step workflow to offload heavy Android Gradle builds from a local Ubuntu/PRoot mobile environment onto GitHub Actions cloud runners and deliver the compiled `.apk` directly to Telegram—with **no 50 MB size bottleneck**.

## Supported Scenarios

1. **Unhosted Local Project:** Initializes Git, creates a clean `.gitignore`, creates a private GitHub repository, pushes the codebase, injects the CI workflow, and builds the APK.
2. **Hosted Local Project (Existing Remote):** Aligns with `origin`, injects or updates `.github/workflows/build-apk.yml`, pushes changes, and triggers the build.
3. **Remote Repository Target (by Keyword or URL):** Searches the user's GitHub repositories via `gh repo list` or accepts a direct URL, clones the target repo into an isolated `/tmp` workspace, injects the CI workflow, pushes, and triggers the cloud APK build.

---

## Step 1: Pre-Flight Environment & Auth Check

Verify `git`, `gh` CLI, and active authentication in the Ubuntu environment:

```bash
git --version && gh auth status
```

- Ensure Git identity (`user.name` and `user.email`) is configured so commits never fail.
- If `gh auth status` fails, stop and instruct the user to run `gh auth login`.

---

## Step 2: Detect Scenario & Resolve Target Repository

Inspect the user's prompt and current working directory (`pwd`) to route into the exact execution path:

### Scenario A: Remote Repository Specified (URL or Keyword)
Triggered when the user supplies a GitHub URL (`https://github.com/<owner>/<repo>`) or specifies a repository name/keyword.

1. **Search by keyword** if a full URL is not given:
   ```bash
   gh repo list --limit 50 --json name,url,defaultBranchRef,updatedAt
   ```
   Match the closest repository name (case-insensitive). If multiple close matches exist, select the most recently updated match or confirm with the user.
2. **Clone into a clean temporary workspace** so the user's active folder stays clean:
   ```bash
   WORK_DIR="/tmp/gh-apk-build-$(basename <repo-url> .git)"
   rm -rf "$WORK_DIR" && git clone <repo-url> "$WORK_DIR" && cd "$WORK_DIR"
   ```

### Scenario B: Local Project with Existing GitHub Remote
Triggered when the current directory contains Android project markers (`settings.gradle`, `settings.gradle.kts`, `build.gradle`, `build.gradle.kts`, or `gradlew`) AND `git remote get-url origin` succeeds.

1. Sync with the remote branch without losing local uncommitted work:
   ```bash
   CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
   git pull --rebase origin "$CURRENT_BRANCH" || true
   ```

### Scenario C: Unhosted Local Project (No Git or No Remote)
Triggered when the current directory is an Android project without a Git repository or without an `origin` remote.

1. Derive `<repo-name>` from the current folder name (sanitized to lowercase-hyphenated).
2. Initialize Git if `.git` does not exist:
   ```bash
   git init -b main
   ```
3. Create or verify `.gitignore` so heavy build artifacts and device-specific paths are excluded while keeping `gradle/wrapper/gradle-wrapper.jar` intact:
   ```gitignore
   *.iml
   .gradle/
   /local.properties
   /.idea/
   .DS_Store
   /build/
   **/build/
   /captures/
   .externalNativeBuild/
   .cxx/
   ```
4. Create the private GitHub repository and link `origin`:
   ```bash
   gh repo create "<repo-name>" --private --source=. --remote=origin
   ```

---

## Step 3: Project Inspection & Auto-Healing

Before generating the workflow, inspect and patch common mobile-to-CI issues:

1. **Strip `local.properties`:** Ensure device-specific SDK paths (e.g., `/data/data/com.termux/...`) are never tracked:
   ```bash
   git rm --cached local.properties 2>/dev/null || true
   ```
2. **Gradle Wrapper Permissions:** Android storage / PRoot Ubuntu environments often strip execute bits. Enforce `+x` in the Git index:
   ```bash
   if [ -f "./gradlew" ]; then
     chmod +x ./gradlew
     git update-index --chmod=+x gradlew
   fi
   ```
3. **JDK Version Detection:** Inspect `gradle/wrapper/gradle-wrapper.properties` and `build.gradle*`:
   - Use **JDK 21** if Gradle 8.5+, Android Gradle Plugin (AGP) 8.5+, or `compileSdk 35` is detected.
   - Otherwise, default to **JDK 17** (`temurin`).

---

## Step 4: Configure Telegram Secrets

Ensure the target GitHub repository has the required Telegram secrets configured so the workflow can send the compiled APK automatically.

The user's persistent default Telegram credentials are:
- `TELEGRAM_TOKEN`: `9023342382:AAHE3oJxfcpHiJNMM18uCbB35WcMQR8u3f8`
- `TELEGRAM_CHAT_ID`: `6593924184`

Check if secrets exist via `gh secret list`. If missing or incomplete on the target repository, automatically inject the persistent default credentials:

```bash
echo -n "9023342382:AAHE3oJxfcpHiJNMM18uCbB35WcMQR8u3f8" | gh secret set TELEGRAM_TOKEN
echo -n "6593924184" | gh secret set TELEGRAM_CHAT_ID
```

---

## Step 5: Generate `.github/workflows/build-apk.yml` (No 50 MB Limit)

Create `.github/workflows/build-apk.yml`:

```bash
mkdir -p .github/workflows
```

To bypass Telegram's standard 50 MB Bot API file cap automatically, the workflow:
- Sends the `.apk` directly when under 48 MB.
- For APKs **larger than 48 MB** (up to 2 GB+), automatically publishes a **GitHub Release** with a direct one-tap download URL AND splits the APK into 45 MB `.zip` parts sent straight to your Telegram chat so you can either tap the direct link or extract the parts on your phone.

Write the following production workflow (replacing `'17'` with `'21'` if JDK 21 was detected in Step 3):

```yaml
name: Build Android APK & Send to Telegram

on:
  push:
    branches: [ main, master ]
  workflow_dispatch:
    inputs:
      build_type:
        description: 'Build variant (debug or release)'
        required: false
        default: 'debug'
        type: choice
        options:
          - debug
          - release

permissions:
  contents: write

jobs:
  build-apk:
    name: Compile Android APK
    runs-on: ubuntu-latest
    timeout-minutes: 30

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up JDK
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Setup Gradle & Cache
        uses: gradle/actions/setup-gradle@v4

      - name: Grant execute permission for gradlew
        run: |
          if [ -f "./gradlew" ]; then
            chmod +x ./gradlew
          fi

      - name: Build APK
        run: |
          TASK="assembleDebug"
          if [ "${{ github.event.inputs.build_type }}" = "release" ]; then
            TASK="assembleRelease"
          fi
          if [ -f "./gradlew" ]; then
            ./gradlew $TASK --no-daemon --stacktrace
          else
            gradle $TASK --no-daemon --stacktrace
          fi

      - name: Collect Output APK
        run: |
          mkdir -p final-apk
          find . -path "*/build/outputs/apk/*/*.apk" -exec cp {} final-apk/ \;
          ls -lh final-apk/

      - name: Upload APK Artifact (Up to 2 GB)
        uses: actions/upload-artifact@v4
        with:
          name: android-apk
          path: final-apk/*.apk
          retention-days: 14
          if-no-files-found: error

      - name: Create GitHub Release for Direct High-Speed Download
        id: release
        if: success()
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          TAG="apk-build-${{ github.run_number }}-${{ github.run_id }}"
          gh release create "$TAG" final-apk/*.apk             --title "APK Build #${{ github.run_number }}"             --notes "Automated Android APK build from commit ${{ github.sha }}"
          echo "release_url=https://github.com/${{ github.repository }}/releases/tag/${TAG}" >> $GITHUB_OUTPUT

      - name: Deliver APK to Telegram (Auto-Bypass 50 MB Limit)
        if: success() && env.TELEGRAM_TOKEN != '' && env.TELEGRAM_CHAT_ID != ''
        env:
          TELEGRAM_TOKEN: ${{ secrets.TELEGRAM_TOKEN }}
          TELEGRAM_CHAT_ID: ${{ secrets.TELEGRAM_CHAT_ID }}
        run: |
          REPO_NAME="${{ github.repository }}"
          RELEASE_URL="${{ steps.release.outputs.release_url }}"
          MAX_BYTES=50331648 # 48 MB safe threshold for standard Bot API

          for APK_FILE in final-apk/*.apk; do
            if [ -f "$APK_FILE" ]; then
              FILE_SIZE=$(stat -c%s "$APK_FILE")
              FILE_NAME=$(basename "$APK_FILE")
              SIZE_MB=$(awk "BEGIN {printf "%.2f", $FILE_SIZE/1048576}")

              if [ "$FILE_SIZE" -le "$MAX_BYTES" ]; then
                curl -s -F chat_id="$TELEGRAM_CHAT_ID"                      -F document=@"$APK_FILE"                      -F caption="APK Build Complete: $REPO_NAME ($FILE_NAME - ${SIZE_MB} MB)"                      "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument"
              else
                curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage"                      -d chat_id="$TELEGRAM_CHAT_ID"                      -d text="Large APK Built ($FILE_NAME - ${SIZE_MB} MB). Direct Download: $RELEASE_URL (Sending 45 MB split parts below...)"

                mkdir -p split-parts
                zip -s 45m "split-parts/${FILE_NAME}.zip" "$APK_FILE"
                for PART in split-parts/*; do
                  curl -s -F chat_id="$TELEGRAM_CHAT_ID"                        -F document=@"$PART"                        -F caption="Part: $(basename "$PART")"                        "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument"
                done
                rm -rf split-parts
              fi
            fi
          done

      - name: Notify Telegram on Failure
        if: failure() && env.TELEGRAM_TOKEN != '' && env.TELEGRAM_CHAT_ID != ''
        env:
          TELEGRAM_TOKEN: ${{ secrets.TELEGRAM_TOKEN }}
          TELEGRAM_CHAT_ID: ${{ secrets.TELEGRAM_CHAT_ID }}
        run: |
          curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage"                -d chat_id="$TELEGRAM_CHAT_ID"                -d text="APK Build Failed for ${{ github.repository }}. Check Actions logs: https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }}"
```

---

## Step 6: Commit, Push & Trigger Cloud Build

Stage, commit, and push to trigger the workflow:

```bash
git add -A
if ! git diff --cached --quiet; then
  git commit -m "ci: add automated GitHub Actions APK build and unlimited Telegram delivery"
  git push -u origin HEAD
else
  gh workflow run build-apk.yml
fi
```

---

## Step 7: Monitor Build & Auto-Diagnose Failures

1. Fetch the active run ID and watch progress:
   ```bash
   sleep 5
   RUN_ID=$(gh run list --workflow=build-apk.yml --limit 1 --json databaseId --jq '.[0].databaseId')
   gh run watch "$RUN_ID" --exit-status
   ```
2. **If the build fails:** Pull failed logs (`gh run view "$RUN_ID" --log-failed | tail -n 60`), diagnose the issue (e.g., JDK mismatch, missing SDK version, or Gradle error), fix locally, and re-push.
3. **If the build succeeds:** Confirm to the user that the `.apk` (or direct Release link + split archives for APKs > 48 MB) has been delivered to their Telegram chat and share the GitHub Actions run URL (`https://github.com/<owner>/<repo>/actions/runs/$RUN_ID`).

## Gotchas

- **Zero 50 MB Size Limit:** Standard Telegram bots reject single uploads over 50 MB. This workflow solves it automatically: APKs <= 48 MB arrive as a single `.apk` in Telegram, while APKs > 48 MB (up to 2 GB) automatically generate a direct one-tap GitHub Release link AND send 45 MB split `.zip` parts to Telegram.
- **Never commit secrets in YAML:** Always reference `${{ secrets.TELEGRAM_TOKEN }}` and `${{ secrets.TELEGRAM_CHAT_ID }}` so repositories never expose your bot token.
- **PRoot / Android Storage Execute Bits:** Always run `git update-index --chmod=+x gradlew` before committing so Ubuntu runners do not fail with `Permission denied`.
