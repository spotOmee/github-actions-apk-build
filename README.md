# 🚀 GitHub Actions APK Build (Cloud + Unlimited Telegram Delivery)

An autonomous AI agent skill that offloads heavy Android Gradle builds from local environments (especially resource-constrained Android, PRoot, Termux, or low-RAM machines) onto high-speed GitHub Actions cloud runners and delivers compiled `.apk` files directly to your Telegram chat—with **zero 50 MB file size bottleneck**.

---

## ⚡ What is this Skill?

When developing Android apps on mobile devices (Termux, PRoot, AndroidIDE) or low-spec machines, local Gradle compilation causes extreme battery drain, out-of-memory crashes, CPU throttling, and long build times.

`github-actions-apk-build` teaches your AI coding agent (Antigravity, Claude Code, Cursor, Codex, OpenCode, etc.) how to autonomously:
1. **Detect Android Project Setup:** Works with unhosted local directories, existing Git repositories, or remote GitHub repos (via keyword or URL).
2. **Auto-Heal Common Mobile-to-CI Issues:** Strips device-specific paths (`local.properties`), repairs missing Gradle execution bits (`git update-index --chmod=+x gradlew`), and automatically selects JDK 17 or JDK 21.
3. **Bypass Telegram's 50 MB Limit:** Standard Telegram bot API uploads fail above 50 MB. This workflow delivers APKs $\le$ 48 MB as a single `.apk` file, and for APKs $> 48\text{ MB}$ (up to 2 GB+), automatically publishes a **GitHub Release** with direct one-tap download and splits the APK into 45 MB `.zip` archives delivered straight to your chat.
4. **Live Monitoring & Auto-Diagnosis:** Tracks the GitHub Actions run in real-time, extracts failure logs if Gradle fails, and diagnoses the root cause.

---

## 🤖 Give This Prompt to Your Coding Agent to Install

Simply copy the prompt below and paste it directly into your AI coding agent (Antigravity, Claude Code, Codex, Cursor, etc.):

```markdown
Please install the `github-actions-apk-build` skill globally so you can build Android APKs in the cloud and deliver them to my Telegram:

1. Clone or pull the skill from GitHub:
   git clone --depth 1 https://github.com/spotOmee/github-actions-apk-build.git ~/.agents/skills/github-actions-apk-build || git -C ~/.agents/skills/github-actions-apk-build pull

2. Run its installer or symlink it:
   bash ~/.agents/skills/github-actions-apk-build/install.sh

3. Verify skill directory is registered:
   test -d ~/.agents/skills/github-actions-apk-build && echo "[✔] Skill registered"
```

---

## 💻 Manual CLI Install

To install manually:
```bash
git clone --depth 1 https://github.com/spotOmee/github-actions-apk-build.git ~/.agents/skills/github-actions-apk-build
bash ~/.agents/skills/github-actions-apk-build/install.sh
```

---

## 📱 How to Trigger the Skill in Your Agent

Once installed, invoke the skill anytime in your conversation using plain natural language or slash commands:

- `/github actions build apk`
- `/github actions`
- `build apk`
- `compile this android project on github actions and send apk to telegram`
- `build apk for https://github.com/user/my-android-app`

---

## 🔑 Telegram Setup (One-Time)

To receive APK builds directly on your phone:
1. **Telegram Bot Token:** Get a token from [@BotFather](https://t.me/BotFather) on Telegram (`TELEGRAM_TOKEN`).
2. **Telegram Chat ID:** Get your numeric chat ID from [@userinfobot](https://t.me/userinfobot) on Telegram (`TELEGRAM_CHAT_ID`).
3. Set secrets in your target GitHub repository via `gh` or web settings:
   ```bash
   gh secret set TELEGRAM_TOKEN
   gh secret set TELEGRAM_CHAT_ID
   ```

---

## 🛠 Supported Scenarios

| Scenario | Behavior |
| :--- | :--- |
| **Unhosted Local Directory** | Initializes Git, generates `.gitignore`, creates private GitHub repo via `gh repo create`, commits, injects CI, and triggers build. |
| **Existing Local Repo** | Syncs with `origin`, injects `.github/workflows/build-apk.yml`, commits, pushes, and triggers cloud build. |
| **Remote Repository (URL or Keyword)** | Clones repo into isolated `/tmp` workspace, injects CI workflow, pushes, and triggers build without cluttering working folder. |

---

## 📄 License

MIT License. Free to use, modify, and distribute.
