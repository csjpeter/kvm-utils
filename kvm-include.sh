
# Color codes
PURPLE='\033[0;35m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Logging functions
log_debug()    { [ "$DEBUG" = "yes" ] && echo -e "${PURPLE}[DEBUG]${NC} $*"; }
log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

ip_to_mac()
{
    local ip="$1"
    IFS='.' read -r a b c d <<< "$ip"
    export RETURNED_MAC=$(printf '52:54:%02X:%02X:%02X:%02X' $a $b $c $d)
}
