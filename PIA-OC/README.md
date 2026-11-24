# PIA-OC: OpenVPN-over-Shadowsocks Obfuscation Connection (OC) Toolkit

Provides two-hop VPN traffic obfuscation for Private Internet Access (PIA) on Linux (tested on Fedora 42):

```text
[Local NIC] ──▶ Shadowsocks (TCP 443) ──▶ [PIA Entry Bridge] ──▶ OpenVPN (TCP 501) ──▶ [PIA Exit POP] ──▶ [Internet]
```

> **Isolation Note:** Because NetworkManager and GNOME do not natively support OpenVPN-over-Shadowsocks (`socks-proxy`) integration in the desktop GUI, this toolkit operates independently from the root repository's standard NetworkManager GUI profiles:
> * Uses its own local v6 server snapshot (`PIA-OC/pia-v6-servers.dat`) without modifying `/var/log/pia-v6-at-install.dat`.
> * Uses the `O-PIA-` prefix and writes optional `.nmconnection` profiles into `PIA-OC/O-PIA-NMprofiles/` so GNOME NetworkManager stays untouched.
> * **Privacy Caveat:** While Shadowsocks disguises OpenVPN packets from Deep Packet Inspection (DPI), switching exit POPs still exposes a public PIA exit IP address to destination websites.

---

## Prerequisites

1. **Private Internet Access (PIA) Account & `root`/`sudo` Access**: Required to modify routing tables (`ip route`), configure `systemd-resolved` DNS, and launch `openvpn`.
2. **Shadowsocks Client (`shadowsocks-rust` / `sslocal`)**:
   * `OpenVPN-OC-up.sh` expects the `sslocal` binary at `/root/.cargo/bin/sslocal` (configurable via `PROXY_BINARY` at the top of `OpenVPN-OC-up.sh`).
   * On Fedora/RHEL, install via Cargo (`sudo cargo install shadowsocks-rust` after `sudo dnf install -y cargo rust openssl-devel`) or your distribution's package manager and update `PROXY_BINARY` accordingly.
3. **OpenVPN & CLI Utilities**:
   * `openvpn` (`2.6+` recommended for AEAD `AES-256-GCM` negotiation), `curl`, `jq`, `ip` (`iproute` / `iproute2`), `pgrep` (`procps-ng`), and `resolvectl` (`systemd-resolved`).
4. **PIA OpenVPN Root CA Certificate**:
   * Expected at `/etc/openvpn/pia-ca.rsa.4096.crt` (installed automatically if you have already run `../pia_NM_profiles_install.sh`, or downloadable from PIA's `pia-foss/manual-connections` repository).
5. **PIA Credentials File (`/root/.pia-auth`)**:
   * Create a 2-line plain-text file owned by `root` (`chmod 600 /root/.pia-auth`) containing **only** your PIA username on line 1 and your PIA password on line 2 (no labels, quotes, or extra blank lines):
     ```text
     p1234567
     your_pia_password
     ```
   * Quick setup command:
     ```bash
     sudo bash -c 'printf "p1234567\nyour_pia_password\n" > /root/.pia-auth && chmod 600 /root/.pia-auth'
     ```
---

## Directory Contents

* **`PIA-OC.conf`** — Single path configuration file sourced by the toolkit scripts (`SCRIPT_DIR`). Defaults to the directory containing `PIA-OC.conf` (or can be pinned to a custom directory such as `/root/PIA-OC`).
* **`OpenVPN-OC-up.sh`** — Primary CLI connect script. Accepts optional `[BRIDGE_ARG] [EXIT_ARG]` (defaults: `Seattle` `czech`). Automatically tries `<EXIT_ARG>.privacy.network` first and fails over to the region's `.pvt.site` FQDN if primary fails. Auto-detects the physical gateway/NIC, locks DNS via `systemd-resolved`, verifies public exit IP/country, and logs cipher history.
* **`OpenVPN-OC-down.sh`** — Cleanly terminates `openvpn` and `sslocal`, removes split-tunnel (`0.0.0.0/1`, `128.0.0.0/1`) and `/32` bridge routes, deletes `/tmp/PIA-OC-active.ovpn`, and flushes DNS caches.
* **`OpenVPN-OC-status.sh`** — Checks local daemon PIDs (`sslocal`, `openvpn`), `tun0` interface state, split-tunnel routes, `systemd-resolved` DNS lock, and performs a parallel background `curl` check against `1.1.1.1/cdn-cgi/trace` to verify whether your live public IP/country matches the last session log.
* **`one-line-OC-status-checks.sh`** — Quick offline terminal reference checking `tun0`, active split-tunnel routes, `resolvectl` DNS status, and running `sslocal`/`openvpn` processes.
* **`list-PIA-OC-options.sh`** — Lists available `[BRIDGE_ARG]` tags from `NM-PIA-OC.json` and suffix-free `[EXIT_ARG]` POP slugs from `pia-v6-servers.dat`. Supports `--pf` (port-forwarding POPs only) and keyword filtering.
* **`update-PIA-OC-servers.sh`** — Fetches PIA's latest `v6` server list into `pia-v6-servers.dat` and validates `NM-PIA-OC.json`.
* **`NM-PIA-OC.json`** — `shadowsocks-rust` configuration defining 10 PIA Shadowsocks entry bridges (local ports `1080`–`1089`).
* **`PIA-OC-Template.ovpn`** — Base OpenVPN TCP template (`AEAD` `data-ciphers`, `verb 3`, `route-noexec`) rendered dynamically at runtime into `/tmp/PIA-OC-active.ovpn`.
* **`NM-deploy-PIA-OC-profiles.sh`** — Reads `/root/.pia-auth` and generates isolated `O-PIA-*` `.nmconnection` files inside `O-PIA-NMprofiles/` without loading them into NetworkManager/GNOME.

---

## Quick Usage

Run all commands from inside the `PIA-OC/` directory as `root` (or with `sudo`):

1. **Fetch the latest PIA server list (required on first run):**
   ```bash
   sudo ./update-PIA-OC-servers.sh
   ```
2. **List available entry bridges and exit POP arguments:**
   ```bash
   ./list-PIA-OC-options.sh
   ./list-PIA-OC-options.sh --pf uk
   ```
3. **Connect using default route (`Seattle` bridge $\rightarrow$ `czech` exit):**
   ```bash
   sudo ./OpenVPN-OC-up.sh
   ```
4. **Connect using custom bridge and exit arguments:**
   ```bash
   sudo ./OpenVPN-OC-up.sh UK-London swiss
   sudo ./OpenVPN-OC-up.sh Amsterdam austria.pvt.site
   ```
   *(Short arguments without dots automatically append `.privacy.network` with `.pvt.site` fallback; full FQDNs containing dots are used as-is.)*
5. **Check active tunnel status:**
   ```bash
   sudo ./OpenVPN-OC-status.sh
   ```
6. **Disconnect and restore normal routing:**
   ```bash
   sudo ./OpenVPN-OC-down.sh
   ```

---

## Logs & Runtime Files

| Path | Purpose |
| :--- | :--- |
| `/root/.pia-auth` | 2-line PIA credentials file (`chmod 600`) |
| `/var/log/pia-cipher-history.log` | Persistent session log (timestamp, bridge, exit, public IP/country, `tun0` IP, negotiated cipher) |
| `/var/log/openvpn-pia.log` | Active OpenVPN daemon log |
| `/var/log/sslocal-pia.log` | Active `shadowsocks-rust` (`sslocal`) daemon log |
| `/tmp/PIA-OC-active.ovpn` | Temporary runtime OpenVPN profile (deleted automatically on disconnect) |

