# Windows laptop (Arch Linux on WSL)

Same dotfiles as the Ubuntu guide; only the distro setup differs. The package install
(`run_once_before_01-pacman-packages.sh`) is tested in an x86_64 Arch container. The
WSL-specific steps below are not, so expect to adjust them.

## A. On Windows (PowerShell)

```powershell
wsl --install -d archlinux       # opens a root shell in Arch when it finishes
```
Terminal app: **Noctty** (`winget install --id AmanThanvi.noctty -e`). It opens `wsl.exe`, your default distro: make Arch
the default with `wsl --set-default archlinux`, or set `command = wsl.exe -d archlinux` in
`~/.config/noctty/config.ghostty` later. (Otty is the Mac's terminal and is not used on Windows for now.)

## B. Create your user (in the root shell)

The Arch image starts as root with no user, no `sudo` and no keyring. Replace `<you>`.

```bash
pacman-key --init && pacman-key --populate archlinux
pacman -Syu --noconfirm sudo git
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
useradd -m -G wheel -s /bin/bash <you> && passwd <you>
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
printf '[user]\ndefault=<you>\n' >> /etc/wsl.conf
# Arch's systemd doesn't register WSL's Windows-interop handler; without it
# powershell.exe/cmd.exe fail ("Exec format error") and the font/terminal-config
# steps are skipped.
echo ':WSLInterop:M::MZ::/init:PF' > /usr/lib/binfmt.d/WSLInterop.conf
exit
```
Back in PowerShell, restart so the default user applies, then open Arch again:
```powershell
wsl --terminate archlinux
wsl -d archlinux                 # now as <you>
```

## C. Install the dotfiles (as your user)

```bash
sudo pacman -S --noconfirm chezmoi
chezmoi init --apply https://github.com/jpatrickb/dotfiles-public.git
```
Accept the `sudo` prompt; it takes a few minutes. This installs everything from
pacman (Neovim, Go, Rust, Terraform, delta, fastfetch, eza, starship, mise, uv, ...) and
copies the Noctty config and colour palette to Windows. The shell on Arch is **bash**, with ble.sh 0.4 (the AUR `blesh-git`) for suggestions and highlighting. A fresh Arch has no AUR helper,
so the install builds **yay** once (the same helper Omarchy uses) and installs ble.sh through it; if that fails, bash still works and
the output says how to retry.

`chezmoi init` asks whether to install the AWS CLI and the GCP CLI (default: no). To add
either later, run `chezmoi init --prompt`, answer yes, then `chezmoi apply`.

Then edit `~/.gitconfig.local` (created automatically): set your git name and email.

**Then restart WSL, so every shell starts fresh.** The terminal you ran the install in began before the shell config
existed, so it does not have the new PATH (`~/.local/bin`, which holds `herdr` and others) and a plain new tab may reuse
it. In Windows PowerShell run `wsl --terminate archlinux`, then open Arch again.

## D. First launch

Same as [Windows, part C](windows-wsl.md#c-first-launch), after the WSL restart above: restart the terminal app (font),
confirm the Noctty config landed, `tmux` (no plugin step), `nvim` then wait for
`:Mason`, restart nvim ([neovim.md](neovim.md)). Check with `hash -r && chezmoi status` (expect only R lines).

## Notes

- If you see `Exec format error` from `powershell.exe`/`cmd.exe`, interop is missing; run the
  `WSLInterop.conf` line from section B, then `sudo systemctl restart systemd-binfmt` and
  `chezmoi apply`.
- Arch is rolling: run `sudo pacman -Syu` regularly, never `-Sy` alone.
- Not in the official repos, so handled separately: `mdcat` (release binary, installed by
  `run_once_before_02`) and fast-syntax-highlighting (cloned by `run_once_03`).
