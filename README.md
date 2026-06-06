# [Capybara Paradise](https://capycraft.io/) AddOns

This repository manages World of Warcraft (Classic / [Capybara Paradise](https://capycraft.io/)) addons. Some addons are managed as Git submodules to easily fetch updates from upstream repositories.

## Managed Addons (Submodules)

- **pfQuest**: Quest helper addon (configured as a submodule from `https://github.com/The-Kludge-Bureau/pfQuest.git`).
- **pfQuest-turtle**: [Capybara Paradise](https://capycraft.io/) specific data and database overwrites for pfQuest (configured as a submodule from `https://github.com/The-Kludge-Bureau/pfQuest-turtle.git`).

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

### 3. Committing Submodule Updates
After updating the submodules, you should commit the updated submodule pointers in the main repository:
```bash
git add pfQuest pfQuest-turtle
git commit -m "Update submodules to latest upstream"
git push
```
