#!/usr/bin/env shpec
# See Also: https://github.com/rylnd/shpec

_has_pty_session_man() { [ ${#_pty_session_impl} -gt 0 ]; }

_restore_on_exit=
# List of file paths in the form: <backup>|<original>:...
# The backup paths are moved to the original path.

_on_exit() {
  IFS=:
  for file in ${_restore_on_exit}
  do [ ${#file} -gt 0 ] && mv -f "${file%|*}" "${file#*|}"
  done
  for file in ${_delete_on_exit}
  do [ ${#file} -gt 0 ] && rm -rf "${file}"
  done
}

_pty_session_init() {
  _pty_session_impl=
  if abduco -v | grep -q 'abduco.*Marc André Tanner'
  then
    export ABDUCO_SOCKET_DIR="${_tmpdir}"
    export _pty_session_impl=abduco
    export _pty_session="abduco -n moe_shpec"
  else
    echo "Failed to find a pty session manager. Many tests won't be run without one."
  fi
}

_tmpdir="$(mktemp -d \"$(printf \"${PWD}\" | cksum | cut -d ' ' -f 1).XXXXXX\")"

# List of file paths to delete in the form: <path>:...
_delete_on_exit="${_tmpdir}"

trap _on_exit 0 # EXIT
_pty_session_init


describe "moe is an editor"

    describe "invocation options"

        it "can display it's version"
            assert equal `moe -v | grep -oPq "^moe v\d+\.\d+\.\d+$";echo $?` 0
        end

        it "can display command line options"
            # TODO: Expand this test to include verifying the option list is formatted and localized correctly.
            assert egrep "`moe --help`" " *moe \[file\] +Edit file.*"
        end

_has_pty_session_man && {
        it "can load a config file from ~/.config/moe/moerc.toml"
            configDir=~/.config/moe
            config=${configDir}/moerc.toml
            if [ ! -d "${configDir}" ]
            then
                mkdir -p ~/.config/moe
                _delete_on_exit="${_delete_on_exit}:${configDir}"
            fi
            if [ -e "${config}" ]
            then
                mv "${config}" "${config}.orig"
                _restore_on_exit="${_restore_on_exit}:${config}.orig|${config}"
            else
                _delete_on_exit="${_delete_on_exit}:${config}"
            fi
            cp -f example/moerc.toml "${configDir}/"
            ${_pty_session} moe
        end
}

    end

end
