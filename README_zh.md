# Capybara Paradise 插件

[ [English](README.md) | 中文 ]

本仓库管理 [Capybara Paradise](https://capycraft.io/) 插件。部分插件以 Git 子模块（submodule）的形式进行管理，以便于从上游仓库获取更新。

## 已管理的插件（子模块）

- **pfQuest**：任务助手插件（配置为来自 [The-Kludge-Bureau/pfQuest](https://github.com/The-Kludge-Bureau/pfQuest.git) 的子模块）。
- **pfQuest-turtle**：针对 pfQuest 的 Capybara Paradise 特定数据和数据库覆盖（配置为来自 [The-Kludge-Bureau/pfQuest-turtle](https://github.com/The-Kludge-Bureau/pfQuest-turtle.git) 的子模块）。
- **Atlas**：地图浏览插件（配置为来自 [Otari98/Atlas](https://github.com/Otari98/Atlas.git) 的子模块）。
- **AtlasLoot**：掉落查询数据库（配置为来自 [Otari98/AtlasLoot](https://github.com/Otari98/AtlasLoot.git) 的子模块）。
- **AtlasQuest**：Atlas 的任务信息查询插件（配置为来自 [Otari98/AtlasQuest](https://github.com/Otari98/AtlasQuest.git) 的子模块）。

---

## 用于管理插件的 Git 命令

### 1. 初始设置（克隆）
如果您是首次克隆此仓库，必须同时初始化并克隆子模块：
```bash
git clone https://github.com/liruqi/AddOns
cd AddOns
git submodule update --init --recursive
```

### 2. 更新子模块
要将所有子模块更新为各自远程仓库的最新提交：
```bash
git submodule update --remote --merge
```
*注意：`--merge` 可确保子模块上的任何本地提交（如果有的话）与传入的更新合并。*

如果您只想更新**特定**的子模块（例如：仅更新 `pfQuest`）：
```bash
git submodule update --remote --merge pfQuest
```

## 贡献

我们欢迎各位的贡献！请随时提交拉取请求（PR）以进行贡献。

如果您想对特定插件进行贡献，请尝试给该特定插件的上游仓库提交补丁，或者自行 fork 一个新仓库。
