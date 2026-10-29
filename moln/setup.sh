#!/bin/bash
# Installerar PowerShell 7 i molnmiljön (Ubuntu). Används som miljöns startskript och som reserv i körningarna.
set -e
if command -v pwsh >/dev/null 2>&1; then exit 0; fi
. /etc/os-release
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
curl -sSL -o /tmp/packages-microsoft-prod.deb "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb"
$SUDO dpkg -i /tmp/packages-microsoft-prod.deb >/dev/null
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq powershell >/dev/null
pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
