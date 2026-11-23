#!/bin/bash
# [custom] Installs JetBrainsMono Nerd Font, per-user, no admin/sudo needed
# anywhere. Four cases, in order:
#   1. macOS            -- Homebrew cask (already idempotent on its own).
#   2. WSL               -- installs into the WINDOWS host's per-user font
#                            dir + registry via PowerShell, reached through
#                            /mnt/c. WSL itself has no display of its own --
#                            whatever terminal app runs on Windows is what
#                            actually renders glyphs.
#   3. Linux with a local GUI display (not WSL) -- installs into this
#                            machine's own ~/.local/share/fonts, since this
#                            machine IS what renders its own terminal.
#   4. Anything else (e.g. a headless Linux VM reached via SSH/WezTerm from
#                            a different machine) -- nothing to do here;
#                            whichever machine actually renders the terminal
#                            needs the font, and that's covered by one of the
#                            cases above running there instead.
# Best-effort throughout: any failure prints the manual install instructions
# and exits 0 rather than breaking the rest of `chezmoi apply`.
set -uo pipefail

NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
MANUAL_INSTRUCTIONS="Manual install: $NERD_FONT_URL -> unzip -> install each .ttf"

if [[ "$(uname -s)" == "Darwin" ]]; then
  if command -v brew >/dev/null 2>&1; then
    echo "==> Installing JetBrainsMono Nerd Font via Homebrew..."
    brew install --cask font-jetbrains-mono-nerd-font || echo "Homebrew cask install failed. $MANUAL_INSTRUCTIONS"
  else
    echo "Homebrew not found. $MANUAL_INSTRUCTIONS"
  fi
  exit 0
fi

if [ -d /mnt/c ] && command -v powershell.exe >/dev/null 2>&1; then
  echo "==> WSL detected -- installing JetBrainsMono Nerd Font on the Windows host..."
  if ! powershell.exe -NoProfile -NonInteractive -Command "
