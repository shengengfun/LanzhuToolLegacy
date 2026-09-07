# LanzhuTool 工具更新指南

## 工具当前状态

| 工具 | 版本 | 修改日期 | 状态 |
|------|------|---------|------|
| FFmpeg | 8.1-full_build | 2026-03-17 | ✅ 最新 |
| MP4Box | 0.5.1-DEV-r4929 | 2016-10-23 | ❌ **10年过时** |
| mkvmerge | 9.5.0 | 2016-10-23 | ❌ **10年过时** |
| NeroAAC | (unknown) | 2016-10-23 | ❌ **10年过时** |

## 推荐更新

### 1. MP4Box (GPAC)
**下载地址**:
- 官网: https://gpac.wp.imt.fr/
- GitHub 最新版: https://github.com/gpac/gpac/releases
- 推荐版本: v2.5 或更新

**更新步骤**:
```
1. 下载 gpac-xxx-wtk-win64.zip (64位) 或适合的版本
2. 解压后找到 MP4Box.exe
3. 替换 tools/video/gpac/MP4Box.exe
```

### 2. MKVToolNix (mkvmerge, mkvextract, mkvinfo)
**下载地址**:
- 官网: https://www.bunkus.org/videotools/mkvtoolnix/
- 推荐版本: 82.0 或更新

**更新步骤**:
```
1. 下载 mkvtoolnix-64-bit-xxx.7z 或 .exe 安装版
2. 提取 mkvmerge.exe, mkvextract.exe, mkvinfo.exe, mmg.exe 等
3. 替换 tools/video/mkvtoolnix/ 中对应文件
```

### 3. NeroAAC (可选)
**下载地址**:
- 官网: https://www.nero.com/enu/Nero-AAC-Codec/
- 推荐版本: 1.3.3 或更新

**更新步骤**:
```
1. 下载 NeroAACCodec-1.3.3.7z 或最新版
2. 提取 neroAacEnc.exe
3. 替换 tools/audio/encoders/neroAacEnc.exe
```

## 手动更新方法

如果自动下载失败，可以手动：

1. 访问上述网址
2. 下载对应的工具
3. 按分类复制到对应目录：
   - 视频：`tools/video/...`
   - 音频编码器：`tools/audio/encoders/...`
4. 覆盖原有文件

## 验证更新

更新后在命令行验证：
```powershell
d:\Project\lanzhutool\tools\video\gpac\MP4Box.exe -version
d:\Project\lanzhutool\tools\video\mkvtoolnix\mkvmerge.exe --version
d:\Project\lanzhutool\tools\audio\encoders\neroAacEnc.exe -help
```

## 注意事项

- ✅ FFmpeg 已是最新版本，无需更新
- ⚠️ 某些旧视频编码可能需要保留旧版工具以兼容
- 💾 更新前建议备份原文件到其他位置
- 🔍 更新后建议用少量测试文件验证功能

## 新增维护能力（2026-05）

### 1) 更新脚本增强
- 脚本已支持：`-ToolsPath`、`-RetryCount`、`-TimeoutSec`
- 已内置：下载重试、超时、可选 SHA256 校验、临时文件稳健清理

示例：
```powershell
.\update_tools.ps1 -ToolsPath .\tools -RetryCount 3 -TimeoutSec 120
```

### 2) RESX 资源审计
新增脚本：`audit_resx_resources.ps1`

功能：
- 统计 `.resx` 中二进制资源（Icon/Bitmap/base64）
- 检测重复二进制资源（基于 SHA256）

示例：
```powershell
.\audit_resx_resources.ps1
.\audit_resx_resources.ps1 -RootPath .\mp4box
```

### 3) 解决方案构建建议
- 优先使用 .NET Framework MSBuild（旧式项目 + COM 引用）
- 已补齐 `Debug|x86` / `Release|x86` 解决方案配置映射

示例：
```powershell
& "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe" .\mp4box.sln /t:Build /p:Configuration=Debug /p:Platform="x86"
```

### 4) tools 目录整理
- 新增：`tools/organize_tools.ps1`（安全整理）
- 新增：`tools/TOOLS_MANIFEST.md`（核心/可选工具清单）

示例：
```powershell
cd .\tools
.\organize_tools.ps1          # 预览(DRY-RUN)
.\organize_tools.ps1 -Apply   # 应用整理
```

脚本会：
- 校验目录结构与核心工具
- 清理 tools 根目录临时文件（`.bat` / `.tmp` / `.log` 等）
- 生成/更新 `toolchain_ver.txt`

### 5) 编译后自动复制 tools 到输出目录
- 已在 `mp4box/Res/PostBuildEvent.bat` 中增加复制逻辑
- 每次输出更新时，会把整个 `tools` 目录复制到 `mp4box/bin/Debug/tools`（或对应配置输出目录）

## 更新日期

- 文档创建: 2026-05-04
- 工具检查日期: 2026-05-04
- 建议更新: MP4Box, MKVToolNix, NeroAAC
