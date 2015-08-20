_turtle()
{
	_usage() {
		${PAGER:-less} -f <(sed -e :a -e 's/^\( *\)\./\1 /' -e ta <<EOF
NAME
..turtle - the ninja turtle shell

SYNOPSIS
..turtle
....devkit
......upgrade - stop spheramid then do an apt-get update + dist-upgrade upgrade on the dev-kit
......name - the name of the dev-kit
......ssh - ssh to the dev-kkit
......less - less the specified dev-kit file or /var/log/ninjasphere.log
......tail - tail -f the specified dev-kit file or /var/log/ninjasphere.log
......bash - run bash on the dev-kit with the contents of stdin
......stop - stop the spheramid service
......start - start the spheramid service
....daemon
......config - list the development host daemon configuration
......up - bring up the specified daemon or all daemons
......down - take down the specified daemon or all daemons
......status - report the status of the specified daemon or all daemons
....driver
......src - print the src directory of the current driver
......deploy-dir - print the deployment directory for the current driver
......assert
........valid - assert that there is a current driver
......deploy - build and deploy the current driver to the dev-kit
......build - build the driver
......arm-build - do an arm build of the driver
......installed-version - report the md5sum of the installed version of the driver
....edit - edit the turtle scripts
....module
......name - the current module name
......dir - the current module directory
......org - the organization part of the current module's name
......host - the host part of the current module's name
......list - a list of modules in $GOPATH/src
....with
......module - change to the specified modules directory and run the specified command or start a new shell
......turtle - change to the turtle src directory and run the specified command or start a new shell
....view

INSTALLATION

Copy turtle.j into /tmp, then run:

..bash /tmp/turtle.j

NOTES

Works best if:
..* ~/bin is in your PATH
..* you have installed an ssh public key in the ~ninja/.ssh/authorized_keys file of your dev-kit
..* you have added :NOPASSWD to the ninja user in the sudoer's file
..* you have a ~/.sphere/remote.json file containing the mqtt.host and serial-override for your dev-kit

MORE INFO
..See http://github.com/ninjasphere/ninja-turtle

COPYRIGHT
..(c) 2014 - Ninja Blocks Inc.
EOF
)
	}

	_edit() {
		exec $(which jsh) module edit turtle
	}

	_view() {
		exec less $($(which jsh) module filename turtle)
	}

	_with() {
		_dispatch() {
			if test $# -gt 0; then
				"$@"
			else
				exec  bash --init-file <(
cat <<EOF
export TURTLE_DEPTH=$(expr ${TURTLE_DEPTH:-0} + 1);
export TURTLE_TITLE="$(basename $(pwd)) (\${TURTLE_DEPTH})"
export PS1="\\h:\\W \\u (\${TURTLE_DEPTH})\$ ";
turtle title
EOF
				)
			fi
		}

		_module() {
			local name=$1
			shift 1
			test -n "$name" || die "usage: with module {module}"

			m=$(_turtle module list | grep ${name}\$ | tail -1)
			test -n "$m" || die "$name is not a module"

			cd ${GOPATH}/src/$m

			rc=0
			(_dispatch "$@") || rc=1
			turtle title
			return $rc
		}

		__turtle() {
			cd $(dirname $($(which jsh) module filename turtle))
			rc=0
			(_dispatch "$@") || rc=1
			turtle title
			return $rc
		}

		case "$1" in
			turtle)
				shift 1
				set -- _turtle "$@"
			;;
			*)
			;;
		esac

		(jsh invoke "$@") || exit $?
	}

	_daemon() {
		_config() {
			cat <<EOF
sphere-validator,sphere-validator
mosquitto,mosquitto
godoc,godoc -http=:6060
EOF
		}

		_status() {
			local daemon=$1

			local status
			local pid

			pid=$(test -f /tmp/${daemon}.pid && cat /tmp/${daemon}.pid)
			pid=$(test -n "$pid" && ps -o pid= -p $pid)
			status=running

			test -n "$pid" || status=stopped
			echo $daemon $status $pid
		}

		_up() {
			local daemon=$1
			set -- $(_status "$daemon")
			local status=$2
			if test "$status" = "stopped"; then
				local launch=$(_config | grep ^$daemon, | cut -f2- -d,)
				test -n "$launch" || die "$daemon is not a known daemon"
				$launch &> /tmp/${daemon}.log &
				echo $! > /tmp/${daemon}.pid
			fi
			_status "$daemon"
		}

		_down() {
			local daemon=$1
			set -- $(_status "$daemon")
			local status=$2
			local pid=$3
			if test "$status" != "stopped"; then
				kill "$pid"
			fi
			_status "$daemon"
		}

		case $1 in
		up|down|status)
			if test -n "$2"; then
				jsh invoke "$@"
			else
				_config | cut -f1 -d, | while read daemon; do
					jsh invoke "$1" "$daemon"
				done
			fi
		;;
		*)
			jsh invoke "$@"
		;;
		esac

	}

	_nand() {
		_bash() {
			ssh -AT yoctobuilder@osbuilder01.ci.ninjablocks.co bash
		}

		_assert() {
			_in-yocto() {
				test "$(basename $(pwd))" = "yocto-meta-ninjasphere" ||  die "must be run from yocto-meta-ninjasphere"
			}
			jsh invoke "$@"
		}

		_get() {
			local file=$1
			test -n "$file" || die "usage: get {file}"
			localfile=/tmp/$(basename "$file")
			scp yoctobuilder@osbuilder01.ci.ninjablocks.co:${file} "${localfile}" 1>&2
			echo "$localfile"
		}

		_track() {

			_assert "in-yocto"
			local branch=${1:-$(git branch | sed -n "s/^* //p")}
			(cat <<EOF
cd ~/yocto_varsomam33/tisdk/sources/meta-ninjasphere &&
git fetch origin &&
git stash &&
git checkout -B $branch origin/$branch
EOF
) | _bash
		}

		_build() {
			_assert "in-yocto"
			git push origin $(git branch | sed -n "s/^* //p") &&
			(
				cat <<EOF
				set -x
. ~/.bashrc &&
cd ~/yocto_varsomam33/tisdk/sources/meta-ninjasphere &&
./yocto-helper.sh build-and-publish
EOF
)  | _bash 2>&1 | tee -a build.log
		}

		_sync() {
			_assert "in-yocto"
			git push origin $(git branch | sed -n "s/^* //p")
			(cat <<EOF
. ~/.bashrc &&
cd ~/yocto_varsomam33/tisdk/sources/meta-ninjasphere &&
git stash &&
git pull --rebase origin &&
git stash pop
EOF
) | _bash
		}

		_update() {
			local version=$1
			test -n "$version" || die "usage: turtle nand update {version}"
			(cat <<EOF
(
	. ~/.bashrc &&
	cd ~/yocto_varsomam33/tisdk/sources/meta-ninjasphere &&
	./yocto-helper.sh update-ninjasphere-factory-reset "$version"
) 1>&2
EOF
)  | _bash
			git pull --rebase origin

		}

		_build-shell() {
			ssh -At yoctobuilder@osbuilder01.ci.ninjablocks.co sh -c "'cd  ~/yocto_varsomam33/tisdk/sources/meta-ninjasphere && pwd && bash'"
		}

		jsh invoke "$@"

	}

	_driver()
	{
		_name()
		{
			local name=${1:-${TURTLE_DRIVER:-$(_module name)}}
			test -n "$name" || die "specify a driver or set TURTLE_DRIVER"
			echo $name
		}

		_assert()
		{
			_valid()
			{
				name=$(_name $1)
				test -d "$(_src $name)" || die "$name is not a valid driver name"
			}
			jsh invoke "$@"
		}

		_src()
		{
			local name=$(_name $1)
			echo $GOPATH/src/github.com/ninjasphere/$name
		}

		_deploy-dir()
		{
			local name=$(_name $1)
			echo /opt/ninjablocks/drivers/$name
		}

		_installed-version()
		{
			(_devkit ssh md5sum $(_deploy-dir "$@")/$(_name "$@") | cut -f1 -d' ')
		}

		_deploy()
		{
				local name=$(_name $1)
				local built="<not built>"
				local deployed="<not deployed>"
				built=$(_arm-build "$@") &&
				rsync -q $(_src)/linux-arm/$name ninja@${DEVKIT_HOST:-my-devkit}:/tmp &&
				(_devkit bash <<EOF
sudo service spheramid stop;
sudo cp /tmp/$name $(_deploy-dir "$@")/$name &&
${TURTLE_CLEANLOGS:-true} &&
sudo service spheramid start
EOF
				) &&
				deployed=$(_installed-version) &&
				test "$built" = "$deployed" || die "failed $built != $deployed"
				echo "ok - $built - $(date)" 1>&2
				echo "$built"
		}

		_install() {
			local name=$(_name $1)
			(_devkit bash <<EOF
sudo service spheramid stop
sudo apt-get update -y &&
sudo apt-get install -y "${name/driver-/ninja-}"
sudo service spheramid start
EOF
			)
		}

		_build()
		{
			local name=$(_name $1)
			_assert valid $name
			(
				cd $(_src)
				local out
				if test "${GOOS:-darwin}" == "darwin"; then
					out=bin
				else
					out=${GOOS}-${GOARCH}
					mkdir -p $out
				fi
				go build -o $out/$name
				md5sum < $out/$name | cut -f1 -d' '
			)
		}

		_arm-build()
		{
			GOOS=linux GOARCH=arm _build "$@"
		}

		jsh invoke "$@"
	}

	_devkit() {
		_name() {
			echo ${DEVKIT_HOST:-my-devkit}
		}

		_ssh() {
			ssh ninja@$(_name) "$@"
		}

		_tail() {
			ssh ninja@$(_name) tail -f "${1:-/var/log/ninjasphere.log}"
		}

		_less() {
			ssh -t ninja@$(_name) less -F "${1:-/var/log/ninjasphere.log}"
		}

		_stop() {
			_bash <<EOF
sudo service spheramid stop
EOF
		}

		_start() {
			_bash <<EOF
sudo service spheramid start
EOF
		}

		_upgrade() {
			_bash <<EOF
sudo service spheramid stop
sudo apt-get update -y &&
sudo apt-get dist-upgrade -y
sudo service spheramid start
EOF
		}

		_bash() {
			if test $# -gt 0; then
			ssh -T ninja@$(_name) bash <<EOF
export PATH=/opt/ninjablocks/bin:\$PATH
$@
EOF
			else (
cat <<EOF
export PATH=/opt/ninjablocks/bin:\$PATH
EOF
cat
				) | ssh -T ninja@$(_name) bash
			fi
		}

		jsh invoke "$@"
	}

	_title() {
		local title=$1
		if test -z "$title"; then
			title="${TURTLE_TITLE}"
		fi
		echo -n -e "\033]0;$title\007"
	}

	_factory-test()
	{
		_deploy() {
			make arm-build &&
			COPYFILE_DISABLE=1 tar -czLvf sphere-factory-test-adhoc.tgz bin/json bin/sphere-io scripts/login.sh scripts/test-controller.sh images/*.png &&
			scp sphere-factory-test-adhoc.tgz ninja@${DEVKIT_HOST:-my-devkit}:/tmp &&
			(_devkit bash <<EOF
cd /opt/ninjablocks/sphere-factory-test
gzip -dc /tmp/sphere-factory-test-adhoc.tgz | sudo tar -xvf -
EOF
			)
		}

		_update-debian-packages() {
			_devkit bash <<EOF
sudo apt-get update -y && sudo apt-get install -d ninjasphere-factory-test
EOF
 			rsync ninja@${DEVKIT_HOST:-my-devkit}:/var/cache/apt/archives/ninjasphere-factory-test_*.deb $GOPATH/src/github.com/ninjasphere/sphere-factory-test/installer/
		}


		jsh invoke "$@"
	}

	_check() {

		_errcodes() {
			output=$(sed -n "s/.*\(ERR[0-9]*:\).*/\1/p" | uniq -d)
			test -z "$output" || die "duplicate error codes detected"
		}

		jsh invoke "$@"
	}

	_loop() {
		_sphere-usb() {
			_title usb
			while true; do screen /dev/${SPHERE_USB:-$(basename $(ls -d /dev/tty.usbm* | sort | tail -1))} ; reset; sleep 5; done
		}

		_sphere-usb2() {
			_title usb2
			while true; do screen /dev/${SPHERE_USB2:-tty.usbmodem1412} ; reset; sleep 5; done
		}
		_sphere-ftdi() {
			_title ftdi
			while true; do screen -L /dev/${SPHERE_FTDI:-$(basename $(ls -d /dev/tty.usbserial* | sort | tail -1))} 115200 ; reset; sleep 5; done
		}

		_sphere-ssh() {
			_title sphere
			while ! ssh -At ninja@${SPHERE_IP:-10.0.1.164}; do sleep 5; done
		}

		_odroid() {
			_title odroid
			while ! ssh -At ${ODROID_USER:-jon}@odroid; do sleep 5; done
		}

		_packager() {
			_title packager
			while ! ssh -At ${PACKAGER_USER:-jonseymour}@buildbox-amd64-sfo-agent1.ci.ninjablocks.co; do sleep 5; done
		}

		_image-build() {
			_title image-build
			# 212.47.239.20
			#212.47.239.153
			#212.47.232.48
			while ! ssh -At ${IMAGE_BUILD_USER:-root}@212.47.232.48; do sleep 5; done
		}

		jsh invoke "$@"
	}

	_sdcard() {
		_reimage() {
			local disk=$1
			test -b "$disk" || die "$disk is not a block device"
			test "$disk" != "/dev/disk0" || die "I will not nuke disk0, ok?!"

			diskutil list $disk | grep "Apple" && die "I am not going to delete an Apple disk, ok?"

			image=${NINJA_IMAGE:-~/ninja/images/factory-build/ubuntu_armhf_trusty_norelease_sphere-unstable.img.gz} &&
			test -f "$image" || die "No image. To fix: export NINJA_IMAGE={your-image-name};" &&
			shortdisk=$(basename $disk) &&
			diskutil unmountDisk "$shortdisk" &&
			gzip -dc "${image}" | sudo dd of=/dev/r${shortdisk} bs=16m
			diskutil unmountDisk "$shortdisk"
		}

		jsh invoke "$@"
	}

	_fetch-firmware() {
		local repo=${1:-unstable}
		cd ${NINJA_IMAGES:-/Volumes/data/ninja/firmware/latest} &&
		prefix=${NINJA_PREFIX:-http://firmware.sphere.ninja/latest} &&
		image=ubuntu_armhf_trusty_norelease_sphere-${repo} &&
		echo "fetching manifest..." 1>&2
		curl -s -O ${prefix}/${image}.manifest &&
		echo "manifest downloaded." &&
		(
			cat ${image}.manifest | grep "\\-recovery"
			cat ${image}.manifest | grep -v "\\-recovery"
		) | while read sha1 file; do
			echo -n "fetching ${prefix}/${file}..."
			test -f "$file" && test "$(sha1sum < "${file}" | cut -f1 -d' ')" = "$sha1" && echo "available - $(echo "$sha1" | cut -c1-8)" ||
			if curl -s -O ${prefix}/${file}
				echo -n "$downloaded..." &&
				test "$(sha1sum < "${file}" | cut -f1 -d' ')" = "$sha1"; then
				echo "ok - $(echo $sha1 | cut -c1-8)"
			else
				echo "failed"
			fi
		done
	}

	_fetch-package() {
		local package=$1
		test -n "$package" || die "usage: fetch-package {package}"

		for repo in http://ports.ubuntu.com/dists/trusty/main https://s3.amazonaws.com/ninjablocks-apt-repo/dists/trusty-spheramid-unstable/main http://s3.amazonaws.com/ninja-partialverse-repo/dists/partialverse/main; do
			file=$(
				echo $repo 1>&2 &&
				echo $(dirname $(dirname $(dirname $repo))) 1>&2 &&
				curl -s $repo/binary-armhf/Packages.gz  |
				gzip -dc  |
				sed -n "s/^Filename: //p" |
				grep /${package}_*
			)
			if test -n "$file"; then
				echo $(dirname $(dirname $(dirname $repo)))/$file
				if curl -O $(dirname $(dirname $(dirname $repo)))/$file &&
					test -f $(basename "$file"); then
					echo "$(basename "$file")"
				fi
			fi
		done
	}

	_fetch-packages() {

		local repo=${1:-unstable}
		curl -s https://s3.amazonaws.com/ninjablocks-apt-repo/dists/trusty-spheramid-${repo}/main/binary-armhf/Packages.gz | gzip -dc
	}

	_promoteable() {
		local from=$1
		local to=$2
		_fetch-packages $from > /tmp/from.$$
		_fetch-packages $to > /tmp/to.$$
		trap "rm /tmp/to.$$ && rm /tmp/from.$$" EXIT
		diff -u /tmp/from.$$ /tmp/to.$$ | grep "^+Filename:" | cut -f2 -d' ' | cut -f4 -d'/'
	}

	_module() {
		_list() {
			find $GOPATH/src -mindepth 3 -maxdepth 3 -type d | while read d
			do
				echo ${d#${GOPATH%/}/src/}
			done
		}

		_host() {
			echo $2
		}

		_org() {
			echo $3
		}

		_name() {
			echo $4
		}

		_dir() {
			echo $GOPATH/$1/$2/$3/$4
		}

		case "$1" in
			list)
				jsh invoke "$@"
				return $?
			;;
			*)
				local pwd=$(pwd)
				local relative=${pwd#${GOPATH%/}/}
				if test "$relative" != $pwd; then
					cmd=$1
					set -- ${relative//\// }
					if test $# -ge 4 && test $1 = "src"; then
						jsh invoke $cmd "$@"
						return $?
					fi
				fi
				die "$(pwd) is not in a module directory"
			;;
		esac
	}

	jsh invoke "$@"
}

_discuss() {
# {
#   "action_type": 5,
#   "created_at": "2015-01-13T05:22:39.080Z",
#   "excerpt": "G&#39;day David, \n\nFor the moment, the best way to formally report an issue with a Ninja Sphere is to send an email to support@ninjablocks.com. Over time, we will refine our support processes to improve the visibility of known issues to the community at large. \n\nRegards, \n\njon seymour.",
#   "avatar_template": "/user_avatar/discuss.ninjablocks.com/jon_seymour/{size}/906.png",
#   "acting_avatar_template": "/user_avatar/discuss.ninjablocks.com/jon_seymour/{size}/906.png",
#   "slug": "reporting-bugs-best-place-for-it",
#   "topic_id": 2845,
#   "target_user_id": 7036,
#   "target_name": "Jon Seymour",
#   "target_username": "Jon_Seymour",
#   "post_number": 2,
#   "post_id": 16188,
#   "reply_to_post_number": null,
#   "username": "Jon_Seymour",
#   "name": "Jon Seymour",
#   "user_id": 7036,
#   "acting_username": "Jon_Seymour",
#   "acting_name": "Jon Seymour",
#   "acting_user_id": 7036,
#   "title": "Reporting bugs - Best place for it?",
#   "deleted": false,
#   "hidden": false,
#   "moderator_action": false,
#   "category_id": 23,
#   "uploaded_avatar_id": 906,
#   "acting_uploaded_avatar_id": 906
# }


	_article-summaries-by-user() {
		user=$1
		max=$2
		offset=0
		while test $offset -lt $max; do
			curl -s "https://discuss.ninjablocks.com/user_actions.json?offset=$offset&username=$user&filter=5" | jq  -r '.user_actions[]|[.created_at,.excerpt,.slug,.topic_id,.post_number,.post_id,.title]|map(tostring)|[., "https://discuss.ninjablocks.com/t/"+.[2]+"/"+.[3]+"/"+.[4]]|flatten|@csv'
			let offset=offset+60
		done
	}

	jsh invoke "$@"
}

_git() {
	_simple-log() {
		git shortlog "$@" | sed -n "s/^  *//p"
	}
	jsh invoke "$@"
}

_promote() {
	local id=$1
	local thingType=$2
	local room=$3
	test -n "$room" || die "usage: promote {id} {thingType} {room-id}"
	test -n "$SPHERE_IP" || die "must defined SPHERE_IP"
	thing=$(curl -s http://${SPHERE_IP}:8000/rest/v1/things/$id | jq ".data|.promoted=true|.type=\"${thingType}\"")
	echo "$thing" | curl -s -d @- -XPUT "http://${SPHERE_IP}:8000/rest/v1/things/$id"
	curl -s -d "{\"id\": \"$room\"}" -XPUT "http://${SPHERE_IP}:8000/rest/v1/things/$id/location"
}


_create-room() {
	local type=$1
	shift 1
	local name="$*"
	test -n "$name" || die "usage: create-room type name"
	test -n "$SPHERE_IP" || die "must defined SPHERE_IP"
	output=$(curl -s -d "{\"name\":\"$name\", \"type\":\"$type\"}" -XPOST "http://${SPHERE_IP}:8000/rest/v1/rooms")
	echo "$output" | jq -r '.data.id'
}

if test "$(type -t "_jsh")" != "function"; then
	die() {
		echo "$*" 1>&2
		exit 1
	}

	export PATH=~/bin:$PATH &&
	mkdir -p ~/bin

	if ! test -d ~/.jsh; then
		git clone https://github.com/wildducktheories/jsh-installation.git ~/.jsh &&
		pushd ~/.jsh &&
		git submodule update --init --recursive &&
		mnt/jsh/resolved-packages/jsh/bin/j.sh jsh installation init ~/bin &&
		popd &&
		echo "jsh installed - see https://github.com/wildducktheories/jsh for more details." || die "jsh installation failed."
	fi

	mkdir -p ~/.jsh/mnt/jsh/dist/0200-turtle &&
	pushd ~/.jsh/mnt/jsh/dist/0200-turtle &&
	test -d turtle || git clone https://github.com/wildducktheories/ninja-turtle.git turtle &&
	popd &&
	ln -sf ../dist/0200-turtle/turtle ~/.jsh/mnt/jsh/resolved-packages &&
	jsh installation link bin &&
	echo "turtle installation successful - type turtle for help" || die "turtle installation failed."
fi
