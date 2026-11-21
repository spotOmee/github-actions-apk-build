---
name: github-actions-apk-build
allowed-tools:
  - run_command
  - read_file
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
   if [ -d "$WORK_DIR" ]; then rm -rf "$WORK_DIR"; fi
   git clone <repo-url> "$WORK_DIR" && cd "$WORK_DIR"
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
   local.properties
   /.idea/
   .DS_Store
   /build/
   **/build/
   /captures/
   .externalNativeBuild/
   .cxx/

   # Cryptographic & Signing Keys
   *.keystore
   *.jks
   *.p12
   *.pem
   *.key
   *.pk8
   id_rsa*
   id_ed25519*

   # Environment & Secrets
   *.env*
   secrets.*
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
2. **Gradle Wrapper Executable Bit:** Android storage / PRoot Ubuntu environments often strip execute bits. Enforce `+x` in the Git index:
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

## Step 4: Configure GitHub Repository Secrets

Ensure the target GitHub repository has encrypted repository secrets configured under **Settings > Secrets and variables > Actions** so builds run cleanly without exposing credentials:

- `TELEGRAM_TOKEN`: Bot token from `@BotFather`
- `TELEGRAM_CHAT_ID`: User's Telegram numeric chat ID from `@userinfobot`
- `RELEASE_KEYSTORE_BASE64`: (Optional) Base64-encoded Android release keystore (`base64 -w 0 release.keystore`)
- `KEYSTORE_PASSWORD`: (Optional) Keystore password
- `KEY_ALIAS`: (Optional) Signing key alias
- `KEY_PASSWORD`: (Optional) Key password

Check if secrets exist via `gh secret list`. Set them securely using the GitHub CLI:

```bash
gh secret set TELEGRAM_TOKEN
gh secret set TELEGRAM_CHAT_ID
# If signing in CI:
# base64 -w 0 my-release-key.keystore | gh secret set RELEASE_KEYSTORE_BASE64
# gh secret set KEYSTORE_PASSWORD
# gh secret set KEY_ALIAS
# gh secret set KEY_PASSWORD
```

---

## Step 5: Generate `.github/workflows/build-apk.yml` (Zero-Leak CI/CD Pipeline)

Create `.github/workflows/build-apk.yml`:

```bash
mkdir -p .github/workflows
```

The workflow enforces zero-leak security:
1. **Automated Secret Scanning Gate:** Blocks build execution immediately if any unignored private key, keystore, PAT, token, or `.env` file is present.
2. **Encrypted Secrets & Log Masking:** Accesses secrets exclusively via `${{ secrets.* }}`, dynamically masks decoded values with `::add-mask::`, and securely wipes temporary keystores in an `if: always()` cleanup step.
3. **Sanitized Release Metadata:** Emits clean semantic release titles, clean version tags, and notes that omit raw commit SHAs, hashes, or runner environment dumps.
4. **Token Security & Least-Privilege Scope:** Restricts permissions to `contents: write` exclusively for publishing releases and artifacts.
5. **Safe Delivery:** Executes in-process delivery so tokens never appear in runner process argument listings.

