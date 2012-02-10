#!/bin/bash

# files to be managed (defined as array in LINK_CONF)
#   index 2k is key (source)
#   index 2k+1 is value (destination)
LINK_CONF=$HOME/etc/.link.conf

OPTIONS=0
ALL=1
FFLAG=0
BFLAG=0
DFLAG=0
RFLAG=0
VFLAG=0
WFLAG=0

check_options() {
    if [[ $OPTIONS == 1 ]]; then
        echo >&2 "$(basename $0): error: too many options specified"
        usage
    fi
}

read_opt_args() {
    if [[ -n $@ ]]; then
        read -ra ARG_FILES <<< "$@"
        FSIZE=$(( ${#ARG_FILES[@]} ))
        ALL=0
    fi
}

check_link_conf() {
    if [[ ! -e $LINK_CONF ]]; then
        echo >&2 "$(basename $0): error: \`$LINK_CONF' does not exist; creating it"
        echo > $LINK_CONF << EOF 'SOURCE_DIR=$HOME/etc
BACKUP_DIR=$SOURCE_DIR.bak

FILES=( )'
EOF
    fi

    source $LINK_CONF
    FSIZE=$(( ${#FILES[@]} / 2 ))
    declare -a ARG_FILES

    if [[ ! -d $SOURCE_DIR ]]; then
        echo >&2 "$(basename $0): error: \`$SOURCE_DIR' does not exist or not directory"
        exit 1
    elif (( ${#FILES[@]} % 2 != 0 )); then
        echo >&2 "$(basename $0): error: FILES array is missing a key or value"
        exit 1
    fi
}

get_value() {
    KEY=$1

    for (( i = 0; i < ${#FILES[@]}; i++ )); do
        if [[ $KEY == ${FILES[2 * $i]} ]]; then
            echo ${FILES[2 * $i + 1]}
            return 0
        fi
    done

    echo >&2 "$(basename $0): error: key \`$KEY' not found"
    return 1
}

backup() {
    if [[ -e $BACKUP_DIR && $FFLAG == 0 ]]; then
        echo >&2 "$(basename $0): error: backup directory already exists"
        exit 1
    else
        if [[ -e $BACKUP_DIR ]]; then
            rm -rf $BACKUP_DIR
        fi
        mkdir -v $BACKUP_DIR
    fi

    for (( i = 0; i < $FSIZE; i++ )); do
        # $SRC and $DST are reversed since we're backing up
        SRC=${FILES[2 * $i + 1]}
        DST=${FILES[2 * $i]}

        if [[ $(echo $DST | grep "/") && -e $SRC ]]; then
            mkdir -p $BACKUP_DIR/$(dirname $DST)
        fi
        if [[ -e $SRC ]]; then
            cp -vrd $SRC $BACKUP_DIR/$DST
        fi
    done
}

remove_parents() {
    SRC=$1
    DST=$2

    # use $SRC to keep track of how many directories to remove
    while [[ $(echo $SRC | grep "/") ]]; do
        SRC=$(dirname $SRC)
        DST=$(dirname $DST)
        if [[ -e $DST ]]; then
            rmdir -v $DST
        fi
    done
}

delete() {
    for (( i = 0; i < $FSIZE; i++ )); do
        if [[ $ALL == 1 ]]; then
            SRC=${FILES[2 * $i]}
            DST=${FILES[2 * $i + 1]}
        else
            SRC=${ARG_FILES[$i]}
            DST=$(get_value $SRC)
            if [[ $? == 1 ]]; then
                exit 1
            fi
        fi

        if [[ ! -e $DST ]]; then
            echo >&2 "$(basename $0): warning: file does not exist"
        elif [[ -L $DST || $FFLAG == 1 ]]; then
            rm -v $DST
            remove_parents $SRC $DST
        else
            echo >&2 "$(basename $0): warning: file not symlink; not removing"
        fi
    done
}

list() {
    LIGHT_RED=$(tput bold ; tput setaf 1)
    LIGHT_GREEN=$(tput bold ; tput setaf 2)
    LIGHT_BLUE=$(tput bold ; tput setaf 4)
    LIGHT_CYAN=$(tput bold ; tput setaf 6)
    RESET=$(tput sgr0)

    for (( i = 0; i < $FSIZE; i++ )); do
        if [[ $ALL == 1 ]]; then
            DST=${FILES[2 * $i + 1]}
        else
            DST=$(get_value ${ARG_FILES[$i]})
            if [[ $? == 1 ]]; then
                exit 1
            fi
        fi

        if [[ -L $DST ]]; then
            echo -e "[${LIGHT_CYAN}LINK${RESET}]\t$DST"
        elif [[ -f $DST ]]; then
            echo -e "[${LIGHT_GREEN}FILE${RESET}]\t$DST"
        elif [[ -d $DST ]]; then
            echo -e "[${LIGHT_BLUE}DIR ${RESET}]\t$DST"
        elif [[ ! -e $DST ]]; then
            echo -e "[${LIGHT_RED}NONE${RESET}]\t$DST"
        else
            echo -e "[OTHER]\t$DST"
        fi
    done
}

restore() {
    if [[ ! -d $BACKUP_DIR ]]; then
        echo >&2 "$(basename $0): error: backup directory does not exist"
        exit 1
    fi

    for (( i = 0; i < $FSIZE; i++ )); do
        if [[ $ALL == 1 ]]; then
            SRC=${FILES[2 * $i]}
            DST=${FILES[2 * $i + 1]}
        else
            SRC=${ARG_FILES[$i]}
            DST=$(get_value $SRC)
            if [[ $? == 1 ]]; then
                exit 1
            fi
        fi

        if [[ -e $DST ]]; then
            rm -rf $DST
        fi
        if [[ -e $BACKUP_DIR/$SRC ]]; then
            if [[ $(echo $SRC | grep "/") ]]; then
                mkdir -p $(dirname $DST)
            fi
            if [[ $ALL == 1 ]]; then
                mv -v $BACKUP_DIR/$SRC $DST
            else
                cp -Pv $BACKUP_DIR/$SRC $DST
            fi
        fi
        remove_parents $SRC $BACKUP_DIR/$SRC
    done

    if [[ $ALL == 1 ]]; then
        if [[ $(ls -A $BACKUP_DIR) ]]; then
            echo >&2 "$(basename $0): warning: backup directory not empty; not removing"
        else
            rmdir -v $BACKUP_DIR
        fi
    fi
}

write() {
    for (( i = 0; i < $FSIZE; i++ )); do
        if [[ $ALL == 1 ]]; then
            SRC=$SOURCE_DIR/${FILES[2 * $i]}
            DST=${FILES[2 * $i + 1]}
        else
            SRC=$SOURCE_DIR/${ARG_FILES[$i]}
            DST=$(get_value ${ARG_FILES[$i]})
            if [[ $? == 1 ]]; then
                exit 1
            fi
        fi

        if [[ ! -e $DST || $FFLAG == 1 ]]; then
            if [[ -e $DST ]]; then
                rm -rf $DST
            elif [[ $(echo $SRC | grep "/") ]]; then
                mkdir -p $(dirname $DST)
            fi
            ln -vfs $SRC $DST
        else
            echo >&2 "$(basename $0): warning: \`$DST' already exists"
        fi
    done
}

view_diff() {
    KEY=${ARG_FILES[0]}
    if [[ -z $KEY ]]; then
        echo >&2 "$(basename $0): error: option requires an argument"
        exit 1
    fi
    VALUE=$(get_value $KEY)
    if [[ $? == 1 ]]; then
        exit 1
    fi

    vimdiff $VALUE $SOURCE_DIR/$KEY
}

use_config() {
    if [[ -r $1 ]]; then
        LINK_CONF=$1
    else
        echo >&2 "$(basename $0): error: cannot read \`$1'"
        exit 1
    fi
}

usage() {
    echo -e >&2 << EOF "usage: $(basename $0) [-u file] [-b] [-f] [-d [files]] [-r [files]] [-w [files]] [-v file]
	-u  use alternate configuration file
	-b  backup existing files
	-d  delete symlinks
	-f  force removal of existing files
	-r  restore from backup
	-v  view diff
	-w  write symlinks

	-h  display this help and exit

note: files to be managed must be defined in configuration file"
EOF
    exit 1
}

# process flags
while getopts u:bdfhrvw OPT; do
    case "$OPT" in
        u)
            use_config "$OPTARG"
            ;;
        h|\?)
            usage
            ;;
        f)
            FFLAG=1
            ;;
        b)
            check_options && OPTIONS=1
            BFLAG=1
            ;;
        d)
            check_options && OPTIONS=1
            DFLAG=1
            ;;
        r)
            check_options && OPTIONS=1
            RFLAG=1
            ;;
        v)
            check_options && OPTIONS=1
            VFLAG=1
            ;;
        w)
            check_options && OPTIONS=1
            WFLAG=1
            ;;
    esac
done

check_link_conf
shift $(( $OPTIND - 1 ))
read_opt_args "$@"

if [[ $BFLAG == 1 ]]; then
    backup
elif [[ $DFLAG == 1 ]]; then
    delete
elif [[ $RFLAG == 1 ]]; then
    restore
elif [[ $VFLAG == 1 ]]; then
    view_diff
elif [[ $WFLAG == 1 ]]; then
    write
else
    list
fi
