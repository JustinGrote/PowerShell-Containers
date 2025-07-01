# Define file paths
$PINNING_FILE = "/etc/apt/preferences.d/podman-plucky.pref"
$SOURCE_LIST = "/etc/apt/sources.list.d/plucky.list"

# Write Plucky APT source list
Write-Host "Adding Plucky repo to $SOURCE_LIST..."
"deb http://archive.ubuntu.com/ubuntu plucky main universe" > $SOURCE_LIST

# Write APT pinning rules
Write-Host "Writing APT pinning rules to $PINNING_FILE..."
@"
Package: podman buildah golang-github-containers-common crun libgpgme11t64 libgpg-error0 golang-github-containers-image catatonit conmon containers-storage
Pin: release n=plucky
Pin-Priority: 991

Package: libsubid4 netavark passt aardvark-dns containernetworking-plugins libslirp0 slirp4netns
Pin: release n=plucky
Pin-Priority: 991

Package: *
Pin: release n=plucky
Pin-Priority: 400
"@ > $PINNING_FILE

# Update APT cache
sudo apt update
sudo apt install -y podman buildah

Write-Host "Plucky pinning setup complete."