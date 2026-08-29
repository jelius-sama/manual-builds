# manual-builds

This repository is an pseudo-automated build system designed to compile binaries inside isolated Docker environments (currently Amazon Linux 2023) via GitHub Actions.

It uses a decoupled structure where build scripts reside on the `main` branch, while the actual source code for the target applications is maintained as Git submodules on separate, dedicated branches.

## 🏗️ Architecture & How It Works

The build system relies on a few moving parts working together:

1. **`payload.txt`**: The configuration file on the `main` branch. It contains a single string (e.g., `vaultwarden`), which acts as the target name.
2. **The Build Script (`<target>.sh`)**: A bash script on the `main` branch named after the payload. This script contains the specific OS dependencies and compilation commands for that target.
3. **The Target Branch**: A branch named identically to the payload. It contains a Git submodule of the same name pointing to the source code to be compiled.
4. **GitHub Actions**: Reads `payload.txt`, spins up an AL2023 Docker container, mounts the workspace, and runs the target build script. The script checks out the target branch, pulls the submodule, builds the code, and saves the binary.

## 📜 The Build Protocol

The system holds together entirely through naming conventions and a small file-based contract between the four moving parts. There's no central registry — everything is inferred from string matching. Breaking any rule below breaks the pipeline silently or loudly, so treat this as the spec.

### 1. Identity string

Every target is identified by a single lowercase string (e.g. `vaultwarden`). This exact string must be reused, unmodified, in four places:

| Where | Role |
|---|---|
| `payload.txt` (on `main`) | Selects the active target |
| `<name>.sh` (on `main`) | Build script for that target |
| `<name>` branch | Holds the target's submodule |
| `<name>/` submodule directory | Source checked out on that branch |

If any of these four don't match exactly, the workflow fails at either the `chmod +x <name>.sh` step (script not found) or the `cd "$TARGET_REF"` step in the build script (directory not found).

### 2. Environment contract

The workflow passes the payload value into the container as `TARGET_REF`. Every build script must:

- Fail fast if `TARGET_REF` is unset (`[ -z "${TARGET_REF:-}" ]`).
- Use `TARGET_REF` for both the branch checkout and the submodule directory name — never hardcode either.

### 3. Build script responsibilities

A conforming `<name>.sh` must, in order:

1. Install its own OS/toolchain dependencies (the container starts bare — nothing is pre-installed between targets).
2. `git config --global --add safe.directory` for both `/workspace` and `/workspace/$TARGET_REF` before touching git.
3. `git fetch --all --tags` and `git checkout "$TARGET_REF"`.
4. `git submodule update --init --recursive`.
5. `cd "$TARGET_REF"` and verify the directory exists before proceeding.
6. Build the project. The script owns any target-specific pinning (a fixed tag, a tracked branch, etc.) — the pipeline has no opinion here.
7. Verify the expected binary artifact exists before copying it — never assume the build succeeded silently.

### 4. Output contract

On success, a script must leave behind, in `../output_binaries/` (i.e. the repo root, one level up from the submodule):

- The compiled binary, `chmod +x`'d.
- `release_tag.txt`, containing exactly `${TARGET_REF}-$(git rev-parse --short HEAD)` and nothing else.

The workflow reads `release_tag.txt` to decide the release tag and then deletes it before uploading artifacts — its absence is the pipeline's signal that the build produced nothing releasable, and skips the release step without failing the run.

### 5. Idempotency guarantee

Because the tag is derived from `<name>-<short-sha>`, re-running the workflow against an unchanged submodule commit reproduces the same tag. The workflow checks `gh release view "$TAG_NAME"` first and skips release creation if it already exists — so repeated or accidental triggers are safe and never produce duplicate releases.

## 🚀 How to Trigger a Build

1. Switch to the `main` branch.
2. Edit the `payload.txt` file to contain the name of the project you want to build (e.g., `vaultwarden`).
3. Commit and push the change, or manually trigger the workflow from the **Actions** tab.
4. Once the build finishes, download the `.zip` artifact containing the compiled binaries from the workflow summary page.

---

## ➕ How to Add a New Project

To add a new application (e.g., `my-new-app`) to the build system, follow these steps:

### 1. Create the Target Branch & Submodule
First, create a new branch to hold the submodule.

```bash
# Create and switch to a new branch
git checkout -b my-new-app

# Add the source code repository as a submodule
git submodule add https://github.com/author/my-new-app.git my-new-app

# Commit the submodule setup
git commit -m "Add my-new-app submodule"
git push origin my-new-app
```

### 2. Create the Build Script

Switch back to your `main` branch and create a build script named after your project.

```bash
git checkout main
touch my-new-app.sh
chmod +x my-new-app.sh
```

Use the existing `vaultwarden.sh` as a template. Make sure the script:

* Captures the `$TARGET_REF` environment variable.
* Checks out the `$TARGET_REF` branch.
* Initializes the submodules (`git submodule update --init --recursive`).
* Navigates into the submodule directory.
* Installs dependencies, compiles the code, and moves the final binary to `../output_binaries/`.

### 3. Update the Payload

Change the contents of `payload.txt` to point to your new project:

```text
my-new-app
```

Commit `my-new-app.sh` and `payload.txt` to the `main` branch, and push. The GitHub Action will automatically pick up the new payload and run the correct script.
