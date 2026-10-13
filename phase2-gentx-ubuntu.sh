#!/bin/bash
#
# PHASE 2 (Ubuntu) — RUN ON YOUR LOCAL UBUNTU MACHINE, Ledger plugged in,
# ETHEREUM app open on the device.
#
# Functionally identical to phase2-gentx-mac.sh. Differences that matter on Linux:
#   - apt instead of brew
#   - udev rules are REQUIRED (macOS needs none); without them the device is
#     root-only and you get "no hardware wallets detected" as a normal user
#   - keyring defaults to `file` rather than `os`, because the `os` backend needs
#     a running gnome-keyring/libsecret session (absent on headless boxes)
#   - the usbwallet hub matches Interface==0 on Linux, not the macOS usage page
#
# Prereqs: skeleton-genesis.json + coordinator-node.txt copied down from AWS.
#
set -e

# ---------------------------------------------------------------------------
# EDIT THESE
# ---------------------------------------------------------------------------
REPO_DIR="${REPO_DIR:-"/data/projects/projects/2025/BlockMaze/finvasiaGitlab/newcode/AkshitCode"/block-maze-chain-testnet}"   # this git repo, checked out locally
# Where you scp'd the artifacts from the AWS node's /data/genesis-artifacts.
ARTIFACTS="${ARTIFACTS:-$HOME/genesis-artifacts}"
SKELETON="${SKELETON:-$ARTIFACTS/skeleton-genesis.json}"
NODE_INFO="${NODE_INFO:-$ARTIFACTS/coordinator-node.txt}"
OUT_DIR="${OUT_DIR:-$ARTIFACTS}"

MONIKER="${MONIKER:-blockmaze-validator-1}"
CHAINID="${CHAINID:-blockmaze_6165-1}"
KEYNAME="${KEYNAME:-val-ledger}"
KEYRING="${KEYRING:-file}"                # file | os | test
LEDGER_ACCOUNT="${LEDGER_ACCOUNT:-0}"     # HD account index; 0 = MetaMask "Account 1"
LEDGER_INDEX="${LEDGER_INDEX:-0}"

STAKE_AMOUNT="500000000000000000000000iota"        # 500,000 BMZ — must be >= genesisvalidator min_self_delegation
MIN_SELF_DELEGATION="500000000000000000000000"
FEES="30000000000000000rho18"

COMMISSION_RATE="0.05"
COMMISSION_MAX_RATE="0.20"
COMMISSION_MAX_CHANGE_RATE="0.01"

SKIP_UDEV="${SKIP_UDEV:-false}"           # set true if Ledger Live already installed rules

HOMEDIR="$HOME/.blockmaze-gentx-signer"
BINARY="$REPO_DIR/build/blockmazed"
UDEV_RULES="/etc/udev/rules.d/20-hw1.rules"
# ---------------------------------------------------------------------------

[ -f "$SKELETON" ]  || { echo "Skeleton genesis not found at $SKELETON"; exit 1; }
[ -f "$NODE_INFO" ] || { echo "coordinator-node.txt not found at $NODE_INFO"; exit 1; }

# ---------------------------------------------------------------------------
# 0. Dependencies. zondax/hid vendors hidapi AND libusb, so gcc is all that the
#    USB layer needs -- no libusb-1.0-dev / libudev-dev required.
# ---------------------------------------------------------------------------
echo ">>> Installing build dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq build-essential jq bc curl git

# ---------------------------------------------------------------------------
# 1. udev rules. LINUX ONLY -- this is the single most common reason the CLI
#    cannot see a Ledger on Ubuntu. Written inline rather than piping a remote
#    script into sudo bash.
# ---------------------------------------------------------------------------
if [ "$SKIP_UDEV" != "true" ]; then
  echo ">>> Installing Ledger udev rules at $UDEV_RULES ..."
  sudo tee "$UDEV_RULES" >/dev/null <<'EOF'
