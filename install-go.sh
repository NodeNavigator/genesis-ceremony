#!/bin/bash
# shellcheck disable=SC2016
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAR_FILE="$SCRIPT_DIR/go1.27.2.src.tar.gz"
VERSION="1.27.2"

[ -z "$GOROOT" ] && GOROOT="$HOME/.go"
[ -z "$GOPATH" ] && GOPATH="$HOME/go"

OS="$(uname -s)"
ARCH="$(uname -m)"

case $OS in
    "Linux")
        case $ARCH in
        "x86_64")
            ARCH=amd64
            ;;
        "aarch64")
            ARCH=arm64
            ;;
        "armv6" | "armv7l")
            ARCH=armv6l
            ;;
        "armv8")
            ARCH=arm64
            ;;
        .*386.*)
            ARCH=386
            ;;
        esac
        PLATFORM="linux-$ARCH"
    ;;
    "Darwin")
          case $ARCH in
          "x86_64")
              ARCH=amd64
              ;;
          "arm64")
              ARCH=arm64
              ;;
          esac
        PLATFORM="darwin-$ARCH"
    ;;
esac

print_help() {
    echo "Usage: bash install-go.sh OPTIONS"
    echo -e "\nOPTIONS:"
    echo -e "  --remove\tRemove currently installed version"
    echo -e "  --version\tSpecify a version number to install"
    echo -e "  --tar\t\tUse local Go tar.gz file path"
    echo -e "\nDefault local tar file:"
    echo -e "  $TAR_FILE"
}

if [ -z "$PLATFORM" ]; then
    echo "Your operating system is not supported by the script."
    exit 1
fi

if [ -n "$($SHELL -c 'echo $ZSH_VERSION')" ]; then
    shell_profile="$HOME/.zshrc"
elif [ -n "$($SHELL -c 'echo $BASH_VERSION')" ]; then
    shell_profile="$HOME/.bashrc"
elif [ -n "$($SHELL -c 'echo $FISH_VERSION')" ]; then
    shell="fish"
    if [ -d "$XDG_CONFIG_HOME" ]; then
        shell_profile="$XDG_CONFIG_HOME/fish/config.fish"
    else
        shell_profile="$HOME/.config/fish/config.fish"
    fi
fi

if [ "$1" == "--remove" ]; then
    rm -rf "$GOROOT"
    if [ "$OS" == "Darwin" ]; then
        if [ "$shell" == "fish" ]; then
            sed -i "" '/# GoLang/d' "$shell_profile"
            sed -i "" '/set GOROOT/d' "$shell_profile"
            sed -i "" '/set GOPATH/d' "$shell_profile"
            sed -i "" '/set PATH $GOPATH\/bin $GOROOT\/bin $PATH/d' "$shell_profile"
        else
            sed -i "" '/# GoLang/d' "$shell_profile"
            sed -i "" '/export GOROOT/d' "$shell_profile"
            sed -i "" '/$GOROOT\/bin/d' "$shell_profile"
            sed -i "" '/export GOPATH/d' "$shell_profile"
            sed -i "" '/$GOPATH\/bin/d' "$shell_profile"
        fi
    else
        if [ "$shell" == "fish" ]; then
            sed -i '/# GoLang/d' "$shell_profile"
            sed -i '/set GOROOT/d' "$shell_profile"
            sed -i '/set GOPATH/d' "$shell_profile"
            sed -i '/set PATH $GOPATH\/bin $GOROOT\/bin $PATH/d' "$shell_profile"
        else
            sed -i '/# GoLang/d' "$shell_profile"
            sed -i '/export GOROOT/d' "$shell_profile"
            sed -i '/$GOROOT\/bin/d' "$shell_profile"
            sed -i '/export GOPATH/d' "$shell_profile"
            sed -i '/$GOPATH\/bin/d' "$shell_profile"
        fi
    fi
    echo "Go removed."
    exit 0
elif [ "$1" == "--help" ]; then
    print_help
    exit 0
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            if [ -z "$2" ]; then
                echo "Please provide a version number for: $1"
                exit 1
            fi
            VERSION="$2"
            shift 2
            ;;
        --tar)
            if [ -z "$2" ]; then
                echo "Please provide a tar.gz file path for: $1"
                exit 1
            fi
            TAR_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unrecognized option: $1"
            exit 1
            ;;
    esac
done

if [ -d "$GOROOT" ]; then
    echo "The Go install directory ($GOROOT) already exists. Exiting."
    exit 1
fi

TEMP_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEMP_DIRECTORY"' EXIT

if [ ! -f "$TAR_FILE" ]; then
    echo "Go tar file not found: $TAR_FILE"
    echo "Place go1.27.2.src.tar.gz in this script folder or pass it with:"
    echo "  bash install-go.sh --tar /path/to/go1.27.2.src.tar.gz"
    exit 1
fi

if ! tar -tzf "$TAR_FILE" >/dev/null 2>&1; then
    echo "Invalid tar.gz file: $TAR_FILE"
    exit 1
fi

cp "$TAR_FILE" "$TEMP_DIRECTORY/go.tar.gz"

echo "Extracting File..."
mkdir -p "$GOROOT"

tar -C "$GOROOT" --strip-components=1 -xzf "$TEMP_DIRECTORY/go.tar.gz"

if [[ "$TAR_FILE" == *".src.tar.gz" ]] && [ ! -x "$GOROOT/bin/go" ]; then
    echo "Source archive extracted, but Go binary was not found at $GOROOT/bin/go."
    echo "To build from source, install the required bootstrap Go version and run:"
    echo "  cd $GOROOT/src && ./make.bash"
fi

echo "Configuring shell profile in: $shell_profile"
touch "$shell_profile"
if [ "$shell" == "fish" ]; then
    {
        echo '# GoLang'
        echo "set GOROOT '${GOROOT}'"
        echo "set GOPATH '$GOPATH'"
        echo 'set PATH $GOPATH/bin $GOROOT/bin $PATH'
    } >> "$shell_profile"
else
    {
        echo '# GoLang'
        echo "export GOROOT=${GOROOT}"
        echo 'export PATH=$GOROOT/bin:$PATH'
        echo "export GOPATH=$GOPATH"
        echo 'export PATH=$GOPATH/bin:$PATH'
    } >> "$shell_profile"
fi

mkdir -p "${GOPATH}/"{src,pkg,bin}
echo -e "\nGo $VERSION was installed into $GOROOT.\n"
echo -e "\nApplying environment variables now..."
# Source shell profile to apply exports in current script session
    source "$shell_profile"
    echo "Environment variables loaded."
