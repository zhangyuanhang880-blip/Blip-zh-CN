# Blip 简体中文汉化

为 Windows 版 [Blip](https://blip.net/) 制作的非官方简体中文汉化补丁。

本项目只包含汉化脚本和翻译表，不分发 Blip 原程序、安装包或其他受版权保护的二进制文件。已在 Microsoft Store 版 Blip 1.2.3（x64）上完成实际启动验证。

## 特点

- 汉化主要界面、菜单、按钮、设置、提示和错误信息，共收录 299 条译文；在已测试版本中覆盖 365 处界面字符串。
- 不修改受签名保护的 Microsoft Store 原版安装目录。
- 自动为当前版本创建独立汉化副本，原版和汉化版可以分别启动。
- 按版本备份原始资源，可随时恢复。
- Blip 更新后可重新运行补丁，无须手工拆包。
- 翻译集中在 JSON 文件中，便于维护和校对。

## 使用方法

### 安装汉化

1. 先通过 Microsoft Store 安装并至少启动一次 Blip。
2. 下载本项目的 Release 压缩包并完整解压。
3. 双击 `安装汉化.cmd`。
4. 从桌面或开始菜单启动“Blip（简体中文）”。

脚本会关闭正在运行的 Blip，从 Store 原版创建独立副本，备份相关资源，应用翻译，并创建快捷方式。汉化副本位于：

```text
%LOCALAPPDATA%\Programs\Blip-zh-CN\versions\<版本号>
```

备份位于：

```text
%LOCALAPPDATA%\Programs\Blip-zh-CN\backup\<版本号>
```

### 恢复原版

双击 `恢复原版.cmd`。它会还原汉化副本中的原始资源，并移除“Blip（简体中文）”快捷方式。Microsoft Store 原版不会被修改，始终可以从开始菜单正常启动。

### Blip 更新后重新应用

双击 `更新后重新应用.cmd`。脚本会识别当前 Store 版本，在新的版本目录中重新制作汉化副本。旧版本备份不会被自动删除。

## 命令行使用

```powershell
# 应用汉化并启动
powershell -NoProfile -ExecutionPolicy Bypass -File .\Blip-zh-CN.ps1 -Mode Apply -Launch

# 查看状态
powershell -NoProfile -ExecutionPolicy Bypass -File .\Blip-zh-CN.ps1 -Mode Status

# 恢复汉化副本中的原始资源
powershell -NoProfile -ExecutionPolicy Bypass -File .\Blip-zh-CN.ps1 -Mode Restore
```

## 工作原理

Blip 的 Windows 客户端使用 Kotlin/Java Compose Desktop，而不是 Electron。本补丁会复制 Store 应用文件，并在副本内处理 JAR 中的 Java 字符串常量。

补丁不会就地改写共享的 UTF-8 常量。它会为译文追加新的常量，只让对应的 `CONSTANT_String` 项指向译文，因此不会误改字段名、方法名或枚举成员。这也避免了旧式替换可能触发的 `NoSuchFieldError` 启动错误。

## 已知限制

- 当前正式测试版本为 Microsoft Store 版 Blip 1.2.3 x64；后续版本会尝试自动识别，但界面变化可能导致部分文本漏译。
- 资源管理器右键菜单来自 Store 原版的原生扩展，菜单品牌名仍可能显示为 `Blip`。
- 如果原版与汉化版同时运行，Blip 的单实例机制可能把操作交给已经运行的实例。
- Blip 更新、修复或重新安装后，需要重新应用汉化。

## 维护翻译

所有翻译位于 `translations.zh-CN.json`。键是原始英文，值是简体中文。提交修改时请保持 JSON 有效，不要添加 Blip 的原始二进制文件。

## 安全与隐私

脚本在本机运行，不上传文件，不收集数据，也不需要管理员权限。请从本项目的 GitHub Releases 下载，并在运行前自行检查脚本内容。

## 免责声明

这是社区维护的非官方项目，与 Blip、Blip Studio Inc. 或 Microsoft 无隶属、授权或合作关系。Blip 名称及相关商标归其各自权利人所有。使用本项目产生的风险由使用者自行承担。

## 许可证

本项目自行编写的脚本、说明和翻译表以 [MIT License](LICENSE) 发布。该许可证不适用于 Blip 软件本身。
