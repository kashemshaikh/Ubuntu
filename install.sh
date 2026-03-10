#!/data/data/com.termux/files/usr/bin/bash

set -Eeuo pipefail
IFS=$'\n\t'

# Colors
R="$(printf '\033[1;31m')"
G="$(printf '\033[1;32m')"
Y="$(printf '\033[1;33m')"
W="$(printf '\033[1;37m')"
C="$(printf '\033[1;36m')"

CHROOT="$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu"

banner() {
    clear
    printf '%s╔════════════════════════════════════╗\n' "$C"
    printf '%s║     Ubuntu Desktop Installer      ║\n' "$C"
    printf '%s║         for Termux                 ║\n' "$C"
    printf '%s╚════════════════════════════════════╝\n%s' "$C" "$W"
}

install_ubuntu() {
    printf '\n'
    if [ -d "$CHROOT" ]; then
        printf '%sExisting Ubuntu installation found, Resetting it...%s\n' "$G" "$W"
        proot-distro reset ubuntu
    else
        printf '%sInstalling Ubuntu...%s\n\n' "$G" "$W"
        pkg update -y
        pkg install -y proot-distro
        proot-distro install ubuntu
    fi
}

install_desktop() {
    printf '%sInstalling XFCE Desktop...%s\n' "$G" "$W"
    cat > "$CHROOT/root/.bashrc" <<'EOF'
set -e
apt-get update
apt-get install -y udisks2
rm -f /var/lib/dpkg/info/udisks2.postinst
: > /var/lib/dpkg/info/udisks2.postinst
dpkg --configure -a
apt-mark hold udisks2
apt-get install --no-install-recommends xfce4 -y
apt-get install gnome-terminal nautilus dbus-x11 tigervnc-standalone-server -y
# Create VNC scripts with explicit display number
echo 'vncserver :1 -geometry 1280x720 -xstartup /usr/bin/startxfce4' > /usr/local/bin/vncstart
echo 'vncserver -kill :1' > /usr/local/bin/vncstop
chmod +x /usr/local/bin/vncstart /usr/local/bin/vncstop
sleep 2
exit
EOF
    proot-distro login ubuntu
    rm -f "$CHROOT/root/.bashrc"
}

adding_user() {
    printf '%sAdding a User...%s\n' "$G" "$W"
    cat > "$CHROOT/root/.bashrc" <<'EOF'
set -e
apt-get update
apt-get install -y sudo wget
useradd -m -s /bin/bash ubuntu
printf 'ubuntu:ubuntu\n' | chpasswd
printf 'ubuntu ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/ubuntu
exit
EOF
    proot-distro login ubuntu
    # Create shortcut command to login as ubuntu user
    echo 'proot-distro login --user ubuntu ubuntu' > "$PREFIX/bin/ubuntu"
    chmod +x "$PREFIX/bin/ubuntu"
    rm -f "$CHROOT/root/.bashrc"
}

install_theme() {
    printf '%sInstalling Theme%s\n' "$G" "$W"
    # Backup original .bashrc for ubuntu user
    mv "$CHROOT/home/ubuntu/.bashrc" "$CHROOT/home/ubuntu/.bashrc.bak"
    # Download and run theme script, then exit
    echo 'wget https://raw.githubusercontent.com/kashemshaikh/Ubuntu/main/theme/theme.sh && bash theme.sh && exit' > "$CHROOT/home/ubuntu/.bashrc"
    # Run ubuntu user once to execute the theme script
    proot-distro login --user ubuntu ubuntu
    # Clean up
    rm -f "$CHROOT/home/ubuntu/theme.sh"
    rm -f "$CHROOT/home/ubuntu/.bashrc"
    mv "$CHROOT/home/ubuntu/.bashrc.bak" "$CHROOT/home/ubuntu/.bashrc"
    # Also copy to root for consistency (optional)
    cp "$CHROOT/home/ubuntu/.bashrc" "$CHROOT/root/.bashrc"
    sed -i 's/32/31/g' "$CHROOT/root/.bashrc"   # change color from green to red for root prompt
}

install_extra() {
    printf '%sInstalling Extra Software (Firefox, gedit)%s\n' "$G" "$W"
    cat > "$CHROOT/root/.bashrc" <<'EOF'
set -e
apt update
apt install -y firefox gedit
exit
EOF
    proot-distro login ubuntu
    rm -f "$CHROOT/root/.bashrc"
}

sound_fix() {
    printf '%sFixing Sound...%s\n' "$G" "$W"
    # Install pulseaudio on host
    pkg update -y
    pkg install -y x11-repo pulseaudio
    # Add pulseaudio start to host .bashrc with a check
    if ! grep -q "pulseaudio --start" "$HOME/.bashrc"; then
        cat >> "$HOME/.bashrc" <<'EOF'
# Start pulseaudio for audio forwarding (if not already running)
if ! pulseaudio --check; then
    pulseaudio --start \
        --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
        --exit-idle-time=-1
fi
EOF
    fi
    # Backup ubuntu user's .bashrc
    mv "$CHROOT/home/ubuntu/.bashrc" "$CHROOT/home/ubuntu/.bashrc.bak"
    # Run a temporary script inside ubuntu to create firefox profile and set user.js
    cat > "$CHROOT/home/ubuntu/.bashrc" <<'EOF'
vncstart
sleep 4
DISPLAY=:1 firefox &
sleep 10
pkill -f firefox
vncstop
exit
EOF
    proot-distro login --user ubuntu ubuntu
    rm -f "$CHROOT/home/ubuntu/.bashrc"
    mv "$CHROOT/home/ubuntu/.bashrc.bak" "$CHROOT/home/ubuntu/.bashrc"

    # Locate the firefox profile directory and place user.js
    PROFILE_DIR=$(find "$CHROOT/home/ubuntu/.mozilla/firefox" -maxdepth 1 -name "*.default-esr" | head -n 1)
    if [ -n "$PROFILE_DIR" ]; then
        wget -O "$PROFILE_DIR/user.js" \
            https://raw.githubusercontent.com/kashemshaikh/Ubuntu/main/fixes/user.js
    else
        printf '%sFirefox profile not found. user.js could not be installed.%s\n' "$Y" "$W"
    fi
}

final_banner() {
    banner
    printf '\n%sInstallation completed successfully!%s\n\n' "$G" "$W"
    printf 'Commands:\n'
    printf '  %subuntu%s        -  Enter Ubuntu (as user "ubuntu")\n' "$C" "$W"
    printf '  (inside Ubuntu)  vncstart  -  Start VNC server on display :1\n'
    printf '                   vncstop   -  Stop VNC server on display :1\n\n'
    printf 'Default password for user "ubuntu": %subuntu%s\n' "$Y" "$W"
    # Self-delete the script
    rm -f -- "$0"
}

# Main execution
banner
install_ubuntu
install_desktop
adding_user
install_theme
install_extra
sound_fix
final_banner