# Ledger devices (vendor 0x2c97) - all models: Blue, Nano S/S Plus/X, Stax, Flex.
# TAG+="uaccess" hands the device to the logged-in seat on systemd systems;
# MODE/GROUP are the fallback for systems without uaccess.
SUBSYSTEM=="usb", ATTRS{idVendor}=="2c97", MODE="0660", GROUP="plugdev", TAG+="uaccess"
KERNEL=="hidraw*", ATTRS{idVendor}=="2c97", MODE="0660", GROUP="plugdev", TAG+="uaccess"
EOF

  sudo groupadd -f plugdev
  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx plugdev; then
    sudo usermod -aG plugdev "$USER"
    echo "!!! Added $USER to the 'plugdev' group."
    echo "!!! Log out and back in (or run 'newgrp plugdev') before continuing,"
    echo "!!! otherwise the device stays root-only in this shell."
  fi

  sudo udevadm control --reload-rules
  sudo udevadm trigger
  echo ">>> udev rules loaded. Unplug and replug the Ledger now."
  read -r -p "    Press enter once you have replugged it..."
fi

# ---------------------------------------------------------------------------
# 2. Is the device visible to the OS at all?
# ---------------------------------------------------------------------------
echo ">>> Checking USB enumeration (vendor 0x2c97):"
if command -v lsusb >/dev/null 2>&1; then
  if lsusb | grep -i "2c97"; then
    :
  else
    echo "!!! No Ledger found on USB."
    echo "!!!   - use a DATA cable, not charge-only"
    echo "!!!   - unlock the device (enter PIN)"
    echo "!!!   - QUIT Ledger Live and close any browser tab that touched the device"
    echo "!!!     (USB HID is exclusive -- one process at a time)"
    exit 1
  fi
else
  echo "    (lsusb not installed; skipping. apt-get install usbutils to enable this check)"
fi

# ---------------------------------------------------------------------------
# 3. Build a Linux binary WITH ledger support
# ---------------------------------------------------------------------------
if [ ! -x "$BINARY" ]; then
  echo ">>> Building blockmazed for Linux (ledger enabled)..."
  ( cd "$REPO_DIR" && CGO_ENABLED=1 LEDGER_ENABLED=true make build )
fi

echo ">>> Verifying ledger support is compiled in:"
"$BINARY" version --long 2>/dev/null | grep -i build_tags || true
if ! "$BINARY" version --long 2>/dev/null | grep -q "ledger"; then
  echo "!!! 'ledger' is missing from build_tags. Rebuild with CGO_ENABLED=1 and build-essential installed."
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. Pull the AWS node's CONSENSUS pubkey / node id / ip
# ---------------------------------------------------------------------------
CONSENSUS_PUBKEY=$(grep '^CONSENSUS_PUBKEY=' "$NODE_INFO" | cut -d= -f2-)
NODE_ID=$(grep '^NODE_ID=' "$NODE_INFO" | cut -d= -f2-)
PUBLIC_IP=$(grep '^PUBLIC_IP=' "$NODE_INFO" | cut -d= -f2-)

echo ">>> Validator node being registered:"
echo "      node id    : $NODE_ID"
echo "      ip         : $PUBLIC_IP"
echo "      cons pubkey: $CONSENSUS_PUBKEY"
[ -n "$CONSENSUS_PUBKEY" ] || { echo "CONSENSUS_PUBKEY empty -- check $NODE_INFO"; exit 1; }

# ---------------------------------------------------------------------------
# 5. Local signer home. init only to create config/; genesis is then REPLACED
#    by the published skeleton so the signature is over the real chain state.
# ---------------------------------------------------------------------------
rm -rf "$HOMEDIR"
"$BINARY" init "gentx-signer" --chain-id "$CHAINID" --home "$HOMEDIR" >/dev/null 2>&1
cp "$SKELETON" "$HOMEDIR/config/genesis.json"

