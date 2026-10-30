file=$1

echo
echo "warning: this script will probably do some weird shit if the input file is not formatted right"
echo "proper format: <BIN PATH> <CHMOD NUMBER> and separated by \\n"
echo
echo "checking for bad perms:"
echo

if [ ! -e "$1" ]; then
    echo "provided bins file does not exist"
fi

while read l; do
    res=($l)
    bin=${res[0]}
    desired_perm=${res[1]}

    pattern="Access: \\\([0-9]{4}\\\)"

    # holy worst regex oat
    real_perm=$(stat "$bin" | grep "Access: (" | sed "s/Access: (\(.*\)\/.*).*  Uid: .*/\1/")

    if [ "$desired_perm" -ne "$real_perm" ]; then
        echo "Permission does not match for $bin: is $real_perm, should be $desired_perm"
    fi

done < ./suid-bins.txt

echo
