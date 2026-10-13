#!/bin/bash
#
# PHASE 1 — RUN ON THE AWS NODE (coordinator / first validator)
#
# Builds the genesis SKELETON: all funded accounts + all jq param patches,
# but with an EMPTY gentxs list. No keys are created here and no mnemonic is
# needed -- the operator key lives on your Ledger (see phase2-gentx-mac.sh).
#
# Outputs:
#   $PUBLISH_DIR/skeleton-genesis.json   <- distribute this to every validator
#   $PUBLISH_DIR/coordinator-node.txt    <- this node's consensus pubkey + node id
#
set -e

current_path=$(pwd)
#bash "$current_path/install-go.sh"

#source "$HOME/.bashrc"
#source "$HOME/.profile"
ulimit -n 16384

go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.5.0
COSMOVISOR_PATH=$(which cosmovisor)
echo "Cosmovisor is installed at: $COSMOVISOR_PATH"

OS=$(awk -F '=' '/^NAME/{print $2}' /etc/os-release | awk '{print $1}' | tr -d '"')
VERSION=$(awk -F '=' '/^VERSION_ID/{print $2}' /etc/os-release | awk '{print $1}' | tr -d '"')

BINARY="blockmazed"
INSTALL_PATH="/usr/local/bin/"

if [ "$OS" == "Ubuntu" ] && [ "$VERSION" == "22.04" -o "$VERSION" == "24.04" ]; then
  sudo apt-get update
  sudo apt-get install -y build-essential jq wget unzip

  if [ -d "$INSTALL_PATH" ]; then
    BINARY_URL="https://github.com/NodeNavigator/blockmaze-mainnet-script/releases/download/blockmazed/${BINARY}"
    echo "Downloading binary for Ubuntu $VERSION: $BINARY_URL"
    curl -L "$BINARY_URL" -o "/tmp/${BINARY}"
    chmod +x "/tmp/${BINARY}"
    sudo cp "/tmp/${BINARY}" "$INSTALL_PATH"
    sudo chmod +x "${INSTALL_PATH}${BINARY}"
    echo "$BINARY installed or updated successfully!"
  else
    echo "Installation path $INSTALL_PATH does not exist. Please create it."
    exit 1
  fi
else
  echo "Only Ubuntu 22.04 and 24.04 are supported."
  exit 1
fi

sudo chmod u+x "${INSTALL_PATH}${BINARY}"
#==========================================================================================
echo "============================================================================"
echo "Enter the Name (moniker) for this coordinator node:"
echo "============================================================================"
read -r MONIKER

CHAINID="${CHAIN_ID:-blockmaze_6165-1}"
KEYRING="os"
KEYALGO="eth_secp256k1"
FEE=150000000000
BASE_DENOM="Rho18"

DEPLOYER_ACCESS_ADDRESSES='["0x2279c60f81C49d71CC55bB7aB526C84550A26f04"]'
FOUNDATION_ADDRESS="bmz14phuj3s3275sgqa4hrxx0xfqvhyfk32xy59e6q"
GENESIS_VALIDATOR_MIN_STAKE="500000000000000000000000"

GOV_QUORUM="0.400000000000000000"
GOV_THRESHOLD="0.500000000000000000"
GOV_VETO_THRESHOLD="0.334000000000000000"

# Node home (cosmovisor DAEMON_HOME) on this AWS instance.
HOMEDIR="${HOMEDIR:-/data/.tmp-blockmazed}"
# Where the ceremony artifacts (skeleton genesis, node info, gentxs, final
# genesis) are written. Kept on /data so it sits on the same volume as the
# node home. Override with:  PUBLISH_DIR=/some/path ./phase1-skeleton.sh
PUBLISH_DIR="${PUBLISH_DIR:-/data/genesis-artifacts}"

if systemctl is-active --quiet blockmazechain.service; then
    echo "Service is running. Stopping and removing it."
    sudo systemctl stop blockmazechain.service
    sudo rm -rf "$HOMEDIR"
    sudo rm -rf /etc/systemd/system/blockmazechain.service
fi

CONFIG=$HOMEDIR/config/config.toml
APP_TOML=$HOMEDIR/config/app.toml
CLIENT=$HOMEDIR/config/client.toml
GENESIS=$HOMEDIR/config/genesis.json
TMP_GENESIS=$HOMEDIR/config/tmp_genesis.json

command -v jq >/dev/null 2>&1 || {
	echo >&2 "jq not installed. More info: https://stedolan.github.io/jq/download/"
	exit 1
}

if [ -d "$HOMEDIR" ]; then
	printf "\nAn existing folder at '%s' was found. Delete it and rebuild genesis from scratch? [y/n]\n" "$HOMEDIR"
	read -r overwrite
