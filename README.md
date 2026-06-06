# Capybara Paradise AddOns

[ English | [中文](README_zh.md) ]

This repository manages [Capybara Paradise](https://capycraft.io/) addons. Some addons are managed as Git submodules to easily fetch updates from upstream repositories.

## Managed Addons (Submodules)

- **pfQuest**: Quest helper addon (configured as a submodule from `https://github.com/The-Kludge-Bureau/pfQuest.git`).
- **pfQuest-turtle**: Capybara Paradise specific data and database overwrites for pfQuest (configured as a submodule from `https://github.com/The-Kludge-Bureau/pfQuest-turtle.git`).
- **Atlas**: Map addon (configured as a submodule from `https://github.com/Otari98/Atlas.git`).
- **AtlasLoot**: Loot tables database (configured as a submodule from `https://github.com/Otari98/AtlasLoot.git`).
- **AtlasQuest**: Quest information addon for Atlas (configured as a submodule from `https://github.com/Otari98/AtlasQuest.git`).

---

## Git Commands for Managing AddOns

### 1. Initial Setup (Cloning)
If you are cloning this repository for the first time, you must initialize and clone the submodules as well:
```bash
git clone https://github.com/liruqi/AddOns
cd AddOns
git submodule update --init --recursive
```

### 2. Updating Submodules
To update all submodules to the latest commits from their respective remote repositories:
```bash
git submodule update --remote --merge
```
*Note: `--merge` ensures that any local commits on the submodules (if any) are merged with the incoming updates.*

If you want to update a **specific** submodule only (e.g., just `pfQuest`):
```bash
git submodule update --remote --merge pfQuest
```

## Contributing

We welcome contributions! Please feel free to create a Pull Request (PR) to contribute.

If you would like to contribute to a specific addon, please patch that specific addon's upstream repository, or fork a new repository on your own.
