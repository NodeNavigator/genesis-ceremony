#!/bin/bash
#
# PHASE 2 — RUN ON YOUR MAC, with the Ledger plugged in and the ETHEREUM app open.
#
# Produces a signed gentx without the operator private key ever touching AWS.
# The consensus pubkey comes from the AWS node (public, safe to copy in plaintext);
# the operator key stays on the Ledger.
#
# Prereqs:
#   - Go + Xcode command line tools (`xcode-select --install`) for the CGO/ledger build
#   - jq            (`brew install jq`)
#   - skeleton-genesis.json + coordinator-node.txt copied down from the AWS node
#
set -e

# ---------------------------------------------------------------------------
# EDIT THESE
# ---------------------------------------------------------------------------
REPO_DIR="${REPO_DIR:-$HOME/Downloads/block-maze-chain}"   # this git repo, checked out on the Mac
# Where you scp'd the artifacts from the AWS node's /data/genesis-artifacts.
# (Macs have no /data, so these stay under $HOME here.)
ARTIFACTS="${ARTIFACTS:-$HOME/genesis-artifacts}"
SKELETON="${SKELETON:-$ARTIFACTS/skeleton-genesis.json}"
NODE_INFO="${NODE_INFO:-$ARTIFACTS/coordinator-node.txt}"
OUT_DIR="${OUT_DIR:-$ARTIFACTS}"

MONIKER="${MONIKER:-blockmaze-validator-1}"
CHAINID="${CHAINID:-blockmaze_6165-1}"
KEYNAME="${KEYNAME:-val-ledger}"
KEYRING="${KEYRING:-os}"                  # os = macOS Keychain. file | test also work.
LEDGER_ACCOUNT="${LEDGER_ACCOUNT:-0}"     # HD account index; 0 = MetaMask "Account 1"
LEDGER_INDEX="${LEDGER_INDEX:-0}"

STAKE_AMOUNT="500000000000000000000000rho18"        # 500,000 BMZ — must be >= genesisvalidator min_self_delegation
MIN_SELF_DELEGATION="500000000000000000000000"
FEES="30000000000000000rho18"

COMMISSION_RATE="0.05"
COMMISSION_MAX_RATE="0.20"
COMMISSION_MAX_CHANGE_RATE="0.01"

HOMEDIR="$HOME/.blockmaze-gentx-signer"
BINARY="$REPO_DIR/build/blockmazed"
# ---------------------------------------------------------------------------

command -v jq >/dev/null 2>&1 || { echo "jq not installed: brew install jq"; exit 1; }
[ -f "$SKELETON" ]  || { echo "Skeleton genesis not found at $SKELETON"; exit 1; }
[ -f "$NODE_INFO" ] || { echo "coordinator-node.txt not found at $NODE_INFO"; exit 1; }

# ---------------------------------------------------------------------------
# 1. Build a Mac binary WITH ledger support
#    (the GitHub release is a Linux binary and will not run here)
# ---------------------------------------------------------------------------
if [ ! -x "$BINARY" ]; then
  echo ">>> Building blockmazed for macOS (ledger enabled)..."
  ( cd "$REPO_DIR" && CGO_ENABLED=1 LEDGER_ENABLED=true make build )
fi

echo ">>> Verifying ledger support is compiled in:"
"$BINARY" version --long 2>/dev/null | grep -i build_tags || true
if ! "$BINARY" version --long 2>/dev/null | grep -q "ledger"; then
  echo "!!! 'ledger' is missing from build_tags. Rebuild with CGO_ENABLED=1 and Xcode CLT installed."
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Pull the AWS node's CONSENSUS pubkey / node id / ip
# ---------------------------------------------------------------------------
CONSENSUS_PUBKEY=$(grep '^CONSENSUS_PUBKEY=' "$NODE_INFO" | cut -d= -f2-)
NODE_ID=$(grep '^NODE_ID=' "$NODE_INFO" | cut -d= -f2-)
PUBLIC_IP=$(grep '^PUBLIC_IP=' "$NODE_INFO" | cut -d= -f2-)

echo ">>> Validator node being registered:"
echo "      node id   : $NODE_ID"
echo "      ip        : $PUBLIC_IP"
echo "      cons pubkey: $CONSENSUS_PUBKEY"
[ -n "$CONSENSUS_PUBKEY" ] || { echo "CONSENSUS_PUBKEY empty -- check $NODE_INFO"; exit 1; }

# ---------------------------------------------------------------------------
# 3. Local signer home. init only to create config/; genesis is then REPLACED
#    by the published skeleton so the signature is over the real chain state.
# ---------------------------------------------------------------------------
rm -rf "$HOMEDIR"
"$BINARY" init "gentx-signer" --chain-id "$CHAINID" --home "$HOMEDIR" >/dev/null 2>&1
cp "$SKELETON" "$HOMEDIR/config/genesis.json"

# This machine's consensus key is irrelevant -- we sign for the AWS node's key.
# Remove it so it can never be confused for a real validator key.
rm -f "$HOMEDIR/config/priv_validator_key.json"

# ---------------------------------------------------------------------------
# 4. Register the Ledger key (nothing secret is written to disk -- the keyring
#    stores only the pubkey and HD path)
# ---------------------------------------------------------------------------
echo ""
echo ">>> Confirm on the Ledger: unlocked, ETHEREUM app open, contract data / blind signing ON."
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
# 5. Hard check: that address MUST be pre-funded in the skeleton, or the gentx
#    will be rejected at InitChain.
# ---------------------------------------------------------------------------
BAL=$(jq -r --arg a "$VALADDR" \
  '.app_state.bank.balances[] | select(.address==$a) | .coins[] | select(.denom=="rho18") | .amount' \
  "$SKELETON")

if [ -z "$BAL" ]; then
  echo ""
  echo "!!! $VALADDR is NOT funded in the skeleton genesis."
  echo "!!! Either point the Ledger at a different account/index (LEDGER_ACCOUNT / LEDGER_INDEX),"
  echo "!!! or have the coordinator add this address to phase1-skeleton.sh and re-run phase 1."
  exit 1
fi

echo ">>> Genesis balance for this address: $BAL rho18"
if [ "$(echo "$BAL >= $MIN_SELF_DELEGATION" | bc)" -ne 1 ]; then
  echo "!!! Balance is below the required self-delegation of $MIN_SELF_DELEGATION"
  exit 1
fi

# ---------------------------------------------------------------------------
# 6. Sign the gentx on the Ledger.
#    --pubkey  : the AWS node's CONSENSUS key (instead of a local priv_validator_key.json)
#    --node-id / --ip : so the gentx memo points peers at AWS, not at this Mac
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
echo "PHASE 2 DONE."
echo ""
echo "  Signed gentx : $OUT_DIR/gentx-${MONIKER}.json"
echo "  Operator     : $VALADDR  (key never left the Ledger)"
echo "  Peer string  : $NODE_ID@$PUBLIC_IP:26656"
echo ""
echo "Send ONLY the gentx JSON to the coordinator. Then run phase3-collect.sh on AWS."
echo "============================================================================"