else
	overwrite="Y"
fi

if [[ $overwrite != "y" && $overwrite != "Y" ]]; then
	echo "Aborted."
	exit 1
fi

sudo rm -rf "$HOMEDIR"

# /data is usually root-owned on a fresh EBS mount; create and hand it to us.
sudo mkdir -p "$PUBLISH_DIR"
sudo chown -R "$(whoami):$(whoami)" "$PUBLISH_DIR"

$BINARY config set client chain-id "$CHAINID" --home "$HOMEDIR"
$BINARY config set client keyring-backend "$KEYRING" --home "$HOMEDIR"

# init generates config/ + priv_validator_key.json (the CONSENSUS key -- it never
# leaves this machine and is NOT on the Ledger) and a fresh genesis.json.
$BINARY init "$MONIKER" -o --chain-id "$CHAINID" --home "$HOMEDIR"

# ---------------------------------------------------------------------------
# Genesis accounts
# ---------------------------------------------------------------------------
# Founder - Genesis Liquidity & Past KPI/IP Tranche
 $BINARY add-genesis-account bmz1pp6g58esx7a44lp9r9zxycax7xyuga237v8qv8 21250000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1k954464644a9ghd6tlhf3dq0p8yq7lvsqesjn3 10000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1dy9gf47ydh87g48x4pv68c9dv3uwa5mhchxs6p 6250000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1jm003tnrp8u7r9x3rt627gwfcu572cfathtg22 2000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz16z7u90qu9ykxljevnkuylt234h2d3l2dnfwq75 1500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1zydukstl6ajeheqh4u6r4cvqfe0d6xdw4wf9fv 3000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1al24aqgce2dfmcv8x6p2wlx96kfx7z770hwd9g 3250000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1zrzc3eul55c6fsncmj5qlqu46dphzuwajrpxu5 750000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1ecf5ecdwsfp5fhrv2lwrk6nefnfgzlga223sum 500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1krpqf9qhr3mvdf6z7r7gdpe6k3nml5vsd7d28l 7500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1hgdkr8exqj2jx2sd4v76wn2l0lyqahr7m7mzj4 7500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1w8wtw5ye3h5kmgyphusffg0vqylut7calt8t48 20000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1h90wjy9mpk54876u0cxz7nyaaugv6xu4gqnky7 3000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz10du7vq07pupcg96v0wzheg9h0sqsq7ce0ek7ju 3000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1qmynymh6p6hkddnvldl44grmg7ws4l35ltfxl5 2750000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1h9uulfhep8kqzpc2umeqjx07sugc8u29223jna 6250000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1q6hh64jdq3vxyer854ghjnk4mr3ghvzgjzvl06 1500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"

 $BINARY add-genesis-account bmz1pp6g58esx7a44lp9r9zxycax7xyuga237v8qv8 1900000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"

# Validator Addresses (Vendor & Contributor Performance Pool)
# Each holds 500,000 to bond + ~2 BMZ for gas. THESE are the addresses your
# Ledger (and each other validator's key) must derive to.
 $BINARY add-genesis-account bmz1tw5tpafapktpqdlvjllsculh4ptc0fjlkkynhn 500100000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1cqt0d88re2jh5rce3a8srppkwc0xrxk98ez7tc 500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1fgsj0lw4au08030danzjf050vf67xarr7nvhg6 500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1y0q2ux95qqfuj2c4pcpxzsdzllhzefdl4x0h2p 500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1cwq0c0qptlzex85l3utsswdpva82jvhwp2w99x 500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1lhsun9ad8mf0fuatj9y58amjtczlq9klwpsuhk 500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz18r2xrnvkg8p0euy4x9qa2stg6p3czz6yjqcvpa 500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1u7m4ctw5f6umml8prqtmdprw8m07ldfvwfpjwm 500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1n3p5ddd6cw4wtpj6kjh5m30uh29py5l2dm8rwf 500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1smp6cw0tmzrf68sa090jzhqjgclgzg2pkfkem5 500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz17ulxgqlmxhvepx5hfv485lfletq3nngeljxhw3 500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz17lvaq6rp8rwhwj397trsdzgxyw0ery3qztnunt 500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
 $BINARY add-genesis-account bmz1jrvtd5s39gwz8qd62nvjm0mpkpejvvghw54vw4 499900000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"

