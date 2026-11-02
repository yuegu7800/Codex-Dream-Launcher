# Wallpaper Engine 本地素材库

安装后双击 `Wallpaper-Library.cmd` 或桌面“Dragon Wallpaper 壁纸素材库”。无需运行 Wallpaper Engine 即可浏览已下载的本地素材。

自动发现 Steam 多个库中的 workshop/content/431960、myprojects 和 defaultprojects；可手动添加目录。支持标题、ID、类型和标签搜索，选中后查看缩略图、媒体大小和兼容说明。

- 16 MiB 以内 MP4：导出并自动加入同一安装的 Dragon Studio 视频素材列表。
- PNG/JPG/JPEG/WebP、GIF、WebM/MOV/M4V、大 MP4：通过本机已安装的 FFmpeg 转换后加入素材库。不自动下载 FFmpeg。
- Scene 如随附恰好一个独立视频，可转换该视频；不保留场景实时效果。纯 PKG 场景仅浏览。
- Web 和 Application 不执行、不转换；未接入 Wallpaper Engine 原生场景渲染。

转换为静音 H.264 MP4，1280×720、24 FPS、最长截取 30 秒，源文件最大 1 GiB、任务超时 120 秒，输出仍限制 16 MiB。图片转为静态视频，短片播放时循环；不声称导出完整原片或实时场景。

导出文件保存在 wallpaper-library/data/exports；管理器副本保存在 skin/library，按 SHA-256 去重并保存原标题。点击“打开正式版主题管理器”后选择素材并手动应用；管理器重新获得焦点会刷新列表。导入不自动切换当前壁纸。

配色预设改变强调色、面板色和背景色，有三个色块预览；切换配色保留独立的“壁纸透出”滑块值。五个预设共用所选媒体，不是五套视频。

扫描和导入只操作本地文件，没有网络服务或监听端口；拒绝 UNC、路径越界、数据流、符号链接和目录联接。元数据最大 1 MiB，缩略图 JPG/PNG 最大 8 MiB。转换仅接受本地媒体白名单、限制 FFmpeg 的输入协议，不运行场景脚本或网页。容器检查不能保证系统解码成功。

## 验证

在仓库根目录执行：

```powershell
powershell.exe -NoProfile -File wallpaper-library/Test-Library.ps1
powershell.exe -NoProfile -File wallpaper-library/Test-Transfer.ps1
powershell.exe -NoProfile -File wallpaper-library/Test-Unicode.ps1
```

分别检查扫描/路径/导出边界、PNG/GIF/WebM 实际转换与管理器入库、Windows PowerShell 5.1 中文名称读取。转换测试需要 FFmpeg；测试数据留在被忽略的 data/，生成的临时素材库条目会移除。不要在运行目录中制作 GitHub 发布包。

## 参考

本模块独立编写，参考以下公开项目的架构及素材发现方法，没有复制或打包四套项目的代码与渲染器：

- [Luna Beautiful Codex](https://github.com/Bella-rab/luna-beautiful-codex)，MIT：素材分类和选择器。
- [Codex Wallpaper Skin](https://github.com/ChenSenhao0104/codex-wallpaper-skin)，Apache-2.0：独立控制器与兼容信息。
- [we-codex-bg](https://github.com/121103qwq/we-codex-bg)，未确认代码许可：只参考多库发现描述，不复制代码。
- [WallpaperEngineMediaLibrary](https://github.com/MindMobius/WallpaperEngineMediaLibrary)，GPL-3.0：参考浏览组织方式，不复制服务器代码。

本模块沿用父项目 MIT。用户壁纸的版权归原作者；本地订阅不代表获得重新分发许可。data/、skin/、运行时和备份不上传 GitHub。
