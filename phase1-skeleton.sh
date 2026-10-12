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
    BINARY_URL="https://github.com/NodeNavigator/genesis-ceremony/releases/download/blockmazed/${BINARY}"
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
BASE_DENOM="rho18"

DEPLOYER_ACCESS_ADDRESSES='["0x7cb61d4117ae31a12e393a1cfa3bac666481d02e", "0xc6fe5d33615a1c52c08018c47e8bc53646a0e101", "0x963ebdf2e1f8db8707d05fc75bfeffba1b5bac17","0x729a83fF79D2897e091452571DFB3F4d0cc19406","0x686B3140817f40344A66662C4038f5E5163C990e"]'
FOUNDATION_ADDRESS="bmz1dp4nzsyp0aqrgjnxvckyqw84u5trexgw9twp6u"
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
$BINARY add-genesis-account bmz1l2guurkj3p3kcsrtyh0xnetxphn3yu23u4t69r 17940000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1vqqp55msh82ehwjze0c8pf0452ewy29v47c567 9310000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz10glf8q0y50j4tns2pxne7e7jdcy0ln4p6df527 5000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz17zjh9znuk5qpqg37hne33adgpc877exeepw7gc 3500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1szre82raxh3pcqerkz62t5juvl47jnzguja2wp 1500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz12n7xs6ew7ut6xhqyu2arrt6tw9uvrhps03xzjs 6250000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz16flekjvnh5ww8u8zasuxl47sg3rvrcsu2mwq4q 500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz18scpkpavpay2jlujmssmekhsjadlg5s6rdzfyg 1000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz10acpku3ta2nxj4akscyzjk7zpqjgvmetj930w3 10000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1fu3f5kuygzec747q3325ec0sv3qk0wdxuf703h 10000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz187dgg6r3zky3fq70gxujf8fqp8hs6kumwmmg53 20000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1nvf8tlamsvgnr9cawclgcq4cp80fka7u5ustk0 5000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1hc2wx0qmq4c402zvzp2ff8tt5l9suhkzgw2mav 5000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz16wcjknjcyetlqghsscsjp5equ0a6znfxx9dl76 2500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1w294vmezgcfeu2lrmqzlahtmr33k0z3paf0j6s 2500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"

# Founder - Core Allocation
$BINARY add-genesis-account bmz17l2mjk3ehehze20yfwj6kumym8v8vjj6qxh5xg 340860000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1zrjtz0fqnnw4lf3cynqjumyr90ka0slwvgfqc0 176890000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz13n6kjcfu3l78syrtwu8fysqz647sg7n8jv0y65 95000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1p25ecqd4egvr5akxq6rezxar5msklnpff0adz6 66500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1m6gc8m5l42yat9e2gwdu58ajkfn8ay5phz9rx4 28500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1sjqql5z62kc4rknxr52sc8xvu83393yg6mw49v 118750000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1tpm0pl3y4raf405r5d486gpfvdhezp92hxu4ft 9500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1cfct6kmtjgnum73eurfu4r3qnwgmzv83mw2vqt 19000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz13w25s2paay8s7xc3rtp3kgkr9f7gv4d9922zrd 190000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1h36fk4slu5hvy9nqefmwrrqxqusnlqf9raex5y 190000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz18lg5n05wx5lrmnaclhetjh26jn8y6m4dexlje5 380000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz17ltj8z48u5wlxj67p0lzpjgzunf3eyzwvenk8q 95000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1dsu7lfn86vhwsdndtya6skyj3t5l0hlddnjxk2 95000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz10fqycxkvpyur3qlvn4dxlnp65asqvfxquueck4 47500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1ltgy8r0qf0aakhp08g09t97vhpkv7z9722mfm0 47500000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"

# Validator Addresses (Vendor & Contributor Performance Pool)
# Each holds 500,000 to bond + ~2 BMZ for gas. THESE are the addresses your
# Ledger (and each other validator's key) must derive to.
$BINARY add-genesis-account bmz1dp4nzsyp0aqrgjnxvckyqw84u5trexgw9twp6u 500006000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz15m57vv9nqvcznev4vk95maw2c6qt5a8k0q4gst 500002000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz14a40mqxy0yprdt4r336n58dpy0usqhannz4rgy 500002000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1d0kjpgx3z9vcvya9z6pmfyal5n6at8yw4zs8nl 500002000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1f2lntkq4ak6dg9g6sx9kjl5nm8v2zpwkym8wem 500002000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1cwf4a74rjs0g52vrqn0rxj2a6fh5k645jez53e 500002000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1qcqqnztczwd3w22gp8cxfpjrtflwk3a5uds9ay 500002000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1fplzqx9a8s6u86hgdkqtvkneum3ea3w3zr3hvz 500002000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1vesxc66vh78m4lndh7kyh0cukq2c9ddx28ejxf 500002000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1w8cmjraklng9hstg5agsk2smqp2wshw3pyp84e 500002000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1zyn4lxlnyxwakrrewzsfq7ly0f83j403t5u4x5 500002000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz129shcc5y2nqjzhpkhvqw5gfc7sr7par59jjn6u 500002000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
$BINARY add-genesis-account bmz1en8l3jgltrcupxpu9a90q5jeaudagef5q0uedp 500002000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"

