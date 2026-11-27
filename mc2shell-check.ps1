<#
  Minecraft2Shell 自检脚本 (只读, 不修改任何文件) v2 —— 按核心版本判定, 支持整合包
  判定: 解析每个版本"有效的 lwjgl-freetype 坐标"(自身或经 inheritsFrom 继承自父版本):
        无坐标            -> 不受影响 (如 1.20.4 及更早)
        坐标含 2.15.0     -> 已修复
        坐标未打补丁 + 核心 26.x -> 可修复(官方有补丁库)
        坐标未打补丁 + 其它       -> 易受攻击(官方暂无补丁, 需缓解)
  用法: powershell -ExecutionPolicy Bypass -File mc2shell-check.ps1 [-McPath "...\.minecraft"]
#>
param([string]$McPath)
$ErrorActionPreference = 'SilentlyContinue'

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
# 容错取字段(正则, 不依赖 ConvertFrom-Json, 整合包也能读)
function RxVal($raw,$key){ ([regex]::Match($raw, '"'+$key+'"\s*:\s*"([^"]+)"')).Groups[1].Value }
function FtCoordRaw($raw){ ([regex]::Match($raw, '"name"\s*:\s*"(org\.lwjgl:lwjgl-freetype:(?:(?!natives)[^"])+)"')).Groups[1].Value }

# 解析某版本的"有效 freetype 坐标"与"核心版本", 跟随 inheritsFrom 链(最多5层)
function Resolve-Version($root,$id,$depth=0){
  $vj = Join-Path "$root\versions\$id" "$id.json"
  if (-not (Test-Path $vj) -or $depth -gt 5) { return @{ coord=$null; base=$id } }
  $raw = Get-Content $vj -Raw
  $coord = FtCoordRaw $raw
  $inh   = RxVal $raw 'inheritsFrom'
  $base  = if ($inh) { $inh } else {
             $cv = RxVal $raw 'clientVersion'; $jr = RxVal $raw 'jar'
             $fml= ([regex]::Match($raw,'--fml\.mcVersion"\s*,\s*"([^"]+)"')).Groups[1].Value
             if ($cv){$cv}elseif($jr){$jr}elseif($fml){$fml}else{$id}
           }
  if (-not $coord -and $inh) { $p = Resolve-Version $root $inh ($depth+1); return @{ coord=$p.coord; base=$base } }
  return @{ coord=$coord; base=$base }
}
function Is26($base){ $base -match '^26\.' }

$roots = Find-McRoots
if (-not $roots) { Write-Host "未找到 .minecraft 目录。可用 -McPath 指定。" -ForegroundColor Yellow; exit }
$vuln=0; $total=0
foreach ($root in $roots) {
  Write-Host "`n== $root ==" -ForegroundColor Cyan
  foreach ($vdir in (Get-ChildItem "$root\versions" -Directory)) {
    $r = Resolve-Version $root $vdir.Name
    if (-not $r.coord) { Write-Host ("  [无影响 ] {0,-28} 核心 {1}, 不含 FreeType" -f $vdir.Name,$r.base) -ForegroundColor Gray; continue }
    $total++
    if ($r.coord -match 'mojang-2\.15\.0') {
      Write-Host ("  [已修复 ] {0,-28} 核心 {1}  ({2})" -f $vdir.Name,$r.base,$r.coord) -ForegroundColor Green
    } elseif (Is26 $r.base) {
      $vuln++; Write-Host ("  [可修复 ] {0,-28} 核心 {1}  未打补丁({2}) — 官方有补丁, 可自动修" -f $vdir.Name,$r.base,$r.coord) -ForegroundColor Yellow
    } else {
      $vuln++; Write-Host ("  [易受攻击] {0,-28} 核心 {1}  未打补丁({2}) — 官方暂无补丁, 需缓解" -f $vdir.Name,$r.base,$r.coord) -ForegroundColor Red
    }
  }
}
Write-Host "`n----------------------------------------" -ForegroundColor DarkGray
if ($vuln -gt 0) {
  Write-Host "结果: $total 个使用 FreeType 的版本中, $vuln 个需要处理。" -ForegroundColor Red
  Write-Host "  [可修复] 核心 26.x: 官方启动器完整启动一次, 或用 mc2shell-fix.ps1 -Apply, 或删版重装。"
  Write-Host "  [易受攻击] 核心 1.20.5~1.21.11: 官方无补丁 -> 将'服务器资源包'设为'已禁用', 不加载来路不明资源包; 模组端可装 minecraft2shell-fix。"
  Write-Host "  修复前不要接受任何服务器推送的资源包。"
} else { Write-Host "结果: 未发现需要处理的版本。" -ForegroundColor Green }
Write-Host "注: 本脚本只读取文件, 不做任何修改。"
