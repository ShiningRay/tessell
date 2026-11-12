# M0-WP1 本机基线记录

## 1) 采集时间与仓库 HEAD

- 采集时间（本地时间 + 时区）：`2026-11-12 16:16:20 +08:00`
- 命令：`Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"`
- 输出：
```text
2026-11-12 16:16:20 +08:00
```

- repo HEAD hash（`git rev-parse HEAD`）：`981e7a9f0d401170472eb1e52d90b8338dc4d577`
- 命令：`git rev-parse HEAD`
- 输出：
```text
981e7a9f0d401170472eb1e52d90b8338dc4d577
```

## 2) `crystal --version` 完整输出

- 命令：`crystal --version 2>&1; "EXITCODE:$LASTEXITCODE"`
- 输出：
```text
Crystal 1.22.1 [23828b0a40] (2026-10-23)

LLVM: 23.1.3
Default target: x86_64-w64-windows-gnu
EXITCODE:0
```

## 3) `crystal spec` 完整输出与 `$LASTEXITCODE`

- 工作目录：仓库根目录 `C:\Users\ShiningRay\projects\ShiningRay\tessell`
- 命令：`crystal spec 2>&1; "EXITCODE:$LASTEXITCODE"`
- 输出：
```text
......

Finished in 222 microseconds
6 examples, 0 failures, 0 errors, 0 pending
EXITCODE:0
```

## 4) 运行环境

- `[System.Environment]::OSVersion.VersionString`：`Microsoft Windows NT 10.0.26300.0`
- `$env:PROCESSOR_ARCHITECTURE`：`AMD64`
- 命令：`[System.Environment]::OSVersion.VersionString; $env:PROCESSOR_ARCHITECTURE`
- 输出：
```text
Microsoft Windows NT 10.0.26300.0
AMD64
```

- Crystal 安装路径（`Get-Command crystal | Format-List *`）：
- 命令：`Get-Command crystal | Format-List *`
- 输出：
```text


HelpUri            : 
FileVersionInfo    : File:             C:\msys64\ucrt64\bin\crystal.exe
                     InternalName:     
                     OriginalFilename: 
                     FileVersion:      
                     FileDescription:  
                     Product:          
                     ProductVersion:   
                     Debug:            False
                     Patched:          False
                     PreRelease:       False
                     PrivateBuild:     False
                     SpecialBuild:     False
                     Language:         
                     
Path               : C:\msys64\ucrt64\bin\crystal.exe
Extension          : .exe
Definition         : C:\msys64\ucrt64\bin\crystal.exe
Source             : C:\msys64\ucrt64\bin\crystal.exe
Version            : 0.0.0.0
Visibility         : Public
OutputType         : {System.String}
Name               : crystal.exe
CommandType        : Application
ModuleName         : 
Module             : 
RemotingCapability : PowerShell
Parameters         : 
ParameterSets      : 


```

## 5) 结论表

| 检查项 | 状态 | 依据命令 | 结果摘要 |
| --- | --- | --- | --- |
| 本机 Crystal 版本/目标信息 | 通过 | `crystal --version` | Crystal 1.22.1 [23828b0a40] (2026-10-23), LLVM 23.1.3, Default target x86_64-w64-windows-gnu, EXITCODE:0 |
| 仓库基线测试 `crystal spec` | 通过 | `crystal spec` | 6 examples, 0 failures, 0 errors, 0 pending, EXITCODE:0 |
| 运行环境信息采集 | 通过 | `[System.Environment]::OSVersion.VersionString; $env:PROCESSOR_ARCHITECTURE; Get-Command crystal` | OS: Microsoft Windows NT 10.0.26300.0, Arch: AMD64, Crystal: C:\msys64\ucrt64\bin\crystal.exe |

- M0-WP1 总体状态：**通过**
- 未执行项：无（`[未验证]` 项无）