# This machine's consensus key is irrelevant -- we sign for the AWS node's key.
rm -f "$HOMEDIR/config/priv_validator_key.json"

# ---------------------------------------------------------------------------
# 6. Register the Ledger key (no secret is written to disk -- the keyring
#    stores only the pubkey and HD path)
# ---------------------------------------------------------------------------
echo ""
echo ">>> Confirm on the Ledger: unlocked, ETHEREUM app open, blind signing / contract data ON."
read -r -p "    Press enter when ready..."

"$BINARY" keys add "$KEYNAME" \
  --ledger \
  --algo eth_secp256k1 \
  --coin-type 60 \
  --account "$LEDGER_ACCOUNT" \
  --index "$LEDGER_INDEX" \
  --keyring-backend "$KEYRING" \
  --home "$HOMEDIR"

VALADDR=$("$BINARY" keys show "$KEYNAME" -a --keyring-backend "$KEYRING" --home "$HOMEDIR")
echo ">>> Ledger derived operator address: $VALADDR"

# ---------------------------------------------------------------------------
# 7. Hard check: that address MUST be pre-funded in the skeleton, or the gentx
#    will be rejected at InitChain.
# ---------------------------------------------------------------------------
BAL=$(jq -r --arg a "$VALADDR" \
  '.app_state.bank.balances[] | select(.address==$a) | .coins[] | select(.denom=="iota") | .amount' \
  "$SKELETON")

if [ -z "$BAL" ]; then
  echo ""
  echo "!!! $VALADDR is NOT funded in the skeleton genesis."
  echo "!!! Either point the Ledger at a different account/index (LEDGER_ACCOUNT / LEDGER_INDEX),"
  echo "!!! or have the coordinator add this address to phase1-skeleton.sh and re-run phase 1."
  exit 1
fi

echo ">>> Genesis balance for this address: $BAL iota"
if [ "$(echo "$BAL >= $MIN_SELF_DELEGATION" | bc)" -ne 1 ]; then
  echo "!!! Balance is below the required self-delegation of $MIN_SELF_DELEGATION"
  exit 1
fi

# ---------------------------------------------------------------------------
# 8. Sign the gentx on the Ledger.
#    --pubkey         : the AWS node's CONSENSUS key (instead of a local priv_validator_key.json)
#    --node-id / --ip : so the gentx memo points peers at AWS, not at this machine
# ---------------------------------------------------------------------------
echo ""
echo ">>> Approve the EIP-712 hashes on the Ledger when prompted."
echo ""

"$BINARY" gentx "$KEYNAME" "$STAKE_AMOUNT" \
  --pubkey "$CONSENSUS_PUBKEY" \
  --node-id "$NODE_ID" \
  --ip "$PUBLIC_IP" \
  --moniker "$MONIKER" \
  --commission-rate "$COMMISSION_RATE" \
  --commission-max-rate "$COMMISSION_MAX_RATE" \
  --commission-max-change-rate "$COMMISSION_MAX_CHANGE_RATE" \
  --min-self-delegation "$MIN_SELF_DELEGATION" \
  --fees "$FEES" \
  --sign-mode amino-json \
  --ledger \
  --keyring-backend "$KEYRING" \
  --chain-id "$CHAINID" \
  --home "$HOMEDIR" \
  --output-document "$OUT_DIR/gentx-${MONIKER}.json"

echo ""
echo "============================================================================"
echo "PHASE 2 (Ubuntu) DONE."
echo ""
echo "  Signed gentx : $OUT_DIR/gentx-${MONIKER}.json"
echo "  Operator     : $VALADDR  (key never left the Ledger)"
echo "  Peer string  : $NODE_ID@$PUBLIC_IP:26656"
echo ""
echo "scp the gentx JSON to the AWS node's /data/genesis-artifacts/gentxs/,"
echo "then run phase3-collect.sh there."
echo "============================================================================"
