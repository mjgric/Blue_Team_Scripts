if [ ! -e "./00-poweroff.rules" ]; then
    echo "./00-poweroff.rules does not exist"
    exit
fi

apt install -y polkitd
mkdir -p /etc/polkit-1/rules.d/

cp ./00-poweroff.rules /etc/polkit-1/rules.d/
