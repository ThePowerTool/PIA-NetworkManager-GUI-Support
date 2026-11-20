# PIA-NetworkManager-GUI-Support

This repository provides Private Internet Access (PIA) Linux users with NetworkManager GUI OpenVPN profiles and support for PIA's Next-Gen port forwarding.

If you do not require port forwarding, simply run `pia_NM_profiles_install.sh` (selecting `n` for port forwarding) and connect using your desktop NetworkManager GUI.

---

## Repository Files

* **`pia_NM_profiles_install.sh`** (`v1.1`) — Downloads PIA's `v6` server list, OpenVPN CA certificates, and Next-Gen port-forwarding CA certificate, and installs `.nmconnection` OpenVPN profiles into `/etc/NetworkManager/system-connections/`.
* **`get_region_and_token_NM_GUI.sh`** (`v1.3`) — Detects your active `PIApf-*` NetworkManager VPN connection, requests an authentication token from PIA's API (`/api/client/v2/token`), and automatically launches `port_forwarding.sh`.
* **`port_forwarding.sh`** (`v1.3`) — Requests a port-forwarding signature (`getSignature`) from the VPN gateway, binds the assigned port (`bindPort`), and keeps it alive every 15 minutes. It also prints the manual CLI command to re-run `port_forwarding.sh` directly if needed.
* **`ca.rsa.4096.crt`** — PIA's Next-Gen root CA certificate downloaded automatically by `pia_NM_profiles_install.sh` from PIA's official `pia-foss/manual-connections` repository. Used locally by `port_forwarding.sh` to verify TLS connections to the VPN gateway (`:19999`). *(Separate from the OpenVPN CA certificates saved to `/etc/openvpn/pia-ca.rsa.*.crt`.)*
* **`/var/log/pia-v6-at-install.dat`** — Static snapshot of PIA's `v6` server JSON saved during profile installation so `get_region_and_token_NM_GUI.sh` can match your installed profile to its server metadata.
* **`.pia-credentials`** *(optional)* — Manually created 2-line plain-text file containing your PIA username on line 1 and password on line 2 (no quotes or extra spaces). The scripts automatically enforce `chmod 600` on this file when detected.
* **`README.md`** — This documentation file.

---

## Prerequisites

1. **NetworkManager & OpenVPN Plugin**: NetworkManager (`nmcli`) and its OpenVPN plugin (e.g., `network-manager-openvpn` on Debian/Ubuntu or `NetworkManager-openvpn` on Fedora/RHEL) must be installed, along with `curl`, `jq`, and `uuidgen`.
2. **Desktop NM-GUI**: A desktop NetworkManager applet/GUI (GNOME, KDE Plasma, XFCE, etc.) to select and toggle VPN connections.

---

## Usage

### 1. Install NetworkManager Profiles
Make the scripts executable and run the installer as `root`:

```bash
chmod +x pia_NM_profiles_install.sh get_region_and_token_NM_GUI.sh port_forwarding.sh
sudo ./pia_NM_profiles_install.sh
```

* Selecting **`Y`** for port forwarding installs profiles prefixed with **`PIApf-`** (filtering only regions that support port forwarding and are online).
* Selecting **`n`** for port forwarding installs profiles prefixed with **`PIA-`**.
* Both sets can coexist side-by-side in NetworkManager.

### 2. Verify & Connect via NetworkManager GUI
1. Verify the `.nmconnection` files were created:
   ```bash
   ls /etc/NetworkManager/system-connections/PIA*
   ```
2. Open your desktop **NetworkManager GUI**, select a PIA profile, and connect.
3. Confirm the active connection from the terminal:
   ```bash
   nmcli connection show --active
   ```

### 3. Enable Port Forwarding *(Optional)*
While connected to a **`PIApf-*`** profile (note: PIA does not support port forwarding on US servers), run from the repository directory:

```bash
sudo ./get_region_and_token_NM_GUI.sh
```

Leave the terminal running (or run it inside `tmux` / `screen`) so `port_forwarding.sh` can refresh the port binding every 15 minutes.

---

## Troubleshooting

* **Profile fails to connect**:
  * Inspect the generated profile configuration:
    ```bash
    sudo less "/etc/NetworkManager/system-connections/<profile-name>.nmconnection"
    ```
  * Ensure your distribution's NetworkManager OpenVPN plugin package is installed (`network-manager-openvpn` / `NetworkManager-openvpn`).
  * Try another region—an individual server in a static profile may occasionally be offline for maintenance, or re-run `sudo ./pia_NM_profiles_install.sh` to refresh the `v6` server list.
* **Profiles do not appear in the GUI immediately**:
  * Reload NetworkManager connections manually:
    ```bash
    sudo nmcli connection reload
    ```
* **Debugging token or port-forwarding requests**:
  * Both `get_region_and_token_NM_GUI.sh` and `port_forwarding.sh` print the exact `curl` commands they execute. You can copy the printed command, replace `-s` with `-vs` (`--verbose`), and run it manually to inspect TLS or API responses.
  * If PIA rotates a server's TLS Common Name (`CN=`) after install, `port_forwarding.sh` will automatically detect the new `CN=` from `curl` output and retry `getSignature`.

---

## Version History

* **`pia_NM_profiles_install.sh` (`v1.1`)**
  * Updated server list endpoint from `v5` to `v6` (`pia-v6-at-install.dat`) and filtered out offline regions.
  * Downloaded PIA's Next-Gen `ca.rsa.4096.crt` from `pia-foss/manual-connections` for port forwarding while keeping OpenVPN CA certificates separate under `/etc/openvpn/`.
  * Generated modern `.nmconnection` profile files with scoped prefix cleanup (`PIA-*` vs. `PIApf-*`) so both profile sets can coexist.
  * Added runtime dependency checks (`curl`, `jq`, `nmcli`, `uuidgen`), enforced `chmod 600` on `.pia-credentials`, and removed plain-text password echoing.
* **`get_region_and_token_NM_GUI.sh` (`v1.3`)**
  * Switched token authentication to PIA's `POST /api/client/v2/token` endpoint for reliable token generation across all regions.
  * Updated snapshot lookup to `/var/log/pia-v6-at-install.dat` with slash-sanitized region matching.
  * Improved active `PIApf-*` VPN profile and gateway detection via `nmcli`, and redacted passwords from printed debug commands.
* **`port_forwarding.sh` (`v1.3`)**
  * Replaced `eval` process substitution with deterministic `mktemp` stderr capture for `getSignature`.
  * Hardened `CN=` certificate subject extraction across OpenSSL/GnuTLS `curl` builds when handling PIA TLS certificate name drift.
  * Added startup checks for required tools (`curl`, `jq`, `base64`) and `./ca.rsa.4096.crt`.

