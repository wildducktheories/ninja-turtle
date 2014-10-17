_turtle()
{
	_usage() {
		cat <<EOF
turtle
	driver
		get
			src
			deploy-dir
		asset
			valid
		deploy
		transport
		arm-build
		installed-version
	devkit
		upgrade
		name
		ssh
		less
		tail
		bash
		stop
		start
	devhost
		up
		down
		status
	with
		module

EOF
	}

	_edit() {
		exec $(which jsh) module edit turtle
	}

	_view() {
		exec less $($(which jsh) module filename turtle)
	}

	_with() {
		_module() {
			local name=$1
			shift 1
			test -n "$name" || die "usage: with module {module}"

			m=$(_turtle module list | grep ${name}\$ | tail -1)
			test -n "$m" || die "$name is not a module"

			cd ${GOPATH}/src/$m
			if test $# -gt 0; then
				"$@"
			else
				exec bash --login
			fi
		}

		jsh invoke "$@"
	}

	_devhost()
	{
		_status() {
			pid=$(cat /tmp/sphere-validator.pid)
			if test -z "$pid" || ! ps -p "$pid" &>/dev/null; then
				status="stopped"
			else
				status="running"
			fi
			echo "sphere-validator $status $pid"
		}

		_up() {
			pid=$(cat /tmp/sphere-validator.pid)
			if test -z "$pid" || ! ps -p "$pid" &>/dev/null; then
				sphere-validator > /tmp/sphere-validator.log &
				echo $! > /tmp/sphere-validator.pid
				status="started"
			else
				status="running"
			fi
		}

		jsh invoke "$@"
	}

	_driver()
	{
		  _name()
		  {
		  		local name=${1:-${NINJA_DRIVER}}
		  		test -n "$name" || die "specify a driver or set NINJA_DRIVER"
		  		echo $name
		  }

		  _assert()
		  {
		  		_valid()
		  		{
		  			name=$(_name $1)
		  			test -d "$(_get src $name)" || die "$name is not a valid driver name"
		  		}
		  		jsh invoke "$@"
		  }

		  _get()
		  {
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

		  		jsh invoke "$@"
		  }

		  _deploy()
		  {
		  		local name=$(_name $1)
		  		local built="<not built>"
		  		local deployed="<not deployed>"
		  		built=$(_arm-build "$@") &&
		  		rsync -q $(_get src)/linux-arm/$name ninja@${DEVKIT_HOST:-my-devkit}:/tmp &&
		  		(_devkit bash <<EOF
sudo service spheramid stop;
sudo cp /tmp/$name $(_get deploy-dir "$@")/$name &&
${NINJA_CLEANLOGS:-true} &&
sudo service spheramid start
EOF
				) &&
		  		deployed=$(_get installed-version) &&
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
				cd $(_get src)
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
echo 'setInterval(function(){console.log("I SUCK")}, 60000)' | sudo tee /opt/ninjablocks/drivers/driver-chromecast/index.js
echo 'setInterval(function(){console.log("I SUCK")}, 60000)' | sudo tee /opt/ninjablocks/drivers/driver-chromecast/run.js
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
	}


	jsh invoke "$@"
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

	mkdir -p ~/.jsh/mnt/jsh/dist/0200-turtle/turtle &&
	ln -sf ../dist/0200-turtle/turtle ~/.jsh/mnt/jsh/resolved-packages &&
	test -f ~/.jsh/mnt/jsh/dist/0200-turtle/turtle/turtle.j || {
		mv "${BASH_SOURCE}" ~/.jsh/mnt/jsh/dist/0200-turtle/turtle &&
		echo "moved ${BASH_SOURCE} to ~/.jsh/mnt/jsh/dist/0200-turtle/turtle"
	} &&
	jsh installation link bin &&
	echo "turtle installation successful - type turtle for help" || "turtle installation failed."
fi
