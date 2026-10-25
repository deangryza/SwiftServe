$ErrorActionPreference = 'Stop'
$root = 'C:\Users\User\my_first\first\MyFirstApp\firstapp\my_app'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$backupRoot = 'C:\Users\User\Documents\SwiftServe\.codex-theme\before'
foreach ($backup in Get-ChildItem -LiteralPath $backupRoot -Recurse -Filter '*.dart') {
  $relative = $backup.FullName.Substring($backupRoot.Length + 1)
  if ($relative -eq 'lib\main.dart') { continue }
  $path = Join-Path $root $relative
  $text = [IO.File]::ReadAllText($path)
  # Keep text legible on yellow buttons and yellow accents on white surfaces.
  $text = [regex]::Replace($text, '(TextStyle\(\s*color: )(?:const )?Color\(0xFFFFC72C\)', '${1}Color(0xFF242424)')
  if ($relative -like '*login_screen.dart' -or $relative -eq 'lib\features\auth\presentation\screens\client_register_screen.dart') {
    $text = [regex]::Replace($text, '(CircularProgressIndicator\(\s*(?:strokeWidth: [\d.]+,\s*)?color: )Colors.white', '${1}Color(0xFF242424)')
  }
  $tokens = @{ '242424' = 'ink'; '666666' = 'muted'; 'FFC72C' = 'yellow'; 'E5E5E5' = 'line'; 'FFF3CC' = 'softYellow' }
  foreach ($hex in $tokens.Keys) {
    $text = $text.Replace("const Color(0xFF$hex)", "AppTheme.$($tokens[$hex])").Replace("Color(0xFF$hex)", "AppTheme.$($tokens[$hex])")
  }
  if ($text.Contains('AppTheme.')) {
    $depth = ($relative.Split('\').Length - 2)
    $import = ('../' * $depth) + 'shared/theme/app_theme.dart'
    $text = $text.Replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';`r`nimport '$import';")
  }
  [IO.File]::WriteAllText($path, $text, $utf8)
}
# These two empty files were only changed by the formatter.
foreach ($relative in @('lib/auth/worker_register_screen.dart', 'lib/screens/onboarding/onboarding_page.dart')) {
  $path = Join-Path $root $relative
  if ([string]::IsNullOrWhiteSpace([IO.File]::ReadAllText($path))) { [IO.File]::WriteAllText($path, '', $utf8) }
}