\$ErrorActionPreference = 'Stop'
try {
  \$regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
  \$fontsDir = \"\$env:LOCALAPPDATA\Microsoft\Windows\Fonts\"

  # Win32 API for registering a font with the CURRENT session and notifying
  # already-running apps -- copying the file and writing the registry key
  # alone only persists the font for the NEXT login; nothing currently
  # running (including the Fonts Settings page and a freshly-opened
  # WezTerm) picks it up without this. Confirmed missing: Settings > Fonts
  # showed 'no fonts found' even with correct files + registry entries
  # already in place from an earlier run.
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public class FontInstaller {
    [DllImport(\"gdi32.dll\")]
    public static extern int AddFontResource(string lpFileName);
    [DllImport(\"user32.dll\", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
'@

  # No internal "already done" check -- chezmoi's own run_once_ semantics
  # already ensure this whole script only executes once per machine per
  # content-hash, so an internal check here was redundant AND kept missing
  # cases: a check scoped to one font family (NFM) meant OTHER variants
  # (plain NF, which wezterm.lua may point to on a different machine or
  # after a preference change) never got registered or notified at all.
  # Every step below is idempotent (-Force on copies/registry writes, a
  # per-file try/catch for locked files) so a full pass is always safe.
  New-Item -ItemType Directory -Force -Path \$fontsDir | Out-Null

  \$zip = \"\$env:TEMP\JetBrainsMono.zip\"
  Invoke-WebRequest -Uri '$NERD_FONT_URL' -OutFile \$zip
  \$extract = \"\$env:TEMP\JetBrainsMonoNerdFont\"
  Expand-Archive -Path \$zip -DestinationPath \$extract -Force

  Add-Type -AssemblyName System.Drawing

  # Only the 4 canonical styles (Regular/Bold/Italic/Bold Italic) of EVERY
  # variant in the zip (plain NF, NFM, NFP, and the NL-prefixed versions),
  # not every weight (Thin/ExtraLight/Medium/SemiBold/ExtraBold/Black and
  # their italics). Every weight in a given variant shares the SAME family
  # name (e.g. Bold and Thin both report 'JetBrainsMono NFM'), so
  # registering all of them under that name would mean each one's
  # registration overwrites the last -- the original bug here. Each of the
  # 4 canonical styles instead gets its own distinctly-suffixed registry
  # key, matching how Windows expects a multi-style TrueType family to be
  # registered (confirmed via fc-scan against the real files: identical
  # family name, distinct style for each of the 4).
  \$registered = @()
  Get-ChildItem -Path \$extract -Filter *.ttf | ForEach-Object {
    # Capture the pipeline item before the try/catch -- inside a catch
    # block \$_ is rebound to the caught error, not the file, so
    # referencing \$_ in there would silently print the wrong thing.
    \$file = \$_
    if (\$file.BaseName -notmatch '-(Regular|Bold|Italic|BoldItalic)\$') {
      return
    }
    \$styleSuffix = \$matches[1]
    try {
      \$destFile = Join-Path \$fontsDir \$file.Name
      Copy-Item \$file.FullName \$destFile -Force

      # Read the font's REAL embedded family name rather than guessing
      # it -- guessed/hardcoded names are the classic way these scripts
      # silently install files Windows never actually recognizes.
      \$collection = New-Object System.Drawing.Text.PrivateFontCollection
      \$collection.AddFontFile(\$destFile)
      \$familyName = \$collection.Families[0].Name

      \$regName = switch (\$styleSuffix) {
        'Regular'    { \"\$familyName (TrueType)\" }
        'Bold'       { \"\$familyName Bold (TrueType)\" }
        'Italic'     { \"\$familyName Italic (TrueType)\" }
        'BoldItalic' { \"\$familyName Bold Italic (TrueType)\" }
      }

      # Full path, not a bare filename -- a bare value resolves against
      # %SystemRoot%\Fonts (confirmed via Test-Path: absent there), not this
      # per-user AppData font dir, so Windows silently failed to load
      # whichever face still held a bare-filename registration. Observed
      # concretely as the Regular face resolving to an unrelated system
      # font while every other style here already had a full path (from an
      # earlier manual fix, never from this script) and loaded fine.
      New-ItemProperty -Path \$regPath -Name \$regName -Value \$destFile -PropertyType String -Force | Out-Null
      \$registered += \$destFile
    } catch {
      # A locked file (e.g. a running terminal already has this exact
      # style open) shouldn't abort the rest of the styles/variants.
      Write-Host \"Skipping \$(\$file.Name) (likely already installed/in use): \$_\"
    }
  }

  # Notify the session for every style just registered above (all variants,
  # not just one hardcoded variant name) -- otherwise switching wezterm.lua
  # to a different variant later would silently be un-notified again.
  \$notified = 0
  foreach (\$destFile in \$registered) {
    if ([FontInstaller]::AddFontResource(\$destFile) -ne 0) { \$notified++ }
  }
  \$HWND_BROADCAST = [IntPtr]0xffff
  \$WM_FONTCHANGE = 0x001D
  \$result = [UIntPtr]::Zero
  [FontInstaller]::SendMessageTimeout(\$HWND_BROADCAST, \$WM_FONTCHANGE, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 5000, [ref]\$result) | Out-Null

  Write-Host \"JetBrainsMono Nerd Font install pass complete (\$notified file(s) registered with this session)\"
} catch {
  Write-Host \"Font auto-install failed: \$_\"
  exit 1
}
"; then
    echo "Automated Windows font install failed (if powershell.exe says 'Exec format error', WSL interop is off: see docs/arch-wsl.md). $MANUAL_INSTRUCTIONS"
  fi
  exit 0
fi

if [ -n "${DISPLAY:-}" ] && command -v fc-cache >/dev/null 2>&1; then
  # Already installed (Omarchy and most Arch setups ship it as a package): don't download a second copy.
  # No `grep -q` here: this script uses `set -o pipefail`, and -q exits at the first match, which kills
  # fc-list with SIGPIPE and makes the whole pipeline report failure (the guard would never fire).
  if fc-list 2>/dev/null | grep -i 'JetBrainsMono Nerd Font' >/dev/null; then
    echo "==> JetBrainsMono Nerd Font is already installed on this system -- skipping the local install."
    exit 0
  fi
  echo "==> Local Linux display detected -- installing JetBrainsMono Nerd Font locally..."
  marker="$HOME/.local/share/fonts/.jetbrainsmono-nerd-font-installed"
  if [ ! -f "$marker" ]; then
    mkdir -p "$HOME/.local/share/fonts"
    if curl -fLo /tmp/JetBrainsMono.zip "$NERD_FONT_URL" \
      && unzip -o /tmp/JetBrainsMono.zip -d "$HOME/.local/share/fonts" >/dev/null \
      && fc-cache -f "$HOME/.local/share/fonts" >/dev/null; then
      touch "$marker"
      rm -f /tmp/JetBrainsMono.zip
    else
      echo "Local font install failed. $MANUAL_INSTRUCTIONS"
    fi
  fi
  exit 0
fi

# Headless Linux with no local display and not WSL -- whichever machine
# actually renders this terminal (e.g. a Mac or Windows host connecting in)
# needs the font, not this one. Nothing to do here.
exit 0
