#!/bin/bash
# update dependencies of project file

PROJECT=./letux-gsde.qcodeproj

function dependencies() {

# this is not correct...
# wget -O - https://raw.githubusercontent.com/onflapp/gs-desktop/refs/heads/main/dependencies/debian.txt
	cat debian.txt
}

# delete existing dependencies
sed -i.bak '/DEBIAN_DEPENDS.*/d' "$PROJECT"

OP='=\"'

dependencies | while read DEPENDS
do
	sed -i.bak "/export DEBIAN_DESCRIPTION.*/i\\
export DEBIAN_DEPENDS$OP$DEPENDS\"
" "$PROJECT"
	OP='+=", '
done

"$PROJECT"