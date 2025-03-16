
一个支持多个软件的版本管理工具，支持手动添加本地路径

A version management tool that supports multiple software and supports manual addition of local paths

## Usage

xm -h

```
XM 多版本管理器 v1.0

使用方式:
  xm [选项] [模块名称] [命令]
  -h, --help                   显示帮助信息
  -p                           显示所有模块状态
  -x                           显示当前 PATH 环境变量
  --unset-all                  清理所有模块环境变量
  [module]                     显示可用版本列表
  [module] install [version]   安装指定版本
  [module] use [version]       使用指定版本
  [module] unset               取消使用当前版本
  [module] remove [version]    移除已安装版本
```

例如:

xm -p

```
+------------------------+-------------------+
| name                   | status            |
+------------------------+-------------------+
| jdk                    | @ openjdk-v14.0.1 |
+------------------------+-------------------+
| node                   | * v22.5.0         |
+------------------------+-------------------+
| pandoc                 | * 3.6.3           |
+------------------------+-------------------+
| python                 | * 3.8 (local)     |
+------------------------+-------------------+
| arm-none-eabi-gcc      | # 10.3            |
+------------------------+-------------------+
| cmake                  | # 3.30            |
+------------------------+-------------------+
| aarch64-none-linux-gnu | # 13.3            |
+------------------------+-------------------+
| ffmpeg                 | # full            |
+------------------------+-------------------+
| flutter                | * 3.24.0 (local)  |
+------------------------+-------------------+
| iverilog               | # 12.0            |
+------------------------+-------------------+
| qemu                   | # 7.14.9          |
+------------------------+-------------------+
| upx                    | # 4.2.0           |
+------------------------+-------------------+
```

xm [modeule] will list all available versions

```
+---------------------+---------------------+---------------------+
|              * : used,  @ : installed,  # : local               |
+---------------------+---------------------+---------------------+
| @ openjdk-v14.0.1   | * openjdk-v22.0.2   |                     |
+---------------------+---------------------+---------------------+
```

xm_config.ini is the config file

example of config file:

```ini
[jdk]
openjdk-v14.0.1 = https://download.java.net/java/GA/jdk14.0.1/664493ef4a6946b186ff29eb326336a2/7/GPL/openjdk-14.0.1_windows-x64_bin.zip
openjdk-v22.0.2 = https://download.java.net/java/GA/jdk22.0.2/c9ecb94cd31b495da20a27d4581645e8/9/GPL/openjdk-22.0.2_windows-x64_bin.zip

[node]
v22.5.0 = https://nodejs.org/dist/v22.5.0/node-v22.5.0-win-x64.zip

[pandoc]
3.6.3 = https://gitee.com/wjundong/packages/releases/download/pandoc_v3.6.3/pandoc-3.6.3-windows-x86_64.zip
3.6.2 = https://github.com/jgm/pandoc/releases/download/3.6.2/pandoc-3.6.2-windows-x86_64.zip

[python]
3.8 = "C:\ProgramFiles\Library\python\python38;C:\ProgramFiles\Library\python\python38\Scripts"
3.9 = "C:\ProgramFiles\Library\python\python39;C:\ProgramFiles\Library\python\python39\Scripts"

[arm-none-eabi-gcc]
10.3 = C:\ProgramFiles\Library\arm-none-eabi-gcc\bin

[cmake]
3.30 = C:\ProgramFiles\Library\cmake\bin

[aarch64-none-linux-gnu]
13.3 = C:\ProgramFiles\Library\aarch64-none-linux-gnu\bin

[ffmpeg]
full = C:\ProgramFiles\Library\ffmpeg\bin

[flutter]
3.16.4 = C:\ProgramFiles\Library\flutter\flutter_3.16.4\bin
3.24.0 = C:\ProgramFiles\Library\flutter\flutter_3.24.0\bin

[iverilog]
12.0 = C:\ProgramFiles\Library\iverilog\bin

[qemu]
7.14.9 = C:\ProgramFiles\Library\qemu

[upx]
4.2.0 = C:\ProgramFiles\Library\upx
```
