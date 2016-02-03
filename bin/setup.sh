#!/bin/bash
#/ Usage: bin/strap.sh [--debug]
#/ Install development dependencies on Mac OS X.
set -e

[ "$1" = "--debug" ] && STRAP_DEBUG="1"

if [ -n "$STRAP_DEBUG" ]; then
  set -x
else
  STRAP_QUIET_FLAG="-q"
  Q="$STRAP_QUIET_FLAG"
fi

STDIN_FILE_DESCRIPTOR="0"
[ -t "$STDIN_FILE_DESCRIPTOR" ] && STRAP_INTERACTIVE="1"

abort() { echo "!!! $@" >&2; exit 1; }
log()   { echo "--> $@"; }
logn()  { printf -- "--> $@ "; }
logk()  { echo "OK"; }

NAME="Vincent Klaiber"
EMAIL="vincentklaiber@gmail.com"

sw_vers -productVersion | grep $Q -E "^10.(10|11)" || {
  abort "Run Strap on Mac OS X 10.10/11."
}

[ "$USER" = "root" ] && abort "Run Strap as yourself, not root."
groups | grep $Q admin || abort "Add $USER to the admin group."

# Initialise sudo now to save prompting later.
log "Enter your password (for sudo access):"
sudo -k
sudo /usr/bin/true
logk

# Set computer name (as done via System Preferences → Sharing)
logn "Set computer name to Valhall:"
sudo scutil --set ComputerName "Valhall"
sudo scutil --set HostName "Valhall"
sudo scutil --set LocalHostName "Valhall"
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "Valhall"
logk

# Install the Xcode Command Line Tools if Xcode isn't installed.
DEVELOPER_DIR=$("xcode-select" -print-path 2>/dev/null || true)
[ -z "$DEVELOPER_DIR" ] || ! [ -f "$DEVELOPER_DIR/usr/bin/git" ] && {
  log "Installing the Xcode Command Line Tools:"
  CLT_PLACEHOLDER="/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  sudo touch "$CLT_PLACEHOLDER"
  CLT_PACKAGE=$(softwareupdate -l | \
                grep -B 1 -E "Command Line (Developer|Tools)" | \
                awk -F"*" '/^ +\*/ {print $2}' | sed 's/^ *//' | head -n1)
  sudo softwareupdate -i "$CLT_PACKAGE"
  sudo rm -f "$CLT_PLACEHOLDER"
  logk
}

# Check if the Xcode license is agreed to and agree if not.
/usr/bin/xcrun clang 2>&1 | grep $Q license && {
  if [ -n "$STRAP_INTERACTIVE" ]; then
    logn "Asking for Xcode license confirmation:"
    sudo xcodebuild -license
    logk
  else
    abort 'Run `sudo xcodebuild -license` to agree to the Xcode license.'
  fi
}

# Setup Homebrew directories and permissions.
logn "Installing Homebrew:"
HOMEBREW_PREFIX="/usr/local"
HOMEBREW_CACHE="/Library/Caches/Homebrew"
for dir in "$HOMEBREW_PREFIX" "$HOMEBREW_CACHE"; do
  [ -d "$dir" ] || sudo mkdir -p "$dir"
  sudo chown -R $USER:admin "$dir"
done

# Download Homebrew.
export GIT_DIR="$HOMEBREW_PREFIX/.git" GIT_WORK_TREE="$HOMEBREW_PREFIX"
git init $Q
git config remote.origin.url "https://github.com/Homebrew/homebrew"
git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
git rev-parse --verify --quiet origin/master >/dev/null || {
  git fetch $Q origin master:refs/remotes/origin/master --no-tags --depth=1
  git reset $Q --hard origin/master
}
sudo chmod g+rwx "$HOMEBREW_PREFIX"/* "$HOMEBREW_PREFIX"/.??*
unset GIT_DIR GIT_WORK_TREE
logk

# Install Homebrew Bundle, Cask and Versions tap.
log "Installing Homebrew taps and extensions:"
export PATH="$HOMEBREW_PREFIX/bin:$PATH"
brew update
brew tap | grep -i $Q Homebrew/bundle || brew tap Homebrew/bundle
cat > /tmp/Brewfile.strap <<EOF
tap 'caskroom/cask'
tap 'caskroom/versions'
tap 'homebrew/versions'
tap 'homebrew/php'
EOF
brew bundle --file=/tmp/Brewfile.strap
rm -f /tmp/Brewfile.strap
logk

# Set some basic security settings.
logn "Configuring security settings:"
defaults write com.apple.Safari \
  com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabled \
  -bool false
defaults write com.apple.Safari \
  com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabledForLocalFiles \
  -bool false
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0
sudo defaults write /Library/Preferences/com.apple.alf globalstate -int 1

if [ -n "$NAME" ] && [ -n "$EMAIL" ]; then
  sudo defaults write /Library/Preferences/com.apple.loginwindow \
    LoginwindowText \
    "Found this computer? Please contact $NAME at $EMAIL."
fi
logk

# Check and enable full-disk encryption.
logn "Checking full-disk encryption status:"
if fdesetup status | grep $Q -E "FileVault is (On|Off, but will be enabled after the next restart)."; then
  logk
elif [ -n "$STRAP_CI" ]; then
  echo
  logn "Skipping full-disk encryption for CI"
elif [ -n "$STRAP_INTERACTIVE" ]; then
  echo
  logn "Enabling full-disk encryption on next reboot:"
  sudo fdesetup enable -user "$USER" \
    | tee ~/Desktop/"FileVault Recovery Key.txt"
  logk
else
  echo
  abort 'Run `sudo fdesetup enable -user "$USER"` to enable full-disk encryption.'
fi

# Check and install any remaining software updates.
logn "Checking for software updates:"
if softwareupdate -l 2>&1 | grep $Q "No new software available."; then
  logk
else
  echo
  log "Installing software updates:"
  if [ -z "$STRAP_CI" ]; then
    sudo softwareupdate --install --all
  else
    echo "Skipping software updates for CI"
  fi
  logk
fi

# Install latest version of Bash.
logn "Install latest version of Bash:"
brew install bash
if [ -z "$STRAP_CI" ]; then
  sudo bash -c 'echo /usr/local/bin/bash >> /etc/shells'
  chsh -s /usr/local/bin/bash
else
  echo "Skipping updating shells for CI"
fi
logk

logn "Installing binaries:"
cat > /tmp/Brewfile.strap <<EOF
brew 'aria2'
brew 'git'
brew 'gnu-sed', args: ['with-default-names']
brew 'homebrew/versions/bash-completion2'
brew 'hub'
brew 'node'
brew 'rename'
brew 'ssh-copy-id'
brew 'wget'
brew 'z'
EOF
brew bundle --file=/tmp/Brewfile.strap
rm -f /tmp/Brewfile.strap
logk

logn "Installing latest version of NPM:"
npm install -g npm@latest
logk

logn "Installing PHP:"
brew install homebrew/php/php70
sed -i".bak" "s/^\;phar.readonly.*$/phar.readonly = Off/g" /usr/local/etc/php/7.0/php.ini
sed -i "s/memory_limit = .*/memory_limit = -1/" /usr/local/etc/php/7.0/php.ini
if [ -z "$STRAP_CI" ]; then
  brew install homebrew/php/composer
  brew install homebrew/php/php-cs-fixer
