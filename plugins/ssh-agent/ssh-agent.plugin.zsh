#
# INSTRUCTIONS
#
#   To enable agent forwarding support add the following to
#   your .zshrc file:
#
#     zstyle :omz:plugins:ssh-agent agent-forwarding on
#
#   To load multiple identities use the identities style, For
#   example:
#
#     zstyle :omz:plugins:ssh-agent identities id_rsa id_rsa2 id_github
#
#   To set the maximum lifetime of the identities, use the
#   lifetime style. The lifetime may be specified in seconds
#   or as described in sshd_config(5) (see TIME FORMATS)
#   If left unspecified, the default lifetime is forever.
#
#     zstyle :omz:plugins:ssh-agent lifetime 4h
#
# CREDITS
#
#   Based on code from Joseph M. Reagle
#   http://www.cygwin.com/ml/cygwin/2001-06/msg00537.html
#
#   Agent forwarding support based on ideas from
#   Florent Thoumie and Jonas Pfenniger
#

local _plugin__ssh_env
local _plugin__forwarding

# This function is intended to be portable by OS.  This works by creating a
# shadow directory ("${file}.lock"), then declaring an trap that removes the
# directory.  The remainder of the arguments specify the action to be
# executed while the lock is held.  This function declares that its traps
# are local, and therefore do not interfere with other traps.
function _plugin__with_lockfile()
{
  local file="$1"

  shift
  setopt localtraps

  while :; do
    mkdir "${file}.lock" 2>/dev/null && break
    sleep 0.1
  done
  trap "rm -rf ${file}.lock" EXIT INT QUIT ABRT TERM
  $*
}

function _plugin__start_agent()
{
  local -a identities
  local lifetime
  zstyle -s :omz:plugins:ssh-agent lifetime lifetime

  # start ssh-agent and setup environment
  /usr/bin/env ssh-agent ${lifetime:+-t} ${lifetime} | sed 's/^echo/#echo/' >! ${_plugin__ssh_env}
  chmod 600 ${_plugin__ssh_env}
  . ${_plugin__ssh_env} > /dev/null

  # load identies
  zstyle -a :omz:plugins:ssh-agent identities identities
  echo starting ssh-agent...

  /usr/bin/ssh-add $HOME/.ssh/${^identities}
}

function _plugin__run()
{
  # Get the filename to store/lookup the environment from
  if (( $+commands[scutil] )); then
    # It's OS X!
    _plugin__ssh_env="$HOME/.ssh/environment-$(scutil --get ComputerName)"
  else
    _plugin__ssh_env="$HOME/.ssh/environment-$HOST"
  fi

  # test if agent-forwarding is enabled
  zstyle -b :omz:plugins:ssh-agent agent-forwarding _plugin__forwarding
  if [[ ${_plugin__forwarding} == "yes" && -n "$SSH_AUTH_SOCK" ]]; then
    # Add a nifty symlink for screen/tmux if agent forwarding
    [[ -L $SSH_AUTH_SOCK ]] || ln -sf "$SSH_AUTH_SOCK" /tmp/ssh-agent-$USER-screen

  elif [ -f "${_plugin__ssh_env}" ]; then
    # Source SSH settings, if applicable
    . ${_plugin__ssh_env} > /dev/null
    ps x | grep ${SSH_AGENT_PID} | grep ssh-agent > /dev/null || {
      _plugin__start_agent;
    }
  else
    _plugin__start_agent;
  fi
}

_plugin__with_lockfile "$HOME/.ssh/omz-start-agent" _plugin__run

# tidy up after ourselves
unfunction _plugin__with_lockfile
unfunction _plugin__start_agent
unfunction _plugin__run
unset _plugin__forwarding
unset _plugin__ssh_env

