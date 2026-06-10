# Git Guide For This Project

## Why use Git here

This camera board project is exactly the kind of work that should use Git.

Reasons:

- you are changing shell scripts often
- board-side behavior changes step by step
- regressions are easy to introduce
- you need a clean way to compare, rollback, and tag stable milestones

Git should be used on the development computer.

The board should mainly be:

- a deploy target
- a test target

Not the main source-of-truth repository.

## Recommended workflow

Use this split:

1. edit code on your Windows computer
2. commit changes with Git on the computer
3. push files to the board with `adb push`
4. test on the board
5. if test passes, commit the next step

This keeps:

- source history on the computer
- runtime validation on the board

## Core Git idea

Git is a content history system.

It tracks snapshots of your files over time.

Three important areas:

1. working tree
   - your current files on disk
2. staging area
   - the exact changes you want in the next commit
3. repository history
   - committed snapshots

Think of it like this:

- edit files
- choose what to include
- save a named snapshot

## Key Git concepts

### Repository

A repository is a folder managed by Git.

It contains:

- your project files
- a hidden `.git` directory

### Commit

A commit is a saved project snapshot with a message.

Examples:

- `feat: add cli wifi provisioning`
- `fix: stabilize aic8800 ap startup`

### Branch

A branch is a movable pointer to a sequence of commits.

Most small embedded projects can start with one main branch:

- `main`

Later you can create feature branches if needed.

### Checkout / switch

This means changing which branch or commit your working tree follows.

### Diff

A diff is the line-by-line change between versions.

### Merge

A merge combines changes from one branch into another.

## Why not develop mainly on the board

You technically can if Git is installed there, but it is the wrong default.

Problems:

- board storage is small
- board tools are limited
- editing is inconvenient
- you may forget to sync changes back
- board state and source state can drift apart

Better model:

- computer is source control center
- board is deployment target

## Install Git on Windows

Preferred source:

- official Git for Windows installer

After install, verify:

```powershell
git --version
```

## First-time Git setup

Run once on your computer:

```powershell
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main
```

Check config:

```powershell
git config --global --list
```

## Start Git in this project

Open PowerShell:

```powershell
cd "D:\camera\board app"
git init
```

This creates:

```text
.git/
```

Then check status:

```powershell
git status
```

## First commit

Stage all files:

```powershell
git add .
```

Create first commit:

```powershell
git commit -m "init: add busybox camera board network scaffolding"
```

## Daily workflow

### 1. Check current changes

```powershell
git status
```

### 2. See exact line changes

```powershell
git diff
```

### 3. Stage selected changes

Stage all:

```powershell
git add .
```

Stage one file:

```powershell
git add scripts/start_ap.sh
```

### 4. Commit

```powershell
git commit -m "fix: re-apply ap ip after hostapd startup"
```

## Good commit strategy for this project

Commit by functional milestone, not by random file batch.

Good commit examples:

- `init: add ap bring-up scaffold`
- `fix: stabilize aic8800 ap startup timing`
- `fix: persist udhcpd lease file under runtime`
- `feat: add cli wifi provisioning`
- `feat: add sta connection scripts`

Bad commit examples:

- `update`
- `fix stuff`
- `test`

## Git status meanings

`git status` usually shows these categories:

- `untracked`
  - file is new and Git is not tracking it yet
- `modified`
  - tracked file changed
- `staged`
  - file is prepared for next commit

## Common commands

### View history

```powershell
git log --oneline
```

More detailed:

```powershell
git log
```

### Show changes in one commit

```powershell
git show <commit_id>
```

### Compare working tree to last commit

```powershell
git diff
```

### Compare staged changes

```powershell
git diff --cached
```

## Branch usage

For now, simplest is:

- keep using `main`

If later you need isolated work:

Create branch:

```powershell
git switch -c feature/sta-connect
```

Switch back:

```powershell
git switch main
```

## How rollback works

There are several rollback styles.

### Undo unstaged file changes

```powershell
git restore scripts/start_ap.sh
```

Use carefully.

This discards local unstaged edits in that file.

### Unstage a file

```powershell
git restore --staged scripts/start_ap.sh
```

### Revert a commit safely

```powershell
git revert <commit_id>
```

This is safer than history rewriting because it adds a new commit that undoes an older one.

## What not to use casually

Avoid using these until you are fully sure:

```powershell
git reset --hard
```

```powershell
git clean -fd
```

These can destroy local work.

## Git and board deployment

Recommended loop:

1. make code changes on computer
2. run:

```powershell
git diff
```

3. deploy to board:

```powershell
adb push scripts /userdata/ap_test/
adb push conf /userdata/ap_test/
```

4. test on board
5. if correct, commit

This gives you a useful boundary:

- deployment is not the same thing as commit
- commit happens only after meaningful validation

## Suggested milestones to commit

Based on current project state, a good commit sequence is:

1. AP scaffold
2. AIC8800 driver startup stabilization
3. DHCP fix for AP mode
4. CLI provisioning
5. STA networking
6. boot-time AP/STA state machine
7. SD card record path migration
8. control + video transport

## Add a .gitignore

You should ignore runtime artifacts.

Suggested entries:

```gitignore
runtime/*
!runtime/.gitkeep
```

Possibly also:

```gitignore
*.log
```

If you want, create it in project root as `.gitignore`.

## Remote repository

If later you want backup or collaboration, create a remote repository on:

- GitHub
- GitLab
- Gitea

Then add remote:

```powershell
git remote add origin <repo_url>
```

Push first time:

```powershell
git push -u origin main
```

## Useful command summary

Initialize:

```powershell
git init
```

Check status:

```powershell
git status
```

See changes:

```powershell
git diff
```

Stage all:

```powershell
git add .
```

Commit:

```powershell
git commit -m "message"
```

History:

```powershell
git log --oneline
```

Restore file:

```powershell
git restore <file>
```

## Best practice for your current project

Use Git as your development ledger.

Meaning:

- every stable step gets a commit
- every risky experiment can be isolated
- board-side behavior can always be traced back to exact files

For embedded and board bring-up work, this matters a lot because many bugs come from:

- startup order
- one-line config changes
- driver timing tweaks
- test-only edits left behind

Git prevents these from becoming invisible history.
