#!/bin/bash
# Entrypoint script to build args for Penumbra's pd,
# based on StatefulSet k8s ordinal.
set -euo pipefail


# Use the STATEFULSET_ORDINAL environment variable
if [[ -z "${STATEFULSET_ORDINAL:-}" ]]; then
  echo "STATEFULSET_ORDINAL is not set" >&2
  exit 1
fi
statefulset_ordinal="${STATEFULSET_ORDINAL}"
validator_upload_needed=0
# Raw Helm vars translated to JSON representation in this file.
node_info_filepath="/nodes.json"

>&2 echo "Configuring node '$statefulset_ordinal' with node info:"
jq < "$node_info_filepath"

# Unpack the JSON Helm vars as Bash env vas.
function get_var() {
    local v
    local json_address
    json_address="${1:-}"
    shift 1
    v="$(jq -r ".[$statefulset_ordinal].$json_address" "$node_info_filepath")"
    if [[ $v = "null" ]]; then
        v=""
    fi
    echo "$v"
}

external_address_flag=""
external_address="$(get_var "external_address")"
if [[ -n $external_address ]] ; then
    external_address_flag="--external-address ${external_address: $PUBLIC_IP}"
fi

moniker_flag=""
moniker="$(get_var "moniker")"
if [[ -n $moniker ]] ; then
    moniker_flag="--moniker $moniker"
fi

seed_mode="$(get_var "seed_mode")"
if [[ "$seed_mode" = "true" ]] ; then
    seed_mode="true"
else
    seed_mode="false"
fi

new_installation=0
if ! test -e /penumbra-config/testnet_data/node0/cometbft/config/config.toml; then
    new_installation=1
    echo "No pre-existing testnet data, pulling fresh info"
    pd testnet --testnet-dir /penumbra-config/testnet_data join \
        --tendermint-p2p-bind 0.0.0.0:26656 \
        --tendermint-rpc-bind 0.0.0.0:26657 \
        $external_address_flag \
        $moniker_flag \
        "$PENUMBRA_BOOTSTRAP_URL";
fi;

chown -R 1000:1000 /penumbra-config/testnet_data;
echo ">>>>>>>>>>>>>>>>>>"
# sed -i -e "s#^indexer.*#indexer = \"psql\"\\npsql-conn = \"$COMETBFT_POSTGRES_CONNECTION_URL\"#" "/penumbra-config/testnet_data/node0/cometbft/config/config.toml";
# sed -i -e "s#^indexer.*#indexer = \"psql\"\\npsql-conn = \"$COMETBFT_POSTGRES_CONNECTION_URL\"#" "/penumbra-config/testnet_data/node0/cometbft/config/config.toml";
ESCAPED_URL=$(printf '%s\n' "$COMETBFT_POSTGRES_CONNECTION_URL" | sed 's/[&/\]/\\&/g')
CONFIG_FILE="/penumbra-config/testnet_data/node0/cometbft/config/config.toml"

# Check if psql-conn is present
if grep -q "^psql-conn" "$CONFIG_FILE"; then
  # Update the existing psql-conn line
  # Ensure indexer is set to "psql"
  sed -i -e "s#^indexer.*#indexer = \"psql\"#" "$CONFIG_FILE"
  sed -i -e "s#^psql-conn.*#psql-conn = \"$ESCAPED_URL\"#" "$CONFIG_FILE"
else
  # Add the psql-conn line if it does not exist
  sed -i -e "s#^indexer.*#indexer = \"psql\"\\npsql-conn = \"$COMETBFT_POSTGRES_CONNECTION_URL\"#" "$CONFIG_FILE";
fi

echo "Put up latest genesis file"
curl -s "${PENUMBRA_BOOTSTRAP_URL}/genesis" | jq '.result.genesis' > /penumbra-config/testnet_data/node0/cometbft/config/genesis.json

sed -i -e "s#^indexer.*#indexer = \"psql\"#" "$CONFIG_FILE"
sed -i -e "s#^psql-conn.*#psql-conn = \"$ESCAPED_URL\"#" "$CONFIG_FILE"
sed -i -e "s/external_address.*/external_address = \"$external_address\"/" "$CONFIG_FILE";
sed -i -e "s/moniker.*/moniker = \"$moniker\"/" "$CONFIG_FILE";
sed -i -e "s/max_num_inbound_peers.*/max_num_inbound_peers = $COMETBFT_CONFIG_P2P_MAX_NUM_INBOUND_PEERS/" "$CONFIG_FILE";
sed -i -e "s/max_num_outbound_peers.*/max_num_outbound_peers = $COMETBFT_CONFIG_P2P_MAX_NUM_OUTBOUND_PEERS/" "$CONFIG_FILE";
sed -i -e "s/^seed_mode.*/seed_mode = \"$seed_mode\"/" "$CONFIG_FILE";

chown -R 100:1000 /penumbra-config/testnet_data/node0/cometbft;

if [[ "$new_installation" = 1 ]] ; then
    echo "New installation -"
    #import wallet
    echo "importing Address from key"
    printf  "$WALLET_PHRASE" | pcli --home $PENUMBRA_PCLI_HOME init soft-kms import-phrase
    validator_upload_needed=1
fi

if [[ "$ENABLE_VALIDATOR" == "true" ]] ; then
    echo "Enabling Validator"
    sed -i -e "s#^enabled.*#enabled = true#"  $PENUMBRA_PCLI_HOME/validator.toml
    validator_upload_needed=1
fi

if [[ "$validator_upload_needed" == "1" ]] ; then 
    validator_upload
fi

#
echo "Pcli View Sync"
pcli --home $PENUMBRA_PCLI_HOME view sync
echo "Pcli Address"
pcli --home $PENUMBRA_PCLI_HOME view address
echo "Pcli Balance"
pcli --home $PENUMBRA_PCLI_HOME view balance
exit 0;

function validator_upload() {
    echo "Pcli Validator key update"
    EPOCH=$(date +%s)
    pcli --home $PENUMBRA_PCLI_HOME validator definition template --tendermint-validator-keyfile /penumbra-config/testnet_data/node0/cometbft/config/priv_validator_key.json --file $PENUMBRA_PCLI_HOME/validator.toml 
    sed -i -e "s#^sequence_number.*#sequence_number = $EPOCH#"  $PENUMBRA_PCLI_HOME/validator.toml
    sed -i -e "s#^name.*#name = \"saikat\"#"  $PENUMBRA_PCLI_HOME/validator.toml
    pcli --home $PENUMBRA_PCLI_HOME validator definition upload --file $PENUMBRA_PCLI_HOME/validator.toml
    if [[ "$ENABLE_VALIDATOR" == "true" && "$DELEGATE_NOW" == "true" ]] ; then
        echo "Pcli Delegation ${DELGATION_AMOUNT:1}penumbra"
        VALIDATOR_IDENTITY="$(pcli --home $PENUMBRA_PCLI_HOME validator identity)"
        pcli --home $PENUMBRA_PCLI_HOME tx delegate "${DELGATION_AMOUNT:1}penumbra" --to $VALIDATOR_IDENTITY
    fi
}