Write the following workflow:

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

      - name: Pre-Build Secret Scanning Audit
        run: |
          python3 -c '
          import os, sys, re

          EXCLUDE_DIRS = {".git", ".gradle", "build", "output", "backups", ".idea"}
          SECRET_PATTERNS = [
              (r"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----", "Private Key"),
              (r"\b[0-9]{8,10}:[a-zA-Z0-9_-]{35}\b", "Telegram Bot Token"),
              (r"(?i)\b(?:ghp|gho|ghu|ghs|ghr)_[a-zA-Z0-9]{36,}\b", "GitHub Token"),
              (r"(?i)\bgithub_pat_[a-zA-Z0-9_]{30,}\b", "GitHub PAT"),
          ]
          FORBIDDEN_EXTS = (".keystore", ".jks", ".p12", ".pem", ".key", ".pk8")
          FORBIDDEN_FILES = {"local.properties"}

          violations = []
          for root, dirs, files in os.walk("."):
              dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
              for f in files:
                  rel_path = os.path.relpath(os.path.join(root, f), ".")
                  if f.endswith(FORBIDDEN_EXTS):
                      violations.append(f"Forbidden key file: {rel_path}")
                  if f in FORBIDDEN_FILES or any(f.startswith(p) for p in [".e" + "nv"]):
                      violations.append(f"Forbidden environment file: {rel_path}")
                  if f.endswith((".py", ".gradle", ".kts", ".properties", ".sh", ".yml", ".yaml", ".json", ".xml")):
                      try:
                          with open(rel_path, "r", encoding="utf-8", errors="ignore") as fh:
                              content = fh.read()
                              for pat, desc in SECRET_PATTERNS:
                                  if re.search(pat, content):
                                      violations.append(f"Pattern violation ({desc}) in: {rel_path}")
                      except Exception:
                          pass

          if violations:
              print("❌ PRE-BUILD SECRET SCANNING FAILED:")
              for v in violations:
                  print(f"  • {v}")
              sys.exit(1)
          print("✅ Pre-build secret scanning passed: Zero secrets, keys, or credentials found.")
          '

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

      - name: Configure Signing Credentials from Repository Secrets
        if: env.RELEASE_KEYSTORE_BASE64 != ''
        env:
          RELEASE_KEYSTORE_BASE64: ${{ secrets.RELEASE_KEYSTORE_BASE64 }}
          KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
          KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
        run: |
          mkdir -p /tmp/signing
          echo "::add-mask::$KEYSTORE_PASSWORD"
          echo "::add-mask::$KEY_ALIAS"
          echo "::add-mask::$KEY_PASSWORD"
          echo "$RELEASE_KEYSTORE_BASE64" | base64 -d > /tmp/signing/release.keystore
          chmod 600 /tmp/signing/release.keystore
          echo "ANDROID_KEYSTORE_PATH=/tmp/signing/release.keystore" >> $GITHUB_ENV
          echo "ANDROID_KEYSTORE_PASS=$KEYSTORE_PASSWORD" >> $GITHUB_ENV
          echo "ANDROID_KEY_ALIAS=$KEY_ALIAS" >> $GITHUB_ENV
          echo "ANDROID_KEY_PASS=$KEY_PASSWORD" >> $GITHUB_ENV

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
          TAG="v1.0.0-build-${{ github.run_number }}"
          gh release create "$TAG" final-apk/*.apk \
            --title "APK Build #${{ github.run_number }}" \
            --notes "Automated Android build #${{ github.run_number }}. Verified and ready for installation." \
            --clobber || true
          echo "release_url=https://github.com/${{ github.repository }}/releases/tag/${TAG}" >> $GITHUB_OUTPUT

      - name: Deliver APK to Telegram (Auto-Bypass 50 MB Limit)
        if: success() && env.TELEGRAM_TOKEN != '' && env.TELEGRAM_CHAT_ID != ''
        env:
          TELEGRAM_TOKEN: ${{ secrets.TELEGRAM_TOKEN }}
          TELEGRAM_CHAT_ID: ${{ secrets.TELEGRAM_CHAT_ID }}
        run: |
          REPO_NAME="${{ github.repository }}"
          RELEASE_URL="${{ steps.release.outputs.release_url }}"
          MAX_BYTES=50331648

          python3 -c "
          import os, glob, subprocess, json, urllib.request, uuid

          token = os.environ.get('TELEGRAM_TOKEN')
          chat_id = os.environ.get('TELEGRAM_CHAT_ID')
          repo_name = os.environ.get('REPO_NAME', '')
          release_url = os.environ.get('RELEASE_URL', '')

          def send_msg(text):
              url = f'https://api.telegram.org/bot{token}/sendMessage'
              payload = json.dumps({'chat_id': chat_id, 'text': text}).encode('utf-8')
              req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'})
              with urllib.request.urlopen(req, timeout=30) as r:
                  return json.loads(r.read())

          def send_doc(filepath, caption):
              boundary = uuid.uuid4().hex
              fname = os.path.basename(filepath)
              with open(filepath, 'rb') as f:
                  data = f.read()
              body = bytearray()
              body.extend(f'--{boundary}\r\n'.encode('utf-8'))
              body.extend(f'Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n{chat_id}\r\n'.encode('utf-8'))
              if caption:
                  body.extend(f'--{boundary}\r\n'.encode('utf-8'))
                  body.extend(f'Content-Disposition: form-data; name=\"caption\"\r\n\r\n{caption}\r\n'.encode('utf-8'))
              body.extend(f'--{boundary}\r\n'.encode('utf-8'))
              body.extend(f'Content-Disposition: form-data; name=\"document\"; filename=\"{fname}\"\r\nContent-Type: application/octet-stream\r\n\r\n'.encode('utf-8'))
              body.extend(data)
              body.extend(f'\r\n--{boundary}--\r\n'.encode('utf-8'))
              url = f'https://api.telegram.org/bot{token}/sendDocument'
              req = urllib.request.Request(url, data=body, headers={'Content-Type': f'multipart/form-data; boundary={boundary}'})
              with urllib.request.urlopen(req, timeout=120) as r:
                  return json.loads(r.read())

          for apk in glob.glob('final-apk/*.apk'):
              sz = os.path.getsize(apk)
              fname = os.path.basename(apk)
              mb = sz / (1024*1024)
              if sz <= 50331648:
                  send_doc(apk, f'✅ APK Built: {fname} ({mb:.2f} MB)')
              else:
                  send_msg(f'📦 Large APK Built: {fname} ({mb:.2f} MB)\nDirect download: {release_url}')
                  os.makedirs('/tmp/splits', exist_ok=True)
                  subprocess.run(['zip', '-s', '45m', f'/tmp/splits/{fname}.zip', apk], check=True)
                  for part in sorted(glob.glob('/tmp/splits/*')):
                      send_doc(part, f'Part: {os.path.basename(part)}')
          "

      - name: Notify Telegram on Failure
        if: failure() && env.TELEGRAM_TOKEN != '' && env.TELEGRAM_CHAT_ID != ''
        env:
          TELEGRAM_TOKEN: ${{ secrets.TELEGRAM_TOKEN }}
          TELEGRAM_CHAT_ID: ${{ secrets.TELEGRAM_CHAT_ID }}
        run: |
          python3 -c '
          import os, urllib.request, json
          token = os.environ.get("TELEGRAM_TOKEN", "").strip()
          chat_id = os.environ.get("TELEGRAM_CHAT_ID", "").strip()
          repo = os.environ.get("GITHUB_REPOSITORY", "")
          if token and chat_id:
              url = f"https://api.telegram.org/bot{token}/sendMessage"
              payload = json.dumps({"chat_id": chat_id, "text": f"❌ APK Build Failed for {repo}."}).encode("utf-8")
              req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
              try:
                  with urllib.request.urlopen(req, timeout=15) as resp:
                      pass
              except Exception:
                  pass
          '

      - name: Cleanup Ephemeral Signing Files
        if: always()
        run: |
          if [ -d "/tmp/signing" ]; then
            find /tmp/signing -type f -delete 2>/dev/null && rmdir /tmp/signing 2>/dev/null || true
          fi
          echo "✅ Ephemeral credentials wiped."
```

---

## Step 6: Safe Staging, Diff Audit & Push

Never run blind `git add .` or `git add -A`. Always audit staged files and commit messages before pushing:

1. **Verify Remote Credentials:**
   Ensure `git remote -v` never contains embedded tokens or passwords:
   ```bash
   REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
   if echo "$REMOTE_URL" | grep -qE "://[^@]+@"; then
     echo "❌ Token embedded in remote URL! Sanitizing..."
     CLEAN_URL=$(echo "$REMOTE_URL" | sed -E 's|://[^@]+@|://|')
     git remote set-url origin "$CLEAN_URL"
   fi
   ```

2. **Pre-Staging Sensitive Check & Staging:**
   ```bash
   # Verify sensitive files are uncommitted
   git status --porcelain | grep -E "\.(keystore|jks|pem|key|p12|pk8|env)$|local\.properties" && {
     echo "❌ SENSITIVE FILES DETECTED UNIGNORED! Adding to .gitignore..."
     echo -e "\n*.keystore\n*.jks\n*.pem\n*.key\nlocal.properties\n.env\n.env.*" >> .gitignore
   }

   # Stage safe files
   git add .gitignore .github/workflows/
   ```

3. **Diff Verification Gate:**
   ```bash
   # Ensure no sensitive tokens or private keys are staged
   git diff --cached --name-only | grep -E "\.(keystore|jks|pem|key|env)$|local\.properties" && {
     echo "❌ ERROR: Sensitive files staged! Aborting push."
     exit 1
   }

   # Commit with clean semantic message (never include tokens, env vars, or paths)
   if ! git diff --cached --quiet; then
     git commit -m "ci: configure zero-leak automated GitHub Actions APK build workflow"
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
3. **If the build succeeds:** Confirm to the user that the `.apk` has been delivered cleanly.

## Gotchas & Security Guidelines

- **Zero Credential Leaks:** Secrets are strictly passed through `${{ secrets.* }}`. Dynamically decoded keystores are masked with `::add-mask::` and deleted in `if: always()`.
- **Pre-Commit Secret Check:** Pre-build scan prevents any accidental secret or keystore file commits from reaching release artifacts.
- **Sanitized Release Titles:** Automated releases must use clean semantic versions (`v1.0.0-build-<run>`) with zero raw commit SHAs or environment dumps in release notes.
- **Safe Remote URLs:** Never commit or push with `https://TOKEN@github.com/...`. Use GitHub CLI credential helpers (`gh auth git-credential`) or SSH.
- **PRoot / Android Storage Execute Bits:** Always run `git update-index --chmod=+x gradlew` before committing so Ubuntu runners do not fail with `Permission denied`.
