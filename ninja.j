_ninja() 
{
	_usage() {
		cat <<EOF
ninja 
	driver 
		get
			src
		asset
			valid
		deploy
		transport
		build

EOF
	}

	_edit() {
		jsh invoke module edit ninja
	}

	_with() {
		_module() {
			local name=$1
			shift 1
			test -n "$name" || die "usage: with module {module}"

			if test -d "$GOPATH/src/github.com/ninjasphere/$name"; then
				d="$GOPATH/src/github.com/ninjasphere/$name"
			elif test -d "$GOPATH/src/github.com/ninjablocks/$name"; then
				d="$GOPATH/src/github.com/ninjablocks/$name"
			else
				die "$name does not apepar to be a Ninja module"
			fi
			cd "$d"
			if test $# -gt 0; then
				"$@"
			else
				exec bash --login
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


		  _transport()
		  {
		  		local name=$(_name $1)
		  		_assert valid $name

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


	jsh invoke "$@"
}