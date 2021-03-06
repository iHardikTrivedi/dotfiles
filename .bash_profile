# Load the shell dotfiles, and then some:
# * ~/.path can be used to extend `$PATH`.
for file in ~/.{aliases,bash_prompt,exports}; do
  [ -r "${file}" ] && [ -f "${file}" ] && source "${file}"
done;
unset file;

# Load the z binary.
. `brew --prefix`/etc/profile.d/z.sh

# Case-insensitive globbing (used in pathname expansion).
shopt -s nocaseglob;

# Append to the Bash history file, rather than overwriting it.
shopt -s histappend;

# Autocorrect typos in path names when using `cd`.
shopt -s cdspell;

# Enable tab completion for many Bash commands.
if which brew > /dev/null && [ -f "$(brew --prefix)/share/bash-completion/bash_completion" ]; then
  source "$(brew --prefix)/share/bash-completion/bash_completion";
elif [ -f /etc/bash_completion ]; then
  source /etc/bash_completion;
fi;

# Enable tab completion for `g` by marking it as an alias for `git`.
if type _git &> /dev/null && [ -f /usr/local/etc/bash_completion.d/git-completion.bash ]; then
  complete -o default -o nospace -F _git g;
fi;

# Setup gpg-agent automatically for every shell.
if test -f ~/.gnupg/.gpg-agent-info -a -n "$(pgrep gpg-agent)"; then
  source ~/.gnupg/.gpg-agent-info
  export GPG_AGENT_INFO
  GPG_TTY=$(tty)
  export GPG_TTY
else
  eval $(gpg-agent --daemon ~/.gnupg/.gpg-agent-info)
fi

# Add tab completion for `defaults read|write NSGlobalDomain`.
# You could just use `-g` instead, but I like being explicit.
complete -W "NSGlobalDomain" defaults;
