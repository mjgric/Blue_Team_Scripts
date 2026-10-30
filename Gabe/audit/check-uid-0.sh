awk -F: '$3 == 0 && $1 != "root" {print "UNEXPECTED UID 0:", $1}' /etc/passwd
