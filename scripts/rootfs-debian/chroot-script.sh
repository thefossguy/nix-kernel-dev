PKGS=(
    network-manager
    sudo
)
USER_COMMENT='Pratham Patel'
USER_NAME='pratham'
USER_GROUPS='sudo'

apt-get update
apt-get install -y "${PKGS[@]}"
apt-get upgrade -y

useradd \
    --uid 1000 \
    --create-home \
    --comment "${USER_COMMENT}" \
    --user-group "${USER_NAME}" \
    --groups "${USER_GROUPS}"
sed -i "s/# %wheel\tALL=(ALL)\tNOPASSWD: ALL/%wheel\tALL=(ALL)\tNOPASSWD: ALL/" /etc/sudoers
chsh -s "$(which bash)" "${USER_NAME}"
passwd -d "${USER_NAME}"
chsh -s "$(which bash)" root
passwd -d root

systemctl enable NetworkManager.service
mkdir -p /etc/systemd/system/getty@tty1.service.d/
mkdir -p /etc/systemd/system/serial-getty@tty{AMA,S}0.service.d/
cat << EOF > /etc/systemd/system/getty@tty1.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin ${USER_NAME} %I \$TERM
EOF
cat << EOF > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --keep-baud --autologin ${USER_NAME} 1500000,115200,57600,38400,9600 - \$TERM
EOF
cp /etc/systemd/system/serial-getty@tty{S,AMA}0.service.d/autologin.conf

echo 'debian' | tee /etc/hostname
echo '127.0.0.1       debian' | tee -a /etc/hosts
