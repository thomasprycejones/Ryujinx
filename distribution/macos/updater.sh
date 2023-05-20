#!/bin/bash

set -e

INSTALL_DIRECTORY=$1
NEW_APP_DIRECTORY=$2
APP_PID=$3
APP_ARGUMENTS="${@:4}"
BACKUP_DIRECTORY="$INSTALL_DIRECTORY.bak"

error_handler() {
    local lineno="$1"
    local msg="$2"
    local exit_status="$3"

    script="""
    set alertTitle to \"Ryujinx - Updater error\"
    set alertMessage to \"An error occurred during Ryujinx update (updater.sh:$lineno). Exit status: $exit_status. $msg\n\nPlease download the update manually from our website if the problem persists.\"
    display dialog alertMessage with icon caution with title alertTitle buttons {\"Open Download Page\", \"Exit\"}
    set the button_pressed to the button returned of the result
    if the button_pressed is \"Open Download Page\" then
        open location \"https://ryujinx.org/download\"
    end if
    """

    echo "Error at line $lineno: $msg. Exit status: $exit_status." >> updater.log

    osascript -e "$script"
    exit 1
}

# Validate inputs
if [[ ! -d "$INSTALL_DIRECTORY" ]]; then
    error_handler ${LINENO} "Install directory does not exist" 1
fi

if [[ ! -d "$NEW_APP_DIRECTORY" ]]; then
    error_handler ${LINENO} "New app directory does not exist" 1
fi

if ! kill -0 $APP_PID 2> /dev/null; then
    error_handler ${LINENO} "No process found with PID: $APP_PID" 1
fi

# Backup current installation
cp -r "$INSTALL_DIRECTORY" "$BACKUP_DIRECTORY"

# Wait for Ryujinx to exit, then forcefully terminate if necessary
lsof -p $APP_PID +r 1 &>/dev/null
sleep 1

if kill -0 $APP_PID 2> /dev/null; then
    kill $APP_PID
    sleep 1

    if kill -0 $APP_PID 2> /dev/null; then
        kill -9 $APP_PID
    fi
fi

trap 'error_handler ${LINENO} "$BASH_COMMAND" $?' ERR

# Replace and reopen
rm -rf "$INSTALL_DIRECTORY"
mv "$NEW_APP_DIRECTORY" "$INSTALL_DIRECTORY"

if [ "$#" -le 3 ]; then
    open -a "$INSTALL_DIRECTORY"
else
    open -a "$INSTALL_DIRECTORY" --args "$APP_ARGUMENTS"
fi
