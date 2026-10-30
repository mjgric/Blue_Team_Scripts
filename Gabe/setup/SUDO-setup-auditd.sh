apt install -y auditd audispd-plugins

echo "-a always,exit -F arch=b64 -S execve -k audit-wazuh-c" > /etc/audit/rules.d/wazuh-ir.rules

augenrules --load
auditctl -l
