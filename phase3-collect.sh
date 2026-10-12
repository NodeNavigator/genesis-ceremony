#!/bin/bash
#
# PHASE 3 — RUN ON THE AWS NODE (coordinator), after every gentx is in hand.
#
# Drops all collected gentx files into the genesis, produces the FINAL genesis,
# prints its sha256 for everyone to verify, and installs the systemd unit.
#
# Usage:
#   mkdir -p /data/genesis-artifacts/gentxs
#   # copy every gentx-*.json from every validator into that folder, then:
#   ./phase3-collect.sh
#
set -e

BINARY="blockmazed"
INSTALL_PATH="/usr/local/bin/"
CHAINID="${CHAIN_ID:-blockmaze_6165-1}"

# Must match what phase1-skeleton.sh used.
HOMEDIR="${HOMEDIR:-/data/.tmp-blockmazed}"
PUBLISH_DIR="${PUBLISH_DIR:-/data/genesis-artifacts}"
GENTX_SRC="$PUBLISH_DIR/gentxs"

GENESIS=$HOMEDIR/config/genesis.json
CONFIG=$HOMEDIR/config/config.toml

[ -d "$HOMEDIR" ]   || { echo "No $HOMEDIR -- run phase1-skeleton.sh first."; exit 1; }
[ -d "$GENTX_SRC" ] || { echo "No $GENTX_SRC -- create it and put the gentx JSON files there."; exit 1; }

COUNT=$(ls -1 "$GENTX_SRC"/*.json 2>/dev/null | wc -l)
[ "$COUNT" -gt 0 ] || { echo "No gentx files found in $GENTX_SRC"; exit 1; }
echo ">>> Found $COUNT gentx file(s)."

# ---------------------------------------------------------------------------
# 1. Restore the pristine skeleton, then drop in every gentx.
#    (Restoring makes this script safely re-runnable.)
# ---------------------------------------------------------------------------
cp "$PUBLISH_DIR/skeleton-genesis.json" "$GENESIS"

rm -rf "$HOMEDIR/config/gentx"
mkdir -p "$HOMEDIR/config/gentx"
cp "$GENTX_SRC"/*.json "$HOMEDIR/config/gentx/"

# ---------------------------------------------------------------------------
# 2. Collect. This merges the gentxs into genesis AND rewrites persistent_peers
#    in config.toml from each gentx's memo (nodeid@ip:26656).
# ---------------------------------------------------------------------------
$BINARY collect-gentxs --home "$HOMEDIR"
$BINARY validate-genesis --home "$HOMEDIR"

echo ""
echo ">>> Validators now in genesis:"
jq -r '.app_state.genutil.gen_txs[].body.messages[]
       | select(."@type"=="/cosmos.staking.v1beta1.MsgCreateValidator")
       | "    \(.description.moniker)  \(.validator_address)  \(.value.amount)\(.value.denom)"' "$GENESIS"

echo ""
echo ">>> persistent_peers written to config.toml:"
grep '^persistent_peers' "$CONFIG"

# ---------------------------------------------------------------------------
# 3. Publish the final genesis + its hash.
# ---------------------------------------------------------------------------
cp "$GENESIS" "$PUBLISH_DIR/final-genesis.json"
SHA=$(sha256sum "$PUBLISH_DIR/final-genesis.json" | awk '{print $1}')
echo "$SHA  final-genesis.json" > "$PUBLISH_DIR/final-genesis.json.sha256"

# ---------------------------------------------------------------------------
# 4. Cosmovisor + systemd
# ---------------------------------------------------------------------------
COSMOVISOR_PATH=$(which cosmovisor)

grep -q "DAEMON_NAME" ~/.profile || {
  echo "export DAEMON_NAME=$BINARY"   >> ~/.profile
  echo "export DAEMON_HOME=$HOMEDIR"  >> ~/.profile
}
export DAEMON_NAME="$BINARY"
export DAEMON_HOME="$HOMEDIR"

cosmovisor init "${INSTALL_PATH}${BINARY}"

sudo su -c "echo '[Unit]
Description=Blockmaze Node
Wants=network-online.target
After=network-online.target
[Service]
User=$(whoami)
Group=$(whoami)
Type=simple
ExecStart=$COSMOVISOR_PATH run start --home $HOMEDIR --chain-id $CHAINID
Restart=always
RestartSec=3
LimitNOFILE=4096
Environment=\"DAEMON_NAME=$BINARY\"
Environment=\"DAEMON_HOME=$HOMEDIR\"
Environment=\"DAEMON_ALLOW_DOWNLOAD_BINARIES=false\"
Environment=\"DAEMON_RESTART_AFTER_UPGRADE=true\"
Environment=\"DAEMON_LOG_BUFFER_SIZE=512\"
Environment=\"UNSAFE_SKIP_BACKUP=false\"
[Install]
WantedBy=multi-user.target' > /etc/systemd/system/blockmazechain.service"

sudo systemctl daemon-reload
sudo systemctl enable blockmazechain.service

echo ""
echo "============================================================================"
echo "PHASE 3 DONE."
echo ""
echo "  Final genesis : $PUBLISH_DIR/final-genesis.json"
echo "  sha256        : $SHA"
echo "  Validators    : $COUNT"
echo ""
echo "Distribute final-genesis.json + the sha256 to every validator. Each of them:"
echo "    sha256sum final-genesis.json        # must match exactly"
echo "    cp final-genesis.json <their node home>/config/genesis.json"
echo "    # set persistent_peers in config.toml to the list above"
echo "    sudo systemctl start blockmazechain.service"
echo ""
echo "The chain produces block 1 once validators holding >2/3 of stake are online."
echo "Start yours with:  sudo systemctl start blockmazechain.service"
echo "Watch:             journalctl -u blockmazechain.service -f"
echo "============================================================================"