# Roblox iOS Executor (dylib)

Executor dylib for Roblox iOS. Built via GitHub Actions, ready for injection.

## Build

GitHub Actions builds automatically on push. Download the artifact `executor-dylib` from the Actions tab.

## Local build (requires macOS + Theos)

```bash
export THEOS=$HOME/theos
make clean
make package FINALPACKAGE=1
