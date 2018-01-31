
export PASSVAR=PASS

function xscp() {
	echo xscp
	expect -c "
spawn scp $@
expect password:
send ${!PASSVAR}\r
expect eof
"
}

function xssh() {
	expect -c "
spawn ssh $@
expect password:
send ${!PASSVAR}\r
expect eof
"
}

# Run ssh, piping in stdin for execution behavior
function xssh_in() {
  expect -c "
spawn ssh $@ bash -s
expect password:
send ${!PASSVAR}\r
expect \r\n
while {[gets stdin line] != -1} {
  send \"\$line\r\"
}
send \004

expect eof
"
}


