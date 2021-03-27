#!/bin/sh

CHECKOUT_DIR=data
PRIVATE_DIR='.PRIVATE'

#--------------------------- install tools  ---------------------------

ROOT_DIR=$(cd $(dirname "$0"); pwd)
GROUP=$(id -gn)
is_ubuntu() { uname -a | grep -iq ubuntu; }
cmd_exists() { type "$(which "$1")" > /dev/null 2>&1; }

if is_ubuntu; then
	if ! cmd_exists 'git'; then
		sudo apt install -y git vim
	fi
	if ! cmd_exists 'encfs'; then
		sudo apt install encfs
	fi
else
	if ! cmd_exists 'brew'; then
		bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
		brew update
		brew tap homebrew/cask-cask
	fi

	if ! cmd_exists 'vim'; then
		brew update
		brew install git vim
	fi
	if ! cmd_exists 'encfs'; then
		brew install --cask osxfuse
		brew install encfs
	fi
fi

#--------------------------- update repo  ---------------------------

if [ "$1" = 'update' ]; then
	GIT_PUSH_DEFAULT=simple

	#---------------------------------------------------------------------
	# pull

	cd $ROOT_DIR
	IFS=; pull_result=$(git pull)

	if echo $pull_result | grep -q 'insufficient permission for adding an object'; then
		sudo chown -R $USER:$GROUP "$(git rev-parse --show-toplevel)/.git"
	fi

	if echo $pull_result | grep -q 'use "git push" to publish your local commits'; then
		git push
		exit
	fi

	echo ${pull_result}

	#---------------------------------------------------------------------
	# config


	push=$(git config --local --get push.default)
	if [ -z $push ]; then
		[ -z $GIT_PUSH_DEFAULT ] && read -p 'Input push branch( simple/matching ): ' GIT_PUSH_DEFAULT
		git config --local --add push.default $GIT_PUSH_DEFAULT
	fi

	gituser=$(git config --local --get user.gituser)
	if [ -z $gituser ]; then
		[ -z $GIT_PUSH_USER ] && read -p 'Input your GitHub username: ' GIT_PUSH_USER
		[ -z $GIT_PUSH_USER ] && exit 1
		git config --local --add user.name $GIT_PUSH_USER
	       	git config --local --add user.email $GIT_PUSH_USER@github.com
	       	git config --local --add user.gituser $GIT_PUSH_USER
		gituser=$GIT_PUSH_USER
	fi

	push_url=$(git remote get-url --push origin)

	if ! echo $push_url | grep -q "${gituser}@"; then
		new_url=$(echo $push_url | sed -e "s/\/\//\/\/${gituser}@/g")
		git remote set-url origin $new_url
		echo "${Green}Update remote url: $new_url.${Color_Off}"
	fi

	#---------------------------------------------------------------------
	# add

	cd $ROOT_DIR
	IFS=; add_result=$(git add .)

	if echo $add_result | grep -q 'insufficient permission'; then
		echo "${Green}Permission error.${Color_Off}"
		sudo chown -R $USER:$GROUP $ROOT_DIR
		git add .
	fi

	#---------------------------------------------------------------------
	# commit

	input_msg=$1
	input_msg=${input_msg:="update"}
	IFS=; commit_result=$(git commit -m "${input_msg}")

	if echo $commit_result | grep -q 'nothing to commit'; then
		echo "${Green}Nothing to commit.${Color_Off}"
		exit
	fi

	echo ${commit_result}

	#---------------------------------------------------------------------
	# push

	git config --local credential.helper 'cache --timeout 21600'
	git push
	exit
fi


#--------------------------- checkout  ---------------------------

source_dir=$ROOT_DIR/$PRIVATE_DIR
checkout_dir=$ROOT_DIR/$CHECKOUT_DIR

#if [ $(whoami) != 'root' ]; then
#    echo "CHECKOUT should be executed as root or with sudo:"
#    echo "	sudo sh $ORIARGS "
#    exit 1
#fi

if [ "$1" = 'pass' ]; then
    GIT_URL=$(git remote get-url --push origin)
	ECRYPTFS_PASS=$(git config --local --get user.checkpass)
	echo "github: $GIT_URL"
	echo "mypass: $ECRYPTFS_PASS"
	exit 0
fi

if [ "$1" = 'close' ]; then
	umount $checkout_dir
	exit 0
fi

if [ "$1" = 'help' ]; then
	cat $ROOT_DIR/README.md
	exit 0
fi

if [ ! -z "$(ls -A ${checkout_dir} 2>/dev/null)" ]; then
	#encfs --unmount $checkout_dir
	echo "maybe already mounted."
	exit 0
fi

mkdir -p $source_dir
mkdir -p $checkout_dir

ignoreFile="$ROOT_DIR/.gitignore"
if [ ! -f $ignoreFile ]; then
	touch $ignoreFile
fi
if ! grep -iq "$CHECKOUT_DIR" $ignoreFile; then
	echo "${CHECKOUT_DIR}\n$(cat "$ignoreFile")" > "$ignoreFile"
	echo '*.swp' >> "$ignoreFile"
	echo '*.swo' >> "$ignoreFile"
fi


ECRYPTFS_PASS=$(git config --local --get user.checkpass)
if [ -z $ECRYPTFS_PASS ]; then
	[ -z $ECRYPTFS_PASS ] && read -p 'Input your encfs PASSWORD: ' ECRYPTFS_PASS
	if ! test $ECRYPTFS_PASS; then
		echo "Error exit, password must be set."
		exit
	fi
	git config --local --add user.checkpass $ECRYPTFS_PASS
fi

echo "source: $source_dir"
echo "checkout: $checkout_dir"

echo "$ECRYPTFS_PASS" | encfs --standard --stdinpass "$source_dir" "$checkout_dir"
chown -R $USER:$GROUP "$checkout_dir"

if [ -z "$(ls -A ${checkout_dir})" ]; then
	echo 'target dir is empty'
fi