# Genesis Validator Compensation Pool
 $BINARY add-genesis-account bmz1hneqzs7hc5gwqvy8parnwuy5uurrfwv9xuyg0q 100000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Early / Strategic Investors
 $BINARY add-genesis-account bmz1wtd4hx6m7u6xtdwwuy9jtmplxv5yf7tn8qu08e 500000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Vendor & Contributor Performance Pool
 $BINARY add-genesis-account bmz1l3tezd9xkehyghqp5q76mklmg8dkr5zvyefuh0 593500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# RWA, Business Development & Protocol Operations Team
 $BINARY add-genesis-account bmz1629g6ae26cxv956ajvnw7w9k8sj3zphh676jnj 600000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Advisors & Specialized Experts
 $BINARY add-genesis-account bmz1lk4vktlzqe7gtws0km8m0uqzvejj4q9m6yk2yp 200000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Community Users & Contributors
 $BINARY add-genesis-account bmz182thfv662tnr4gpmum7hs330e0egycg9m5cltc 1200000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Ecosystem & RWA Adoption Fund
 $BINARY add-genesis-account bmz13hhqm7xazcxxm0stacxk7u5ngqkxt8d2r92ags 1000000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Protocol-Owned Liquidity
 $BINARY add-genesis-account bmz1fg9z3uyhe5u22xl8dp4zr6ps3afgtndn0mv47e 350000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Tactical Exchange & MM Incentives
 $BINARY add-genesis-account bmz1pa6x9m9h0yaw4k2d20rfpy3dl4u26mvgpc6w0e 350000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Circuit Breaker Reserve
 $BINARY add-genesis-account bmz1uy4285tyaxwpc07hg3z9flhn4z3dsxvyl68xjz 400000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Foundation Operations
 $BINARY add-genesis-account bmz14phuj3s3275sgqa4hrxx0xfqvhyfk32xy59e6q 200000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Ecosystem & Public Grants
 $BINARY add-genesis-account bmz1eejtdp88sxc346mazneeq82rcg392ff7e4nkne 200000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Strategic Long-Term Reserves
 $BINARY add-genesis-account bmz18uph3m3xq5r2a4dxtwqqtwldw4ueheczhdxkms 300000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"

# ---------------------------------------------------------------------------
# Genesis parameter patches  (NOTE: these MUST run before the gentxs are made,
# because bond_denom=Rho18 is what makes a `...Rho18` gentx valid at InitChain)
# ---------------------------------------------------------------------------
jq '.app_state["staking"]["params"]["bond_denom"]="Rho18"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["crisis"]["constant_fee"]["denom"]="Rho18"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["gov"]["deposit_params"]["min_deposit"][0]["denom"]="Rho18"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["gov"]["params"]["min_deposit"][0]["denom"]="Rho18"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["gov"]["params"]["min_deposit"][0]["amount"]="50000000000000000000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["mint"]["params"]["mint_denom"]="Rho18"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"

jq '.consensus["params"]["block"]["max_bytes"]="8388608"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.consensus["params"]["block"]["max_gas"]="100000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"

jq '.app_state["mint"]["minter"]["inflation"]="0.000000000000000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["mint"]["params"]["inflation_rate_change"]="0.000000000000000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["mint"]["params"]["inflation_max"]="0.000000000000000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["mint"]["params"]["inflation_min"]="0.000000000000000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["distribution"]["params"]["community_tax"]="0.000000000000000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"

# FIXED: the original had a trailing space inside this string ("5256000 "),
# which fails to unmarshal as a uint at InitGenesis.
jq '.app_state["mint"]["params"]["blocks_per_year"]="5256000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"

jq '.app_state["gov"]["deposit_params"]["max_deposit_period"]="604800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["gov"]["params"]["max_deposit_period"]="604800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["gov"]["voting_params"]["voting_period"]="604800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["gov"]["params"]["voting_period"]="604800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["staking"]["params"]["unbonding_time"]="604800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["staking"]["params"]["max_validators"]="250"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["slashing"]["params"]["downtime_jail_duration"]="600s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["slashing"]["params"]["signed_blocks_window"]="100000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"

jq --arg foundation "$FOUNDATION_ADDRESS" '.app_state.rewardpool.foundation_addresses = [$foundation]' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["feemarket"]["params"]["min_gas_price"]="150000000000"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq --arg min_stake "$GENESIS_VALIDATOR_MIN_STAKE" '.app_state["genesisvalidator"]["params"]["min_self_delegation"] = $min_stake' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"

jq --arg quorum "$GOV_QUORUM" '.app_state["gov"]["params"]["quorum"]=$quorum' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq --arg threshold "$GOV_THRESHOLD" '.app_state["gov"]["params"]["threshold"]=$threshold' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq --arg veto_threshold "$GOV_VETO_THRESHOLD" '.app_state["gov"]["params"]["veto_threshold"]=$veto_threshold' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"

echo "Setting deployer access addresses: $DEPLOYER_ACCESS_ADDRESSES"
jq --argjson deployer_access "$DEPLOYER_ACCESS_ADDRESSES" '.app_state["deployer"]["params"]["deployer_access"] = $deployer_access' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"

