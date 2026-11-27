@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=Get-Content -LiteralPath '%~f0' -Raw -Encoding UTF8; $m='#'+'PSSTART'; $i=$c.IndexOf($m); iex $c.Substring($i+$m.Length)"
echo.
echo ============================================
echo  已结束, 按任意键关闭此窗口...
pause >nul
exit /b
#PSSTART
<#
  Minecraft2Shell 自动修复脚本 v3 —— 扫描后交互确认(y/n)
  ------------------------------------------------------------------
  流程: 扫描所有版本并分类 -> 列出结果 -> 若有可自动修复项, 提示 y/n -> 选 y 才修复。
  分类(按核心版本):
    - 原版 26.x                : 用官方权威JSON整份覆盖 + 下载校验补丁库
    - 合并式整合包(自带freetype,核心26.x): 外科式替换freetype条目 + 下载校验
    - inheritsFrom 26.x        : 由父版本26.x修复覆盖(父版本在列表里会被一起修), 本体不改
    - 核心 1.20.5~1.21.11      : 官方无补丁, 仅提示缓解
    - 无freetype               : 不受影响
  安全: 改前备份 *.bak-mc2shell-<时间>; 下载逐个 SHA1 校验。
  用法:
    交互:  powershell -ExecutionPolicy Bypass -File mc2shell-fix.ps1
    批量(不询问直接修): ... mc2shell-fix.ps1 -Yes
    纯预览(只看不改):   ... mc2shell-fix.ps1 -DryRun
    指定目录: ... mc2shell-fix.ps1 -McPath "D:\xxx\.minecraft"
#>
$McPath=$null; $Yes=$false; $DryRun=$false
$ErrorActionPreference='Stop'
$MANIFEST='https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
$LIBBASE ='https://libraries.minecraft.net/'

