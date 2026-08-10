# Complete MacBook Setup Guide — 67 Nights in the Forest

> **For:** MacBook Air M5 (Apple Silicon) — also works on any Mac with Apple Silicon (M1/M2/M3/M4/M5).
> **Goal:** Go from a brand-new Mac with nothing installed to a fully working development environment for this Roblox project.
> **Time needed:** ~45–60 minutes (mostly downloads and installs).

---

## Table of Contents

1. [What This Project Uses](#1-what-this-project-uses)
2. [Install Xcode Command Line Tools](#2-install-xcode-command-line-tools)
3. [Install Homebrew](#3-install-homebrew)
4. [Configure Git](#4-configure-git)
5. [Set Up GitHub SSH Authentication](#5-set-up-github-ssh-authentication)
6. [Install Roblox Studio](#6-install-roblox-studio)
7. [Install Rokit (Toolchain Manager)](#7-install-rokit-toolchain-manager)
8. [Install Windsurf IDE](#8-install-windsurf-ide)
9. [Install Windsurf Extensions](#9-install-windsurf-extensions)
10. [Clone the Repository](#10-clone-the-repository)
11. [Install Project Tools (Rojo + Wally)](#11-install-project-tools-rojo--wally)
12. [Install Wally Packages](#12-install-wally-packages)
13. [Install the Rojo Studio Plugin](#13-install-the-rojo-studio-plugin)
14. [Transfer the Place File from Your Windows PC](#14-transfer-the-place-file-from-your-windows-pc)
15. [Build and Open the Place File](#15-build-and-open-the-place-file)
16. [Start Live Sync (Rojo Serve)](#16-start-live-sync-rojo-serve)
17. [Daily Workflow — Every Time You Sit Down to Code](#17-daily-workflow--every-time-you-sit-down-to-code)
18. [Troubleshooting](#18-troubleshooting)

---

## 1. What This Project Uses

| Tool | Version | What It Does |
|------|---------|-------------|
| **Git** | any recent | Version control — pushes/pulls code to GitHub |
| **Roblox Studio** | latest | The game engine + visual editor where maps, NPCs, and items live |
| **Rokit** | latest | Toolchain manager — installs and pins exact versions of Rojo and Wally |
| **Rojo** | 7.6.1 (pinned) | Syncs `.luau` files between your filesystem and Roblox Studio in real time |
| **Wally** | 0.3.2 (pinned) | Package manager — downloads Knit, ProfileService, Janitor, Signal, Promise, ZonePlus |
| **Windsurf IDE** | latest | Code editor (what you're using right now on Windows) |
| **Luau LSP** | latest | Language server extension for Windsurf — autocomplete, type checking, go-to-definition |

**Important concept:** This project uses a "split" workflow:
- **Code (scripts)** lives in `.luau` files on your filesystem, managed by Git, synced to Studio via Rojo.
- **Assets (maps, NPCs, items, UI)** live inside the Roblox Studio place file (`.rbxlx`), which is **not** in Git.
- This means you need **both** the cloned Git repo **and** the `.rbxlx` place file to work on this project.

---

## 2. Install Xcode Command Line Tools

This installs `git`, `make`, and other basic development tools on your Mac. You do **not** need the full Xcode app (which is 12+ GB).

### Steps

1. Open the **Terminal** app:
   - Press `Cmd + Space` to open Spotlight Search
   - Type `Terminal` and press `Enter`

2. Run this command:
   ```bash
   xcode-select --install
   ```

3. A dialog will pop up saying "The 'xcode-select' command requires the command line developer tools. Would you like to install the tools now?"
   - Click **Install**

4. Wait for the download and installation to complete (typically 5–10 minutes depending on your internet speed).

5. Click **Done** when it finishes.

6. Verify the installation:
   ```bash
   git --version
   ```
   You should see something like `git version 2.39.3` or newer.

---

## 3. Install Homebrew

Homebrew is a package manager for macOS. We need it as a fallback for installing some tools, and it's generally useful.

### Steps

1. In Terminal, paste this command and press `Enter`:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. It will show you what it's going to do and ask for your password. Type your Mac login password (it won't show characters as you type — this is normal) and press `Enter`.

3. Wait for the installation to finish (5–10 minutes).

4. **Critical — Add Homebrew to your PATH.** After installation, the terminal output will show you two commands to run. They look like this (copy them from your terminal output, not from here — the exact text may vary):
   ```bash
   (echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> /Users/YOUR_USERNAME/.zprofile
   eval "$(/opt/homebrew/bin/brew shellenv)"
   ```
   Replace `YOUR_USERNAME` with your actual Mac username. Run both commands.

5. Verify:
   ```bash
   brew --version
   ```
   You should see `Homebrew 4.x.x`.

---

## 4. Configure Git

Set your name and email so your commits are properly attributed.

### Steps

1. In Terminal, run:
   ```bash
   git config --global user.name "Your Full Name"
   git config --global user.email "your.email@example.com"
   ```
   Replace with the **same name and email** you used on your Windows machine (check by running `git config --global user.name` and `git config --global user.email` on your Windows PC).

2. Configure line endings (important since the project was started on Windows):
   ```bash
   git config --global core.autocrlf input
   ```
   This tells Git to convert CRLF (Windows) line endings to LF (Unix) when committing, which is correct for macOS.

3. Set the default branch name to match the project:
   ```bash
   git config --global init.defaultBranch main
   ```

---

## 5. Set Up GitHub SSH Authentication

You need SSH keys to securely push/pull code to and from GitHub without typing your password every time.

### Step 5.1 — Generate an SSH Key

1. In Terminal, run:
   ```bash
   ssh-keygen -t ed25519 -C "your.email@example.com"
   ```
   Use the **same email** as your GitHub account.

2. When prompted "Enter file in which to save the key", press `Enter` to accept the default location (`/Users/YOUR_USERNAME/.ssh/id_ed25519`).

3. When prompted for a passphrase, you can either:
   - Type a passphrase (more secure — you'll need to enter it once per session)
   - Press `Enter` twice to leave it empty (easier, slightly less secure)

### Step 5.2 — Add the SSH Key to Your Mac

1. Start the SSH agent:
   ```bash
   eval "$(ssh-agent -s)"
   ```

2. Create or edit the SSH config file:
   ```bash
   touch ~/.ssh/config
   open -e ~/.ssh/config
   ```
   This opens the file in TextEdit. Add these lines:
   ```
   Host github.com
     AddKeysToAgent yes
     UseKeychain yes
     IdentityFile ~/.ssh/id_ed25519
   ```
   Save the file (`Cmd + S`) and close TextEdit (`Cmd + Q`).

3. Add your key to the SSH agent:
   ```bash
   ssh-add --apple-use-keychain ~/.ssh/id_ed25519
   ```

### Step 5.3 — Add the SSH Key to GitHub

1. Copy your public key to the clipboard:
   ```bash
   pbcopy < ~/.ssh/id_ed25519.pub
   ```

2. Open your browser and go to: **https://github.com/settings/keys**

3. Click **New SSH key**.

4. In the "Title" field, type something like `MacBook Air M5`.

5. In the "Key" field, paste (`Cmd + V`).

6. Click **Add SSH key**.

### Step 5.4 — Test the Connection

1. In Terminal, run:
   ```bash
   ssh -T git@github.com
   ```

2. You'll see a message like:
   ```
   The authenticity of host 'github.com' (140.82.112.3) can't be established.
   ED25519 key fingerprint is SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU.
   Are you sure you want to continue connecting (yes/no/[fingerprint])?
   ```
   Type `yes` and press `Enter`.

3. You should see:
   ```
   Hi manikkDev! You've successfully authenticated, but GitHub does not provide shell access.
   ```
   (Your username will appear instead of `manikkDev`.)

---

## 6. Install Roblox Studio

Roblox Studio has native Apple Silicon support, so it runs fast on M5 chips without Rosetta.

### Steps

1. Open your browser and go to: **https://create.roblox.com/docs/studio/setup**

2. Click the **Download Studio** button.

3. A file called `RobloxStudio.dmg` will download.

4. Find it in your Downloads folder and **double-click** it to open the disk image.

5. A window will appear with the Roblox Studio icon and an Applications folder shortcut. **Drag the Roblox Studio icon into the Applications folder**.

6. Open the **Applications** folder (Finder → Go → Applications, or `Cmd + Shift + A` in Finder).

7. Find **Roblox Studio**, right-click it, and select **Open**.

8. A security warning will appear saying "Roblox Studio is an app downloaded from the Internet. Are you sure you want to open it?" — click **Open**.

9. Roblox Studio will launch and ask you to log in. Log in with your Roblox account.

10. After logging in, close Roblox Studio for now (`Cmd + Q`).

---

## 7. Install Rokit (Toolchain Manager)

Rokit is a toolchain manager that reads the `rokit.toml` file in the project and installs the exact pinned versions of Rojo and Wally. This ensures you have the **same versions** as the Windows machine.

### Steps

1. In Terminal, run:
   ```bash
   curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
   ```

2. The script will download and install Rokit. It will print instructions about adding Rokit to your PATH.

3. **Add Rokit to your PATH.** The installer will show you a command like this — run it:
   ```bash
   echo 'export PATH="$HOME/.rokit/bin:$PATH"' >> ~/.zprofile
   source ~/.zprofile
   ```

4. Verify:
   ```bash
   rokit --version
   ```
   You should see `rokit 1.x.x`.

---

## 8. Install Windsurf IDE

Windsurf is the AI-powered IDE you're currently using on Windows. It's a fork of VS Code, so it supports VS Code extensions.

### Steps

1. Open your browser and go to: **https://windsurf.com/editor**

2. Click **Download** and select **Mac (Universal)**.

3. A `.dmg` file will download.

4. Double-click the `.dmg` file to open it.

5. Drag the **Windsurf** icon into the **Applications** folder.

6. Open the **Applications** folder, find **Windsurf**, right-click it, and select **Open**.

7. A security warning will appear — click **Open**.

8. Windsurf will launch. Follow the on-screen setup:
   - Pick your theme (Dark is recommended)
   - Sign in with your Codeium/Windsurf account (the same one you use on Windows)
   - If prompted to import settings from VS Code, you can skip this

9. When asked about installing the `windsurf` terminal command, say **Yes** — this lets you open projects from the terminal with `windsurf .`.

---

## 9. Install Windsurf Extensions

You need the Luau Language Server extension for autocomplete, type checking, and go-to-definition in `.luau` files.

### Steps

1. Open Windsurf.

2. Open the Extensions panel:
   - Press `Cmd + Shift + X`
   - Or click the Extensions icon in the left sidebar (it looks like four squares)

3. Search for: **Luau Language Server**

4. Find the one by **JohnnyMorganz** (the extension ID is `JohnnyMorganz.luau-lsp`).

5. Click **Install**.

6. Wait for it to install, then reload if prompted.

### Optional: Configure Luau LSP for Rojo

The Luau LSP can use Rojo's sourcemap to understand the DataModel hierarchy for better intellisense. To enable this:

1. In Windsurf, open Settings:
   - Press `Cmd + ,` (comma)
   - Or go to Windsurf → Settings → Settings

2. Search for `luau-lsp.sourcemap`

3. Make sure **Luau-lsp: Sourcemap.enabled** is checked (it should be by default).

4. Make sure **Luau-lsp: Sourcemap.autogenerate** is checked.

5. The LSP will automatically run `rojo sourcemap` when you have the project open. This requires Rojo to be installed (which you'll do in Step 11).

---

## 10. Clone the Repository

Now you'll download the project code from GitHub to your Mac.

### Steps

1. Decide where you want to store the project. A common location is `~/Developer/` or `~/Projects/`. Let's use `~/Developer/`:

   ```bash
   mkdir -p ~/Developer
   cd ~/Developer
   ```

2. Clone the repository using SSH:
   ```bash
   git clone git@github.com:manikkDev/67-nights-in-the-forest.git
   ```

3. When prompted "Are you sure you want to continue connecting?", type `yes` and press `Enter` (if you haven't already connected to GitHub from this machine).

4. The repository will download. You'll see a folder called `67-nights-in-the-forest`.

5. Navigate into it:
   ```bash
   cd 67-nights-in-the-forest
   ```

6. Verify you're on the `main` branch:
   ```bash
   git branch
   ```
   You should see `* main`.

7. Verify the project files are there:
   ```bash
   ls -la
   ```
   You should see `default.project.json`, `wally.toml`, `wally.lock`, `rokit.toml`, `src/`, etc.

---

## 11. Install Project Tools (Rojo + Wally)

Rokit will read the `rokit.toml` file in the project and install the exact pinned versions of Rojo (7.6.1) and Wally (0.3.2).

### Steps

1. Make sure you're inside the project directory:
   ```bash
   cd ~/Developer/67-nights-in-the-forest
   ```

2. Run:
   ```bash
   rokit install
   ```

3. Rokit will download and install:
   - **Rojo 7.6.1** (from `rojo-rbx/rojo@7.6.1` in `rokit.toml`)
   - **Wally 0.3.2** (from `UpliftGames/wally@0.3.2` in `rokit.toml`)

4. This may take 1–2 minutes. You'll see progress bars for each download.

5. Verify Rojo:
   ```bash
   rojo --version
   ```
   You should see `rojo 7.6.1`.

6. Verify Wally:
   ```bash
   wally --version
   ```
   You should see `wally 0.3.2`.

> **Note:** If `rojo` or `wally` commands are not found, close your Terminal, open a new one, and try again. Rokit adds tools to your PATH, but the current terminal session may not have picked up the change yet.

---

## 12. Install Wally Packages

Wally will read `wally.toml` and `wally.lock` and download all the Lua packages the project depends on.

### Steps

1. Make sure you're still in the project directory:
   ```bash
   cd ~/Developer/67-nights-in-the-forest
   ```

2. Run:
   ```bash
   wally install
   ```

3. Wally will download these packages (exact versions from `wally.lock`):

   | Package | Version | Type |
   |---------|---------|------|
   | Knit | 1.7.0 | shared |
   | Comm (Knit dependency) | 1.0.1 | shared |
   | Option (Knit dependency) | 1.0.5 | shared |
   | Janitor | 1.18.3 | shared |
   | typed-promise (Janitor dependency) | 4.0.6 | shared |
   | Signal | 2.0.3 | shared |
   | Promise | 4.0.0 | shared |
   | ZonePlus | 3.2.1 | shared |
   | ProfileService | 1.0.0 | server-only |

4. After installation, you'll see two new folders:
   - `Packages/` — shared packages (synced to `ReplicatedStorage.Packages`)
   - `ServerPackages/` — server-only packages (synced to `ServerScriptService.ServerPackages`)

5. These folders are in `.gitignore` and are **not** committed to Git. They are regenerated by `wally install` every time.

6. Verify the folders exist:
   ```bash
   ls Packages/
   ls ServerPackages/
   ```
   You should see subfolders like `Knit`, `Janitor`, `Signal`, `Promise`, `ZonePlus` in `Packages/`, and `ProfileService` in `ServerPackages/`.

---

## 13. Install the Rojo Studio Plugin

Rojo has two parts: the **server** (CLI tool, already installed) and a **Studio plugin** (a button inside Roblox Studio that connects to the server). You need both.

### Steps

1. In Terminal, make sure you're in the project directory:
   ```bash
   cd ~/Developer/67-nights-in-the-forest
   ```

2. Run:
   ```bash
   rojo plugin install
   ```

3. This installs the Rojo plugin into Roblox Studio's plugins folder (`~/Documents/Roblox/Plugins/`).

4. If the command fails or the plugin doesn't appear in Studio, you can install it manually:
   - Go to the Rojo 7.6.1 release page: **https://github.com/rojo-rbx/rojo/releases/tag/v7.6.1**
   - Download the `Rojo.rbxm` file
   - Open Finder, press `Cmd + Shift + G`, and navigate to: `~/Documents/Roblox/Plugins/`
   - If the `Roblox` or `Plugins` folder doesn't exist, create them:
     ```bash
     mkdir -p ~/Documents/Roblox/Plugins
     ```
   - Copy `Rojo.rbxm` into that folder

5. Alternatively, install from the Roblox plugin page:
   - Go to: **https://create.roblox.com/marketplace/asset/13916111004/Rojo**
   - Click **Install**

6. To verify the plugin is installed:
   - Open Roblox Studio
   - Look at the top ribbon for a **ROJO** tab
   - If you see it, the plugin is installed correctly

---

## 14. Transfer the Place File from Your Windows PC

> **This is the most critical step. Do not skip it.**

The `.rbxlx` place file contains all the game's assets — maps (`Base-map`, `lobby-map`), NPCs (wolves, bears, deer, cultists), items (axes, logs, carrots), and UI elements. These assets are **not** in the Git repo — only the scripts are. Without this file, you'll have a project with code but no world to run it in.

The place file is located on your Windows PC at:
```
D:\Roblox Studio Games\67 nights in the forest\67 nights in the forest.rbxlx
```

### Option A — Transfer via Cloud Storage (Recommended)

1. On your **Windows PC**, open File Explorer and navigate to:
   ```
   D:\Roblox Studio Games\67 nights in the forest\
   ```

2. Find the file `67 nights in the forest.rbxlx`.

3. Upload it to a cloud service:
   - **Google Drive**: drag and drop the file into your Google Drive in the browser
   - **iCloud Drive**: if you have iCloud Drive set up on Windows, copy it there
   - **Dropbox**: drag and drop into Dropbox
   - **OneDrive**: drag and drop into OneDrive

4. On your **Mac**, download the file from the same cloud service.

5. Move the downloaded file into your project folder:
   ```bash
   mv ~/Downloads/67\ nights\ in\ the\ forest.rbxlx ~/Developer/67-nights-in-the-forest/
   ```

### Option B — Transfer via USB Drive

1. Plug a USB drive into your Windows PC.
2. Copy `67 nights in the forest.rbxlx` onto the USB drive.
3. Eject the USB drive and plug it into your Mac.
4. The USB drive will appear on your Desktop or in Finder under "Locations".
5. Copy the `.rbxlx` file to your project folder:
   ```bash
   cp /Volumes/YOUR_USB_NAME/67\ nights\ in\ the\ forest.rbxlx ~/Developer/67-nights-in-the-forest/
   ```

### Option C — Transfer via AirDrop (if you have an iPhone as intermediary)

1. AirDrop the `.rbxlx` file from your Windows PC to your iPhone (via a cloud service, since Windows doesn't support AirDrop directly).
2. AirDrop from your iPhone to your Mac.
3. Move the file from Downloads to the project folder.

### Option D — If the Game Is Published to Roblox

If you have already published this game to Roblox (even as a private/unpublished experience):

1. Open Roblox Studio on your Mac.
2. Click **Open** from the start screen.
3. Select the experience from the list.
4. Once it loads, go to **File → Save As File...** and save it as `67 nights in the forest.rbxlx` inside your project folder:
   ```
   ~/Developer/67-nights-in-the-forest/
   ```

### Verify the Place File

1. Check that the file exists in your project folder:
   ```bash
   ls -la ~/Developer/67-nights-in-the-forest/*.rbxlx
   ```
   You should see `67 nights in the forest.rbxlx` with a file size of several MB (it contains all the maps and assets).

---

## 15. Build and Open the Place File

Before opening the place file in Studio, let's do a one-time build to make sure Rojo can sync all the scripts and packages into it.

### Step 15.1 — Initial Build (Optional but Recommended)

This step merges your filesystem scripts + Wally packages into the place file. **Only do this on a copy** of the place file, not the original, in case something goes wrong.

1. Make a backup copy first:
   ```bash
   cd ~/Developer/67-nights-in-the-forest
   cp "67 nights in the forest.rbxlx" "67 nights in the forest BACKUP.rbxlx"
   ```

2. Run the build:
   ```bash
   rojo build -o "67 nights in the forest.rbxlx"
   ```
   This takes the scripts from `src/` and the packages from `Packages/` + `ServerPackages/` and merges them into the place file.

3. You should see output like:
   ```
   Built project to 67 nights in the forest.rbxlx in 0.42s
   ```

> **Warning:** If the build overwrites your assets (maps, NPCs), restore from the backup and skip this step — just open the original `.rbxlx` file directly in Studio and use `rojo serve` to sync scripts live. The `rojo build` command creates a fresh place from `default.project.json`, which only contains scripts and package mappings, **not** the assets in `ServerStorage.Assets` or `Workspace`. If your assets disappear after building, use the backup and rely on `rojo serve` for live syncing instead.

### Step 15.2 — Open in Roblox Studio

1. Open **Roblox Studio**.

2. Click **Open** from the start screen, or go to **File → Open from File...**

3. Navigate to:
   ```
   ~/Developer/67-nights-in-the-forest/67 nights in the forest.rbxlx
   ```

4. Select the file and click **Open**.

5. Roblox Studio will load the place. You should see:
   - The `Base-map` and `lobby-map` in the Workspace
   - All the NPC models in `ServerStorage.Assets`
   - Scripts in `ServerScriptService`, `StarterPlayerScripts`, and `ReplicatedStorage`

---

## 16. Start Live Sync (Rojo Serve)

This is the core of the workflow: Rojo watches your filesystem for changes and instantly syncs them to Roblox Studio.

### Step 16.1 — Start the Rojo Server

1. Open Terminal and navigate to the project:
   ```bash
   cd ~/Developer/67-nights-in-the-forest
   ```

2. Start the Rojo sync server:
   ```bash
   rojo serve
   ```

3. You'll see output like:
   ```
   Rojo server listening on:
     http://127.0.0.1:34872
     http://192.168.x.x:34872
   ```

4. **Leave this terminal window open.** Rojo is now running and watching your files. As long as this terminal is open and `rojo serve` is running, changes to `.luau` files will instantly sync to Studio.

### Step 16.2 — Connect Roblox Studio to Rojo

1. In Roblox Studio, look at the top ribbon for the **ROJO** tab.
   - If you don't see it, the plugin isn't installed — go back to [Step 13](#13-install-the-rojo-studio-plugin).

2. Click the **ROJO** tab.

3. Click the **Connect** button.

4. A small panel will appear showing the connection status. It should say **Connected** and show `127.0.0.1:34872`.

5. If it doesn't connect automatically:
   - Click the **Settings** gear icon in the Rojo panel
   - Make sure the address is `127.0.0.1` and the port is `34872`
   - Click **Connect**

6. Once connected, you'll see a green indicator. Rojo is now syncing.

### Step 16.3 — Test the Sync

1. Open the project in Windsurf:
   ```bash
   cd ~/Developer/67-nights-in-the-forest
   windsurf .
   ```

2. Open any `.luau` file, for example `src/shared/Constants.luau`.

3. Make a small change (add a comment at the top: `-- Test sync`).

4. Save the file (`Cmd + S`).

5. Look at Roblox Studio — the change should appear instantly in the corresponding script.

6. If the change appears, your setup is complete and working!

---

## 17. Daily Workflow — Every Time You Sit Down to Code

Follow these steps every time you start a coding session on your Mac.

### Quick Start (Copy-Paste)

```bash
# 1. Navigate to the project
cd ~/Developer/67-nights-in-the-forest

# 2. Pull the latest changes from GitHub
git pull

# 3. Install any new/updated packages (if wally.toml changed)
wally install

# 4. Start the Rojo sync server (leave this terminal open)
rojo serve
```

Then:
1. Open Roblox Studio and open the `.rbxlx` place file
2. Click the **ROJO** tab → **Connect**
3. Open Windsurf: `windsurf .` (or open it from Applications)
4. Start coding — changes sync to Studio automatically

### When You're Done Coding

```bash
# 1. In the terminal where rojo serve is running, press Ctrl + C to stop it

# 2. Commit and push your changes
git add .
git commit -m "Describe what you changed"
git push
```

### If You Switched Computers (Windows → Mac or Mac → Windows)

Always run `git pull` first to get the latest code. The `.rbxlx` place file is not in Git, so if you made asset changes in Studio on the other computer, you'll need to transfer the updated `.rbxlx` file manually (repeat [Step 14](#14-transfer-the-place-file-from-your-windows-pc)).

---

## 18. Troubleshooting

### `rojo: command not found` or `wally: command not found`

Rokit's bin directory isn't in your PATH. Fix it:

```bash
echo 'export PATH="$HOME/.rokit/bin:$PATH"' >> ~/.zprofile
source ~/.zprofile
```

Then close your terminal, open a new one, and try again.

If that doesn't work, check where Rokit installed the tools:
```bash
ls ~/.rokit/bin/
```
You should see `rojo` and `wally` executables there.

### `git: command not found`

Xcode Command Line Tools aren't installed. Run:
```bash
xcode-select --install
```

### `brew: command not found`

Homebrew isn't in your PATH. Run:
```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

To make it permanent:
```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
```

### SSH connection to GitHub fails

1. Check if your SSH key exists:
   ```bash
   ls ~/.ssh/id_ed25519*
   ```
   You should see `id_ed25519` (private) and `id_ed25519.pub` (public).

2. If not, repeat [Step 5](#5-set-up-github-ssh-authentication).

3. Test the connection:
   ```bash
   ssh -T git@github.com
   ```

4. If it says "Permission denied (publickey)", your key isn't added to GitHub. Repeat [Step 5.3](#step-53--add-the-ssh-key-to-github).

### Rojo plugin not showing in Roblox Studio

1. Check if the plugin file exists:
   ```bash
   ls ~/Documents/Roblox/Plugins/
   ```
   You should see a `Rojo.rbxm` or similar file.

2. If the folder doesn't exist:
   ```bash
   mkdir -p ~/Documents/Roblox/Plugins
   ```
   Then re-run `rojo plugin install`.

3. Alternatively, install from the Roblox marketplace:
   - Go to **https://create.roblox.com/marketplace/asset/13916111004/Rojo**
   - Click **Install**

4. Restart Roblox Studio after installing the plugin.

### Rojo connects but changes don't sync

1. Make sure you're running `rojo serve` from the project directory (where `default.project.json` is):
   ```bash
   cd ~/Developer/67-nights-in-the-forest
   rojo serve
   ```

2. Check the Rojo terminal output for errors. If it says "no project file found", you're in the wrong directory.

3. Make sure the `.rbxlx` file you opened in Studio is the one in the project directory, not a copy elsewhere.

4. Try disconnecting and reconnecting in the Rojo Studio plugin panel.

### Wally packages missing after cloning

This is expected — `Packages/` and `ServerPackages/` are gitignored. Run:
```bash
wally install
```

### `wally install` fails with authentication error

Wally needs to download packages from GitHub. Make sure your GitHub SSH is set up (Step 5) and working:
```bash
ssh -T git@github.com
```

### Roblox Studio says "This file was created by a newer version of Studio"

You need to update Roblox Studio on your Mac. Studio auto-updates, so just close it and reopen it. If that doesn't work:
1. Delete Roblox Studio from Applications
2. Re-download from https://create.roblox.com/docs/studio/setup
3. Reinstall

### Luau LSP not showing autocomplete in Windsurf

1. Make sure the Luau Language Server extension is installed (`Cmd + Shift + X`, search for `luau-lsp`).
2. Make sure you have `rojo` installed and accessible (`rojo --version` should work).
3. The LSP needs a `sourcemap.json` file. It should auto-generate one when you open the project. Check if it exists:
   ```bash
   ls ~/Developer/67-nights-in-the-forest/sourcemap.json
   ```
4. If it doesn't exist, generate it manually:
   ```bash
   cd ~/Developer/67-nights-in-the-forest
   rojo sourcemap --output sourcemap.json
   ```
5. Reload Windsurf: `Cmd + Shift + P` → type "Reload Window" → press `Enter`.

### Place file opens but assets are missing

You likely ran `rojo build` which created a fresh place file with only scripts (no assets). Restore from your backup:
```bash
cd ~/Developer/67-nights-in-the-forest
cp "67 nights in the forest BACKUP.rbxlx" "67 nights in the forest.rbxlx"
```

If you don't have a backup, you need to re-transfer the place file from your Windows PC ([Step 14](#14-transfer-the-place-file-from-your-windows-pc)).

### "Port 34872 is already in use"

Another Rojo instance is already running. Find and kill it:
```bash
lsof -ti:34872 | xargs kill -9
```
Then run `rojo serve` again.

---

## Quick Reference — All Commands

```bash
# === ONE-TIME SETUP ===

# Install Xcode CLI tools
xcode-select --install

# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# Then add to PATH (follow terminal output instructions)

# Configure Git
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
git config --global core.autocrlf input
git config --global init.defaultBranch main

# Set up SSH key
ssh-keygen -t ed25519 -C "your.email@example.com"
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
pbcopy < ~/.ssh/id_ed25519.pub
# Paste the key into GitHub → Settings → SSH and GPG keys → New SSH key

# Install Rokit
curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
# Then add to PATH (follow terminal output instructions)

# Clone the repo
mkdir -p ~/Developer
cd ~/Developer
git clone git@github.com:manikkDev/67-nights-in-the-forest.git
cd 67-nights-in-the-forest

# Install project tools
rokit install

# Install packages
wally install

# Install Rojo Studio plugin
rojo plugin install

# Transfer the .rbxlx place file from your Windows PC (see Step 14)

# === DAILY WORKFLOW ===

cd ~/Developer/67-nights-in-the-forest
git pull
wally install          # only if wally.toml/wally.lock changed
rojo serve             # leave this running

# Then: open .rbxlx in Roblox Studio → ROJO tab → Connect
# Then: windsurf .      # open the project in Windsurf
```

---

*Last updated: August 2026. If anything in this guide becomes outdated, check the official docs for each tool.*
