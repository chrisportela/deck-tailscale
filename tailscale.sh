#!/usr/bin/env bash

# make system configuration vars available
source /etc/os-release

# set invocation settings for this script:
# -e: Exit immediately if a command exits with a non-zero status.
# -u: Treat unset variables as an error when substituting.
# -o pipefail: the return value of a pipeline is the status of the last command to exit with a non-zero status, or zero if no command exited with a non-zero status
set -eu -o pipefail

# save the current directory silently
pushd . > /dev/null

# make a temporary directory, save the name, and move into it
dir="$(mktemp -d)"
cd "${dir}"

echo -n "Getting version..."

# get info for the latest version of Tailscale
tarball="$(curl -s 'https://pkgs.tailscale.com/stable/?mode=json' | jq -r .Tarballs.amd64)"
version="$(echo ${tarball} | cut -d_ -f2)"

echo "got ${version}."

echo -n "Downloading..."

# download the Tailscale package itself
curl -s "https://pkgs.tailscale.com/stable/${tarball}" -o tailscale.tgz

echo "done."

echo -n "Installing..."

# extract the tailscale binaries
tar xzf tailscale.tgz
tar_dir="$(echo ${tarball} | cut -d. -f1-3)"
test -d $tar_dir

# create our target directory structure
mkdir -p tailscale/usr/{bin,sbin,lib/{systemd/system,extension-release.d}}

# pull things into the right place in the target dir structure
cp -rf $tar_dir/tailscale tailscale/usr/bin/tailscale
cp -rf $tar_dir/tailscaled tailscale/usr/sbin/tailscaled

# write a systemd extension-release file
echo -e "SYSEXT_LEVEL=1.0\nID=steamos\nVERSION_ID=${VERSION_ID}" >> tailscale/usr/lib/extension-release.d/extension-release.tailscale

# create the system extension folder if it doesn't already exist, remove the old version of our tailscale extension, and install our new one
mkdir -p /var/lib/extensions
rm -rf /var/lib/extensions/tailscale
cp -rf tailscale /var/lib/extensions/

# copy the systemd files into place
cp -rf $tar_dir/systemd/tailscaled.service /etc/systemd/system

sed -i 's/--port.*//g' tailscale/usr/lib/systemd/system/tailscaled.service

# copy in the defaults file if it doesn't already exist
if ! test -f /etc/default/tailscaled; then
  cp -rf $tar_dir/systemd/tailscaled.defaults /etc/default/tailscaled
fi

# return to our original directory (silently) and clean up
popd > /dev/null
rm -rf "${dir}"

# copy in our overrides file if it doesn't already exist
if ! test -f /etc/systemd/system/tailscaled.service.d/override.conf; then
  mkdir -p /etc/systemd/system/tailscaled.service.d
  cp -rf override.conf /etc/systemd/system/tailscaled.service.d/override.conf
fi

echo "done."

echo "Starting services..."

if systemctl is-enabled --quiet systemd-sysext && systemctl is-active --quiet systemd-sysext; then
  echo "systemd-sysext is already enabled and active"
else
  systemctl enable systemd-sysext --now
fi

systemd-sysext refresh > /dev/null 2>&1
systemctl daemon-reload > /dev/null

if systemctl is-enabled --quiet tailscaled && systemctl is-active --quiet tailscaled; then
  echo "tailscaled is already enabled and active; restarting it..."
  systemctl restart tailscaled
else
  systemctl enable tailscaled --now
fi

echo "Tailscale installed and ready."