function Find-McRoots {
  if ($McPath) { return @($McPath) }
  $cands=New-Object System.Collections.Generic.List[string]
  foreach($d in @("$env:APPDATA\.minecraft","$env:USERPROFILE\.minecraft")){ if(Test-Path $d){ $cands.Add($d) } }
  # 全盘扫描: 所有固定磁盘上名为 .minecraft 的目录(跳过 Windows 目录以加速)
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
function Is26($b){ $b -match '^26\.' }
# freetype 条目按"分类器"归并(base / natives-windows ...), 与版本号无关, 用于跨版本匹配
function FtKey($name){ $p=$name -split ':'; if($p.Count -ge 4){$p[3]}else{'base'} }
function Resolve-Version($root,$id,$depth=0){
  $vj=Join-Path "$root\versions\$id" "$id.json"
  if (-not (Test-Path $vj) -or $depth -gt 5) { return @{own=$null;eff=$null;base=$id;inh=$null} }
  $raw=Get-Content $vj -Raw
  $own=FtCoordRaw $raw; $inh=RxVal $raw 'inheritsFrom'
  $base= if($inh){$inh}else{ $cv=RxVal $raw 'clientVersion'; $jr=RxVal $raw 'jar'; $fml=([regex]::Match($raw,'--fml\.mcVersion"\s*,\s*"([^"]+)"')).Groups[1].Value; if($cv){$cv}elseif($jr){$jr}elseif($fml){$fml}else{$id} }
  $eff=$own; if (-not $eff -and $inh){ $eff=(Resolve-Version $root $inh ($depth+1)).eff }
  return @{own=$own;eff=$eff;base=$base;inh=$inh}
}

Write-Host "获取 Mojang 版本清单..." -ForegroundColor DarkGray
$manifest=Invoke-RestMethod $MANIFEST
$byId=@{}; $manifest.versions | ForEach-Object { $byId[$_.id]=$_.url }
$offCache=@{}
function Get-OfficialJson($id){ if($offCache.ContainsKey($id)){return $offCache[$id]}; $r= if($byId.ContainsKey($id)){Invoke-RestMethod $byId[$id]}else{$null}; $offCache[$id]=$r; $r }
function Download-FtLibs($root,$offJson){
  $arch= if($env:PROCESSOR_ARCHITECTURE -eq 'ARM64'){'natives-windows-arm64'}else{'natives-windows'}
  $need=$offJson.libraries | Where-Object { $_.name -match 'lwjgl-freetype' -and ($_.name -notmatch 'natives' -or $_.name -match [regex]::Escape($arch)) }
  $ok=$true
  foreach($e in $need){ $a=$e.downloads.artifact; $dst=Join-Path "$root\libraries" ($a.path -replace '/','\')
    New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
    Invoke-WebRequest ($LIBBASE+$a.path) -OutFile $dst
    $h=[BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash([IO.File]::ReadAllBytes($dst))).Replace('-','').ToLower()
    if ($h -ne $a.sha1.ToLower()){ Write-Host "    ! 哈希不匹配: $($a.path)" -ForegroundColor Red; $ok=$false } }
  $ok
}

# ===== 第一步: 扫描分类 =====
$roots=Find-McRoots
if (-not $roots){ Write-Host "未找到 .minecraft 目录。可用 -McPath 指定。" -ForegroundColor Yellow; exit }
$actions=@(); $mit=0; $skip=0; $inhc=0
Write-Host "`n===== 扫描结果 =====" -ForegroundColor Cyan
foreach($root in $roots){
  Write-Host "`n== $root ==" -ForegroundColor Cyan
  foreach($vdir in (Get-ChildItem "$root\versions" -Directory)){
    $id=$vdir.Name; $vj=Join-Path $vdir.FullName "$id.json"; $r=Resolve-Version $root $id
    if (-not $r.eff){ continue }
    if ($r.eff -match 'mojang-2\.15\.0'){ Write-Host "  [已修复] $id" -ForegroundColor Green; $skip++; continue }
    if (-not (Is26 $r.base)){ Write-Host "  [需缓解] $id  核心 $($r.base) 官方无补丁 -> 关资源包/缓解模组" -ForegroundColor Red; $mit++; continue }
    if (-not $r.own -and $r.inh){ Write-Host "  [继承]   $id  继承自 $($r.inh), 由父版本修复覆盖" -ForegroundColor DarkCyan; $inhc++; continue }
    $off=Get-OfficialJson $r.base
    if (-not $off){ Write-Host "  [待查]   $id  核心 $($r.base) 不在官方清单, 请手动处理" -ForegroundColor Magenta; continue }
    $kind= if($id -eq $r.base){'原版'}else{'整合'}
    Write-Host "  [可修复·$kind] $id  $($r.own) -> 补丁版" -ForegroundColor Yellow
    $actions += @{ id=$id; vj=$vj; root=$root; base=$r.base; off=$off; kind=$kind; byIdUrl=$byId[$id] }
  }
}
Write-Host "`n----------------------------------------" -ForegroundColor DarkGray
Write-Host ("可自动修复 {0} 个; 已是补丁 {1}; 需缓解 {2}; 继承父版本 {3}" -f $actions.Count,$skip,$mit,$inhc)
if ($mit -gt 0){ Write-Host "[需缓解版本] 选项->'服务器资源包'设为'已禁用', 不加载来路不明资源包; 模组端装 minecraft2shell-fix。" -ForegroundColor Yellow }

# ===== 第二步: 确认 =====
if ($actions.Count -eq 0){ Write-Host "`n没有可自动修复的版本, 结束。" -ForegroundColor Green; exit }
if ($DryRun){ Write-Host "`n(纯预览模式, 不修复。去掉 -DryRun 可进入修复确认。)" -ForegroundColor Yellow; exit }
if (-not $Yes){
  $ans = Read-Host "`n是否现在自动修复以上 $($actions.Count) 个版本? (y/n)"
  if ($ans -notmatch '^(y|Y)') { Write-Host "已取消, 未做任何修改。" -ForegroundColor Yellow; exit }
}

# ===== 第三步: 执行修复 =====
Write-Host "`n===== 开始修复 =====" -ForegroundColor Cyan
foreach($a in $actions){
  Write-Host "  修复 $($a.id) ..." -ForegroundColor White
  $bak="$($a.vj).bak-mc2shell-$(Get-Date -Format yyyyMMddHHmmss)"; Copy-Item $a.vj $bak -Force
  if ($a.kind -eq '原版'){
    Invoke-WebRequest $a.byIdUrl -OutFile $a.vj
  } else {
    $local= try { Get-Content $a.vj -Raw | ConvertFrom-Json } catch { $null }
    if (-not $local){ Write-Host "    -> 无法解析该整合JSON, 跳过(请手动替换freetype条目)" -ForegroundColor Red; continue }
    $offFt=@{}; foreach($e in ($a.off.libraries | Where-Object {$_.name -match 'lwjgl-freetype'})){ $offFt[(FtKey $e.name)]=$e }
    $local.libraries=@(foreach($lib in $local.libraries){ if($lib.name -match 'lwjgl-freetype'){ $k=FtKey $lib.name; if($offFt[$k]){$offFt[$k]}else{$lib} } else {$lib} })
    ($local | ConvertTo-Json -Depth 100) | Set-Content $a.vj -Encoding UTF8
  }
  if (Download-FtLibs $a.root $a.off){ Write-Host "    -> 已修复并校验通过 (备份 $(Split-Path $bak -Leaf))" -ForegroundColor Green }
  else { Write-Host "    -> 下载校验失败, 已保留备份 $(Split-Path $bak -Leaf), 请手动检查" -ForegroundColor Red }
}
Write-Host "`n完成。提示: 第三方启动器修复后不要再点'版本检查/文件校验', 以免覆盖。" -ForegroundColor Green
