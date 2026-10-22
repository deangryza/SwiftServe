$ErrorActionPreference = 'Stop'
$root = 'C:\Users\User\my_first\first\MyFirstApp\firstapp\my_app'
$backupRoot = 'C:\Users\User\Documents\SwiftServe\.codex-theme\before'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$files = @(
  'lib/main.dart', 'lib/auth/login_screen.dart', 'lib/auth/client_register_screen.dart',
  'lib/entry/entry_screen.dart', 'lib/screens/onboarding/onboarding_screen.dart',
  'lib/screens/client/client_search_screen.dart', 'lib/screens/client/post_request_screen.dart',
  'lib/screens/client/client_sections.dart',
  'lib/features/auth/presentation/screens/client_register_screen.dart',
  'lib/features/auth/presentation/screens/client_account_form.dart',
  'lib/features/auth/presentation/screens/worker_account_form.dart',
  'lib/features/auth/presentation/screens/profile_completion_screen.dart',
  'lib/features/client/presentation/screens/client_profile_screen.dart'
)
$map = @{}
foreach ($hex in @('041627','0B1C30','343840','3F4652','161616')) { $map[$hex] = '242424' }
foreach ($hex in @('44474C','555960','596273','667085','697386','7B8190','89919F','9098A8','929AAA','98A2B3','9CA1AB','B0B6C0','8A8A8A','8A6500','BD8500','C58A00','087A52')) { $map[$hex] = '666666' }
foreach ($hex in @('C4C6CD','D0D7E2','DDE2E8','DDE3EA','E0E0E0','E2DED3','E2E5EC','E3D8B8','E4E7EC','E5E7EB','E8E4DA','EAECEF')) { $map[$hex] = 'E5E5E5' }
foreach ($hex in @('DCE9FF','EFF4FF','E1F7EC','FFF4D0','FFF8E5','FFFBF0')) { $map[$hex] = 'FFF3CC' }
foreach ($hex in @('00A86B','10B981','20B978','22B65F','E3A500','E9A400')) { $map[$hex] = '242424' }
$map['0058BE'] = '666666'
foreach ($hex in @('BA1A1A','D92D20')) { $map[$hex] = '242424' }
$dashboard = Join-Path $root 'lib/screens/client/client_home_screen.dart'
$dashboardHash = (Get-FileHash -LiteralPath $dashboard).Hash
foreach ($relative in $files) {
  $path = Join-Path $root $relative
  $before = [IO.File]::ReadAllText($path)
  $after = $before
  foreach ($hex in $map.Keys) { $after = $after.Replace("Color(0xFF$hex)", "Color(0xFF$($map[$hex]))") }
  $after = $after.Replace('Colors.black54', 'const Color(0xFF666666)').Replace('Colors.red', 'const Color(0xFF242424)')
  # Const expressions already inside const widgets must not acquire duplicate const keywords.
  $after = $after.Replace('const const Color', 'const Color')
  if ($relative -eq 'lib/main.dart') {
    $after = $after.Replace("import 'firebase_options.dart';", "import 'firebase_options.dart';`r`nimport 'shared/theme/app_theme.dart';")
    $start = $after.IndexOf('theme: ThemeData(')
    $end = $after.IndexOf('      home: const OnboardingScreen()', $start)
    if ($start -lt 0 -or $end -lt 0) { throw 'Unexpected main theme structure' }
    $after = $after.Substring(0, $start) + "theme: AppTheme.light,`r`n" + $after.Substring($end)
  }
  if ($relative -eq 'lib/features/auth/presentation/screens/client_register_screen.dart') {
    $after = $after.Replace('backgroundColor: const Color(0xFF18181B)', 'backgroundColor: const Color(0xFFFFC72C)')
    $after = $after.Replace('foregroundColor: Colors.white', 'foregroundColor: const Color(0xFF242424)')
    $after = $after.Replace('Color(0xA618181B)', 'Color(0x66FFC72C)')
    $after = $after.Replace('borderRadius: BorderRadius.circular(8)', 'borderRadius: BorderRadius.circular(14)')
    $after = $after.Replace("'assets/registration/arrow.svg',", "'assets/registration/arrow.svg',`r`n                                      colorFilter: const ColorFilter.mode(Color(0xFF242424), BlendMode.srcIn),")
  }
  if ($relative -eq 'lib/screens/onboarding/onboarding_screen.dart') {
    $after = $after.Replace('size: 70,' + "`r`n" + '                                      color: Colors.white', 'size: 70,' + "`r`n" + '                                      color: Color(0xFF242424)')
  }
  if ($relative -eq 'lib/features/client/presentation/screens/client_profile_screen.dart') {
    $after = $after.Replace('backgroundColor: _profileYellow', 'backgroundColor: background')
    $after = [regex]::Replace($after, 'gradient: LinearGradient\(\s*begin: Alignment.topCenter,\s*end: Alignment.bottomCenter,\s*colors: \[_profileYellow, background, background\],\s*stops: const \[0, 0\.34, 1\],\s*\)', 'color: background')
    $after = [regex]::Replace($after, 'boxShadow: const \[\s*BoxShadow\(\s*color: Color\(0x14000000\),\s*blurRadius: 5,\s*offset: Offset\(0, 3\),\s*\),\s*\]', 'border: Border.all(color: const Color(0xFFE5E5E5))')
  }
  if ($after -ne $before) {
    $backup = Join-Path $backupRoot $relative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup)) | Out-Null
    [IO.File]::WriteAllText($backup, $before, $utf8)
    [IO.File]::WriteAllText($path, $after, $utf8)
    Write-Output "Updated $relative"
  }
}
$themeDir = Join-Path $root 'lib/shared/theme'
[IO.Directory]::CreateDirectory($themeDir) | Out-Null
Copy-Item -LiteralPath 'C:\Users\User\Documents\SwiftServe\.codex-theme\app_theme.dart' -Destination (Join-Path $themeDir 'app_theme.dart')
if ((Get-FileHash -LiteralPath $dashboard).Hash -ne $dashboardHash) { throw 'Dashboard changed during operation' }
Write-Output 'Dashboard source unchanged.'
