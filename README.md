# Capybara Paradise AddOns

[ English | [中文](README_zh.md) ]

This repository manages [Capybara Paradise](https://capycraft.io/) addons. Some addons are managed as Git submodules to easily fetch updates from upstream repositories.

## Managed Addons (Submodules)

- **pfQuest**: Quest helper addon (configured as a submodule from [liruqi/pfQuest](https://github.com/liruqi/pfQuest.git)).
- **pfQuest-turtle**: Capybara Paradise specific data and database overwrites for pfQuest (configured as a submodule from [The-Kludge-Bureau/pfQuest-turtle](https://github.com/The-Kludge-Bureau/pfQuest-turtle.git)).
- **Atlas**: Map addon (configured as a submodule from [Otari98/Atlas](https://github.com/Otari98/Atlas.git)).
- **AtlasLoot**: Loot tables database (configured as a submodule from [Otari98/AtlasLoot](https://github.com/Otari98/AtlasLoot.git)).
- **AtlasQuest**: Quest information addon for Atlas (configured as a submodule from [Otari98/AtlasQuest](https://github.com/Otari98/AtlasQuest.git)).
- **Automatonex**: A collection of automation modules used by the project (configured as a submodule from [liruqi/Automatonex](https://github.com/liruqi/Automatonex.git)).
- **Cat**: Class automation and combat helper modules (configured as a submodule from [liruqi/Cat](https://github.com/liruqi/Cat.git)).

---

## Download AddOns

### 1. One-time Download
You can download the addon package directly from the GitHub releases page:

https://github.com/liruqi/AddOns/releases

### 2. Download/Update via Git
If you want to manage the repository with Git, use the following commands.

#### Initial Setup (Cloning)
If you are cloning this repository for the first time, you must initialize and clone the submodules as well:
```bash
git clone https://github.com/liruqi/AddOns
cd AddOns
git submodule update --init --recursive
```

#### Updating Submodules
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

We welcome contributions! Please feel free to create a [Pull Request](https://github.com/liruqi/AddOns/pulls) to contribute.

If you would like to contribute to a specific addon, please patch that specific addon's upstream repository, or fork a new repository on your own.

If profession-specific addons are needed later, we will create separate branches for each profession that has demand.
