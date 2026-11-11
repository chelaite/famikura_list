# 购物清单（第一阶段：截图识别）

1. 在 GitHub 新建仓库，把本目录所有文件（包含 .github 文件夹）上传到 main 分支。
2. 打开仓库 Actions → Build APK，等待绿勾（首次约 8~12 分钟）。
3. 点进这次运行，底部 Artifacts 下载 famikura-list-apk，解压得到 app-release.apk，传到手机安装。
之后每次推送代码都会自动重新打包；也可在 Actions 页点 Run workflow 手动触发。