# Genesis Validator Compensation Pool
$BINARY add-genesis-account bmz1lya5ec74uk0dt2eqvjc847f05qay0ltwwvqcpk 100000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Early / Strategic Investors
$BINARY add-genesis-account bmz1escuhycqte9c7w8lyn4qtn9yf68js6f8nz32wf 500000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Vendor & Contributor Performance Pool
$BINARY add-genesis-account bmz16rvp8lkas9j0rv0xweaehx9pvsngv9fcgsp0na 593499970000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# RWA, Business Development & Protocol Operations Team
$BINARY add-genesis-account bmz1ncr4fa338rrr73df6sll94kzfxendagw8693xa 600000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Advisors & Specialized Experts
$BINARY add-genesis-account bmz1f6eqenzd3842e6j3v94m9tm3d2t763wnv2j20l 200000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Community Users & Contributors
$BINARY add-genesis-account bmz1syc5z72fmvx28l9v88cjs6ez74nxyn4ljt8u76 1200000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Ecosystem & RWA Adoption Fund
$BINARY add-genesis-account bmz1ggu4jyjf2p9rcwpc6empmgsjkz7g2wvnes08pu 1000000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Protocol-Owned Liquidity
$BINARY add-genesis-account bmz1qtqeuwcls348zcw0lzwz47zfu7dfdne8t49t40 350000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Tactical Exchange & MM Incentives
$BINARY add-genesis-account bmz1tt030v62z3q4a55l8lpxxh0k0xqakjw9z2z8hq 350000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Circuit Breaker Reserve
$BINARY add-genesis-account bmz1kl9dfc0572z638pw6kqh32px3yuj5hxawwgdyn 400000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Foundation Operations
$BINARY add-genesis-account bmz10ee39z3t43nh3hc8uk9xvh7pl6x7h5hwm7gjlf 200000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Ecosystem & Public Grants
$BINARY add-genesis-account bmz133a3r8zj8gqh753m36x3z8767k5sgclwh2umtc 200000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"
# Strategic Long-Term Reserves
$BINARY add-genesis-account bmz1aam8fp77q4ej7dsq0mr7a9832kkfl6zge7j5vd 300000000000000000000000000$BASE_DENOM --keyring-backend "$KEYRING" --home "$HOMEDIR"

# ---------------------------------------------------------------------------
# Genesis parameter patches  (NOTE: these MUST run before the gentxs are made,
# because bond_denom=rho18 is what makes a `...rho18` gentx valid at InitChain)
# ---------------------------------------------------------------------------
jq '.app_state["staking"]["params"]["bond_denom"]="rho18"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["crisis"]["constant_fee"]["denom"]="rho18"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["gov"]["deposit_params"]["min_deposit"][0]["denom"]="rho18"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["gov"]["params"]["min_deposit"][0]["denom"]="rho18"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["mint"]["params"]["mint_denom"]="rho18"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"

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

jq '.app_state["gov"]["deposit_params"]["max_deposit_period"]="1800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["gov"]["params"]["max_deposit_period"]="1800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["gov"]["voting_params"]["voting_period"]="1800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["gov"]["params"]["voting_period"]="1800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
jq '.app_state["staking"]["params"]["unbonding_time"]="1800s"' "$GENESIS" >"$TMP_GENESIS" && mv "$TMP_GENESIS" "$GENESIS"
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
sed -i 's/minimum-gas-prices = "0rho18"/minimum-gas-prices = "0.0000015rho18"/g' "$APP_TOML"
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
sed -i 's|^laddr = "tcp://0.0.0.0:26657"|laddr = "tcp://127.0.0.1:26657"|' "$CONFIG"

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
echo "  3. Send the skeleton to the other 12 validators so they can do the same."
echo "  4. Collect all gentx JSON files, then run phase3-collect.sh here."
echo ""
echo "Do NOT start the service yet -- genesis has no validators in it."
echo "============================================================================"