else
  echo "Skipping installing composer and php-cs-fixer for CI"
fi
logk

logn "Installing Mac applications:"
export HOMEBREW_CASK_OPTS="--appdir=/Applications";
cat > /tmp/Caskfile.strap <<EOF
cask '1password'
cask 'adobe-creative-cloud'
cask 'appcleaner'
cask 'atom'
cask 'caskroom/versions/sketch-beta'
cask 'couleurs'
cask 'dropbox'
cask 'firefox'
cask 'flux'
cask 'github-desktop'
cask 'google-chrome'
cask 'imagealpha'
cask 'imageoptim'
cask 'java'
cask 'jumpshare'
cask 'phpstorm'
cask 'qlimagesize'
cask 'qlstephen'
cask 'sequel-pro'
cask 'skype'
cask 'slack'
cask 'spectacle'
cask 'spotify'
cask 'steam'
cask 'transmit'
cask 'vagrant'
cask 'virtualbox'
cask 'vlc'
EOF
brew bundle --file=/tmp/Caskfile.strap
rm -f /tmp/Caskfile.strap
logk

# Create Sites directory in user folder.
logn "Create Sites directory in user folder:"
mkdir ~/Sites
logk

# Setup prefered OS X settings.
logn "Setup prefered OS X settings:"

# Menu bar: Always show percentage next to the Battery icon
defaults write com.apple.menuextra.battery ShowPercent YES

# Set a blazingly fast mouse and scrolling speed
# defaults write .GlobalPreferences com.apple.mouse.scaling -1
defaults write .GlobalPreferences com.apple.scrollwheel.scaling -float 0.6875

# Set a blazingly fast keyboard repeat rate
defaults write NSGlobalDomain KeyRepeat -int 0
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Only show scrollbars when scrolling
defaults write NSGlobalDomain AppleShowScrollBars -string "WhenScrolling"

# Don't play user interface sound effects
defaults write com.apple.systemsound com.apple.sound.uiaudio.enabled -int 0

# Disable auto-correct
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# New Finder windows shows Home directory
defaults write com.apple.finder NewWindowTarget -string "PfHm"
defaults write com.apple.finder NewWindowTargetPath -string "file:///Users/vincent/"

# Disable the warning when changing a file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Hide desktop icons by default
defaults write com.apple.finder CreateDesktop -bool false

# Minimize windows into application icon.
defaults write com.apple.dock minimize-to-application -bool true

# Disable the Docks bounce to alert behavior
defaults write com.apple.dock no-bouncing -bool true

# Set the icon size of Dock items to 42 pixels
defaults write com.apple.dock tilesize -int 42

# Enable spring loading for all Dock items
defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true

# Expand save panel by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

# Expand print panel by default
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# Don’t animate opening applications from the Dock
defaults write com.apple.dock launchanim -bool false

# Automatically hide and show the Dock
defaults write com.apple.dock autohide -bool true

# Stop iTunes from responding to the keyboard media keys
launchctl unload -w /System/Library/LaunchAgents/com.apple.rcd.plist 2> /dev/null

# Disable the all too sensitive backswipe
defaults write com.google.Chrome AppleEnableSwipeNavigateWithScrolls -bool false
defaults write com.google.Chrome.canary AppleEnableSwipeNavigateWithScrolls -bool false
logk

# Revoke sudo access again
sudo -k

log 'Finished! Please reboot! Install additional software with `brew install` and `brew cask install`.'
