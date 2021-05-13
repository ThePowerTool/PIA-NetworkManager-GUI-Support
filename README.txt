This repository is intended to provide Private Internet Access customers using
Linux with support for the NetworkManager-GUI and offer access to
port forwarding.

If you do not require port forwarding simply run the profiles install and use
the NM-GUI to connect to PIA.

ca.rsa.4096.crt    - this cert should only be downloaded directly from PIA.
                     The download is provided by pia_NM_profiles_install.sh
pia-v5-at-install.dat - static v5 data created by pia_NM_profiles_install.sh
                        and saved in /var/log
pia_NM_profiles_install.sh - installs NetworkManager profiles for PIA
get_region_and_token_NM_GUI.sh - Request port forwarding
port_forwarding.sh - this script launched by get_region_and_token_NM_GUI.sh
                     which also provides CL (on finishing) to launch this script
.pia-credentials   - optional: 1st line username, 2nd line password (no quotes,
                     nothing else). This file must be manually created.
README.txt         - this file

Additional details:
NetworkManager must be installed before launching any script found here.
Details on installing NetworkManager can be found via Google search
  for your Linux distribution and NetworkManager
The NM-GUI is the NetworkManager Graphical User Interface supported by
  the desktop (gnome, kde, etc).
Once you have NetworKManager installed and have run the pia_NM_profiles_install
  you can:
  1.  Verify profiles were written by issuing the command:
        ls /etc/NetworkManager/system-connections
  2.  Verify a profile successfully connects by
      a) access the profile via your desktop NM-GUI
      b) from the GUI start the connection
      c) once the GUI displays a successful connection use the following CL:
         nmcli connection show
         or
         nmcli connection show [profile name from 1](*)
         or
         nmcli -g name connection show | head -1
         * Note:  you may need to quote the name (e.g. "Czech Republic")

Troubleshooting:
If a profile does not connect for any reason you can review the profile details:
less /etc/NetworkManager/system-connections/[PIA profile name]

Try connecting with a diffent profile.  A given server referenced within a
  static profile may be offline for maintenance.

Final Note on Troubleshooting:  When sending a generateToken request via
  get_region_and_token_NM_GUI.sh some servers simply do not respond.  Please
  connect and try from another server.  You can copy the displayed curl command
  and replase the "-s" with "--verbose" to verify server response.
