#!/usr/bin/env bash

msg_err() {
    echo "ERROR: $1"
    exit 1
}

create_node_list() {
    local current_node=$1
    local last_node
    let last_node=current_node+$2-1
    local mapr_nodes="["

    while [ $current_node -le $last_node ]; do
        if [ $current_node -eq $last_node ]; then
            mapr_nodes="$mapr_nodes\"$3$current_node\"]"
        else
            mapr_nodes="$mapr_nodes\"$3$current_node\", "
        fi

        let current_node=$current_node+1
    done

    RESULT=$mapr_nodes
}

wait_for_connection() {
    local retries=0
    while [ $retries -le 20 ]; do
        sleep 2
        curl --silent -k -I $1 && return
        let retries=$retries+1
        echo "Retry: $retries"
    done
    msg_err "Connection to $1 was not able to be established"
}

if [ -f /opt/mapr/conf/mapr-clusters.conf ]; then
    echo "MapR is already installed; Not running Stanza again."
    exit 0
fi

# TODO: File should go away and logic should be put in mapr-setup
MEP=$1
CLUSTER_NAME=$2
MAPR_PASSWORD=$3
THREE_DOT_SUBNET_PRIVATE=$4
START_OCTET=$5
NODE_COUNT=$6
SERVICE_TEMPLATE=$7
RESOURCE_GROUP=$8

RESULT=""

echo "MEP: $MEP"
echo "CLUSTER_NAME: $CLUSTER_NAME"
echo "MAPR_PASSWORD: <hidden>"
echo "THREE_DOT_SUBNET_PRIVATE: $THREE_DOT_SUBNET_PRIVATE"
echo "START_OCTET: $START_OCTET"
echo "NODE_COUNT: $NODE_COUNT"
echo "SERVICE_TEMPLATE: $SERVICE_TEMPLATE"
echo "RESOURCE_GROUP: $RESOURCE_GROUP"

STANZA_URL="https://raw.githubusercontent.com/mapr/mapr-cloud-templates/master/1.6/azure/mapr-core.yml"
STATUS="SUCCESS"

MAPR_HOME=/opt/mapr/installer
MAPR_USER=mapr
# TODO: Need to get the core version in here. Might need to inspect this machine to see what packages are installed
MAPR_CORE=5.2.1

create_node_list $START_OCTET $NODE_COUNT $THREE_DOT_SUBNET_PRIVATE
NODE_LIST=$RESULT
echo "NODE_LIST: $NODE_LIST"

. $MAPR_HOME/build/installer/bin/activate

# TODO: SWF: I don't see REPLACE_THIS in properties.json anymore. Not needed?
#H=$(hostname -f) || msg_err "Could not run hostname"
#sed -i -e "s/REPLACE_THIS/$H/" MAPR_HOME/data/properties.json
service mapr-installer start || msg_err "Could not start mapr-installer service"
wait_for_connection https://localhost:9443 || msg_err "Could not run curl"

echo "Installer state: $?" > /tmp/mapr_installer_state

if [ "$SERVICE_TEMPLATE" == "custom-configuration" ]; then
    echo "MapR custom configuration selected; Log in to MapR web UI to complete installation."
    exit 0
fi

input=$MAPR_HOME/stanza_input.yml
rm -f $input
touch $input
chown $MAPR_USER:$MAPR_USER $input || msg_err "Could not change owner to $MAPR_USER"

echo "environment.mapr_core_version=$MAPR_CORE " >> $input
echo "config.ssh_id=$MAPR_USER " >> $input
echo "config.ssh_password=$MAPR_PASSWORD " >> $input
#echo "config.ssh_key_file=/opt/mapr/installer/data/installer_key " >> $input
echo "config.mep_version=$MEP " >> $input
echo "config.cluster_name=$CLUSTER_NAME " >> $input
echo "config.hosts=$NODE_LIST " >> $input
echo "config.services={\"${SERVICE_TEMPLATE}\":{}} " >> $input
echo "config.provider.config.resource_group=$RESOURCE_GROUP " >> $input

CMD="cd $MAPR_HOME; bin/mapr-installer-cli install -f -n -t $STANZA_URL -u $MAPR_USER:$MAPR_PASSWORD@localhost:9443 -o @$input"
echo $CMD > /tmp/cmd

sudo -u $MAPR_USER bash -c "$CMD"
RUN_RSLT=$?
rm -f $input
if [ $RUN_RSLT -ne 0 ]; then
    msg_err "Could not run installation: $RUN_RSLT"
fi
