<#
  Minecraft2Shell 自检脚本 (只读, 不修改任何文件, 离线) v3 —— 按 freetype 库版本判定
  判定依据: 版本实际引用的 lwjgl-freetype 库版本(自身或经 inheritsFrom 继承):
    无 freetype               -> 不受影响
    已是 *-mojang-2.15.0       -> 已修复
    3.4.3 / 3.4.1 (有官方补丁)  -> 可修复
    其它(3.3.x 等, 无官方补丁)  -> 易受攻击, 需缓解
  整合包同样按其引用的 freetype 版本判定, 与名字无关。
  用法: powershell -ExecutionPolicy Bypass -File mc2shell-check.ps1 [-McPath "...\.minecraft"]
#>
param([string]$McPath)
$ErrorActionPreference='SilentlyContinue'
# 已知有官方补丁(-mojang-2.15.0)的 lwjgl-freetype 版本
$PATCHABLE=@('3.4.3','3.4.1')

function Find-McRoots {
  if ($McPath) { return @($McPath) }
  $cands=New-Object System.Collections.Generic.List[string]
  foreach($d in @("$env:APPDATA\.minecraft","$env:USERPROFILE\.minecraft")){ if(Test-Path $d){ $cands.Add($d) } }
  $drives=Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | Select-Object -Expand DeviceID
  if(-not $drives){ $drives=(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Root -match '^[A-Za-z]:' }).Root -replace '\\$','' }
  foreach($dv in $drives){
    $root="$dv\"
    Write-Host "  全盘扫描 $root (可能需要一会儿)..." -ForegroundColor DarkGray
    Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -ne $env:SystemRoot } |
      ForEach-Object {
        try { Get-ChildItem -LiteralPath $_.FullName -Recurse -Directory -Filter '.minecraft' -Force -ErrorAction SilentlyContinue | ForEach-Object { $cands.Add($_.FullName) } } catch {}
      }
    if(Test-Path "$root.minecraft"){ $cands.Add("$root.minecraft") }
  }
  $cands | Where-Object { Test-Path (Join-Path $_ 'versions') } | Select-Object -Unique
}
function RxVal($raw,$key){ ([regex]::Match($raw,'"'+$key+'"\s*:\s*"([^"]+)"')).Groups[1].Value }
function FtCoordRaw($raw){ ([regex]::Match($raw,'"name"\s*:\s*"(org\.lwjgl:lwjgl-freetype:(?:(?!natives)[^"])+)"')).Groups[1].Value }
function PlainVer($coord){ ($coord -split ':')[2] -replace '-mojang.*$','' }
function Resolve-Eff($root,$id,$depth=0){
  $vj=Join-Path "$root\versions\$id" "$id.json"
  if (-not (Test-Path $vj) -or $depth -gt 5) { return @{own=$null;eff=$null;inh=$null} }
  $raw=Get-Content $vj -Raw
  $own=FtCoordRaw $raw; $inh=RxVal $raw 'inheritsFrom'
  $eff=$own; if (-not $eff -and $inh){ $eff=(Resolve-Eff $root $inh ($depth+1)).eff }
  return @{own=$own;eff=$eff;inh=$inh}
}

$roots=Find-McRoots
if (-not $roots){ Write-Host "未找到 .minecraft 目录。可用 -McPath 指定。" -ForegroundColor Yellow; exit }
$vuln=0; $total=0
foreach($root in $roots){
  Write-Host "`n== $root ==" -ForegroundColor Cyan
  foreach($vdir in (Get-ChildItem "$root\versions" -Directory)){
    $r=Resolve-Eff $root $vdir.Name
    if (-not $r.eff){ Write-Host ("  [无影响 ] {0,-28} 不含 FreeType" -f $vdir.Name) -ForegroundColor Gray; continue }
    $total++
    if ($r.eff -match 'mojang-2\.15\.0'){ Write-Host ("  [已修复 ] {0,-28} ({1})" -f $vdir.Name,$r.eff) -ForegroundColor Green; continue }
    $plain=PlainVer $r.eff
    if ($PATCHABLE -contains $plain){
      $vuln++; Write-Host ("  [可修复 ] {0,-28} freetype {1} — 官方有补丁, 可自动修" -f $vdir.Name,$plain) -ForegroundColor Yellow
    } else {
      $vuln++; Write-Host ("  [易受攻击] {0,-28} freetype {1} — 官方暂无补丁, 需缓解" -f $vdir.Name,$plain) -ForegroundColor Red
    }
  }
}
Write-Host "`n----------------------------------------" -ForegroundColor DarkGray
if ($vuln -gt 0){
  Write-Host "结果: $total 个使用 FreeType 的版本中, $vuln 个需要处理。" -ForegroundColor Red
  Write-Host "  [可修复] 用官方启动器完整启动一次, 或运行 mc2shell-fix.ps1 / mc2shell一键修复.bat。"
  Write-Host "  [易受攻击] 官方无补丁 -> 将'服务器资源包'设为'已禁用', 不加载来路不明资源包; 模组端装 minecraft2shell-fix。"
  Write-Host "  修复前不要接受任何服务器推送的资源包。"
} else { Write-Host "结果: 未发现需要处理的版本。" -ForegroundColor Green }
Write-Host "注: 本脚本只读取文件, 不做任何修改。"
