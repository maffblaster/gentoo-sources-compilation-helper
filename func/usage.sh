usage() {
    echo "Usage: ${0##*/} [--help|-h] [--version|-v] [--kernel|-k <version>] [--yestoall|-y]"
    echo ""
    echo "-h, --help        Display this help"
    echo "-v, --version     Display version and exit"
    echo "-k, --kernel      kernel version in format linux-<version>-gentoo[<-r<1-9>>]"
    echo "-y, --yestoall    Automatically answer yes to all questions"
    echo ""
    echo ""
}