sed -i.bak 's/"expedited_voting_period": "86400s"/"expedited_voting_period": "600s"/g' "$GENESIS"
rm -f "$GENESIS.bak"

# ---------------------------------------------------------------------------
# Node config (LOCAL to this machine -- not part of the shared genesis)
# ---------------------------------------------------------------------------
sed -i 's/timeout_commit = "3s"/timeout_commit = "6s"/g' "$CONFIG"
sed -i 's/prometheus = false/prometheus = true/' "$CONFIG"
sed -i 's/experimental_websocket_write_buffer_size = 200/experimental_websocket_write_buffer_size = 600/' "$CONFIG"
sed -i 's/prometheus-retention-time  = "0"/prometheus-retention-time  = "1000000000000"/g' "$APP_TOML"
sed -i 's/enabled = false/enabled = true/g' "$APP_TOML"
sed -i 's/minimum-gas-prices = "0Rho18"/minimum-gas-prices = "0.0000015Rho18"/g' "$APP_TOML"
sed -i 's/enable = false/enable = true/g' "$APP_TOML"
sed -i 's/swagger = false/swagger = true/g' "$APP_TOML"
sed -i 's/enabled-unsafe-cors = false/enabled-unsafe-cors = true/g' "$APP_TOML"
sed -i 's/enable-unsafe-cors = false/enable-unsafe-cors = true/g' "$APP_TOML"
sed -i '/\[rosetta\]/,/^\[.*\]/ s/enable = true/enable = false/' "$APP_TOML"
sed -i 's/localhost/0.0.0.0/g' "$APP_TOML"
sed -i 's/localhost/0.0.0.0/g' "$CONFIG"
sed -i 's/:26660/0.0.0.0:26660/g' "$CONFIG"
sed -i 's/localhost/0.0.0.0/g' "$CLIENT"
sed -i 's/127.0.0.1/0.0.0.0/g' "$APP_TOML"
sed -i 's/127.0.0.1/0.0.0.0/g' "$CONFIG"
sed -i 's/127.0.0.1/0.0.0.0/g' "$CLIENT"
sed -i 's/\[\]/["*"]/g' "$CONFIG"
sed -i 's/\["\*",\]/["*"]/g' "$CONFIG"

grep -q -F '[rosetta]' "$APP_TOML" && sed -i '/\[rosetta\]/,/^\[/ s/enable = true/enable = false/' "$APP_TOML"
grep -q -F '[memiavl]' "$APP_TOML" && sed -i '/\[memiavl\]/,/^\[/ s/enable = true/enable = false/' "$APP_TOML"
grep -q -F '[versiondb]' "$APP_TOML" && sed -i '/\[versiondb\]/,/^\[/ s/enable = true/enable = false/' "$APP_TOML"

# SECURITY: the blanket 127.0.0.1 -> 0.0.0.0 above also exposes CometBFT RPC.
# Re-bind it to loopback; reach it over the SSH tunnel instead.
sed -i 's|^laddr = "tcp://0.0.0.0:26657"|laddr = "tcp://0.0.0.0:26657"|' "$CONFIG"

# ---------------------------------------------------------------------------
# Validate (passes with an empty gentxs list) and publish the skeleton
# ---------------------------------------------------------------------------
$BINARY validate-genesis --home "$HOMEDIR"

cp "$GENESIS" "$PUBLISH_DIR/skeleton-genesis.json"

TENDERMINTPUBKEY=$($BINARY tendermint show-validator --home "$HOMEDIR")
NODEID=$($BINARY tendermint show-node-id --home "$HOMEDIR")
PUBIP=$(curl -s https://checkip.amazonaws.com || echo "SET_ME")

{
  echo "MONIKER=$MONIKER"
  echo "NODE_ID=$NODEID"
  echo "PUBLIC_IP=$PUBIP"
  echo "CONSENSUS_PUBKEY=$TENDERMINTPUBKEY"
  echo "PEER=$NODEID@$PUBIP:26656"
} | tee "$PUBLISH_DIR/coordinator-node.txt"

echo ""
echo "============================================================================"
echo "PHASE 1 DONE."
echo ""
echo "  Skeleton genesis : $PUBLISH_DIR/skeleton-genesis.json"
echo "  This node's info : $PUBLISH_DIR/coordinator-node.txt"
echo ""
echo "Next:"
echo "  1. scp the skeleton + coordinator-node.txt down to your Mac."
echo "  2. Run phase2-gentx-mac.sh on the Mac with the Ledger attached."
echo ""
echo "Do NOT start the service yet -- genesis has no validators in it."
echo "============================================================================"