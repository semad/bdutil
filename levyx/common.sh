#!/bin/bash
#
# common.sh
# 
# Copyright (C) 2013-2015, Levyx, Inc.
#
# NOTICE:  All information contained herein is, and remains the property of
# Levyx, Inc.  The intellectual and technical concepts contained herein are
# proprietary to Levyx, Inc. and may be covered by U.S. and Foreign Patents,
# patents in process, and are protected by trade secret or copyright law.
# Dissemination of this information or reproduction of this material is
# strictly forbidden unless prior written permission is obtained from Levyx,
# Inc.  Access to the source code contained herein is hereby forbidden to
# anyone except current Levyx, Inc. employees, managers or contractors who
# have executed Confidentiality and Non-disclosure agreements explicitly
# covering such access.
#

# Variables for gcloud setting, and the path to access gcloud
USER=hadoop
ZONE=us-central1-c
export PATH=$PATH:~/google-cloud-sdk/bin/

## Where to get bdutil from
BDUTIL_URL=https://github.com/levyx/bdutil.git

# Bucket used to set up ssh keys.
BUCKET=levyx-test-data
LEVYX_SHARE=levyx-share

PUBLISH_PATH=/var/www/html

# Variables for gcloud setting, and the path to access gcloud
THIS_ENV=${VM_PREFIX}_env
THIS_BDUTIL_CONF=${VM_PREFIX}_bdutil_conf

SUPPRESS_TRAPPED_ERRORS=0
CAUGHT_ERROR=0
BDUTIL_CMD=./bdutil

RESIZE_PARTITION='echo -e "d\nd 1\nn\n \n \n \n \nw" | sudo /usr/sbin/fdisk /dev/sda'
CHANGE_MNT_OWNERSHIP="sudo chown -R $USER:$USER /mnt/[ep]d[0-9]"
CHANGE_SYSCTL_FSLIMIT='echo "fs.file-max=100000" | sudo tee --append /etc/sysctl.conf'
CHANGE_SECLIMITS_FSLIMIT='echo -e "* soft nproc 65535\n* hard nproc 65535\n* soft nofile 65535\n* hard nofile 65535" | sudo tee --append /etc/security/limits.conf'
RESIZE_FS='sudo xfs_growfs -d /'


function handle_error() {
  # Save the error code responsible for the trap.
  local errcode=$?
  local bash_command=${BASH_COMMAND}
  local lineno=${BASH_LINENO[0]}

  CAUGHT_ERROR=1

  if (( ${SUPPRESS_TRAPPED_ERRORS} )); then
    echo "Continuing despite trapped error with code '${errcode}'"
    return
  fi

  # Wait for remaining async things to finish, otherwise our error message may
  # get lost among other logspam.
  wait
  echo "Command failed: ${bash_command} on line ${lineno}."
  echo "Exit code of failed command: ${errcode}"

  exit ${errcode}
}


function save_env() {
  cat <<EOF > ${THIS_ENV}
  # Run started at `date` with these job variables
  BEGIN_TIME=`date +%s`
  THIS_JOB_NAME=${JOB_NAME}
  THIS_BUILD_NUMBER=${BUILD_NUMBER}

  # Variables used by Jenkins Jobs
  JENKINS_PATH=./utils/cloud/gcp/jenkins
  JENKINS_BASH_OPTIONS=-xe

  USER=$USER
  ZONE=$ZONE
  BUCKET=$BUCKET

  BDUTIL_URL=$BDUTIL_URL
  LEVYX_SHARE=$LEVYX_SHARE

  RUNTIME_ONLY=$RUNTIME_ONLY
  BASE_IMAGE=$BASE_IMAGE
  VM_PREFIX=$VM_PREFIX
  NUM_NODES=$NUM_NODES
  PREEMPTIBLE_VAL=$PREEMPTIBLE_VAL

  MASTER_MACHINE_TYPE=$MASTER_MACHINE_TYPE
  MASTER_BOOT_DISK_SIZE=$MASTER_BOOT_DISK_SIZE
  MASTER_SSD_COUNT=$MASTER_SSD_COUNT
 
  WORKER_MACHINE_TYPE=$WORKER_MACHINE_TYPE
  WORKER_BOOT_DISK_SIZE=$WORKER_BOOT_DISK_SIZE
  WORKER_SSD_COUNT=$WORKER_SSD_COUNT

  ATTACHED_PD_TYPE=$ATTACHED_PD_TYPE
  PDSIZE=$PDSIZE
  DG_SCALE=$DG_SCALE

  PUBLISH_PATH=$PUBLISH_PATH

  DEPLOY_LS_GIT_BRANCH=$LS_GIT_BRANCH
  DEPLOY_BD_GIT_BRANCH=$BD_GIT_BRANCH
  DEPLOY_DG_SCALE=$DG_SCALE
  SALT=1
EOF
}

verify_input() {
  MASTER_CPU=${MASTER_MACHINE_TYPE##*-*-}
  WORKER_CPU=${WORKER_MACHINE_TYPE##*-*-}

  total_attached_disk_size=$(( ($NUM_NODES + 1) * (PDSIZE * WORKER_PD_COUNT) ))
  total_num_cpu=$(( $NUM_NODES * $WORKER_CPU + $MASTER_CPU ))
#  data_total_size=$(( 22 * ${DG_SCALE} / 10 ))
#  echo "total_attached_disk_size = $total_attached_disk_size versus data_total_size=$data_total_size"
#  echo "total_num_cpu = $total_num_cpu"
#
#  if [[ $data_total_size -gt $total_attached_disk_size ]]
#  then
#    exit
#  fi
}

checkout_bdutil() {
  # Checkout latest bdutil
  if [ ! -d bdutil ]
  then
    git clone $BDUTIL_URL
  fi

  # Checkout Branch
  pushd bdutil; git checkout $BD_GIT_BRANCH; popd;
}

clean_up() {
  # Checkout latest bdutil
  if [  -d bdutil ]
  then
    rm -rf bdutil 
  fi

  if [ -e $THIS_BDUTIL_CONF ]
  then 
    rm $THIS_BDUTIL_CONF 
  fi

  if [ -e $THIS_ENV ]
  then 
    rm $THIS_ENV
  fi
}

generate_bdutil_config() {
  [ -e ${THIS_BDUTIL_CONF} ] && rm ${THIS_BDUTIL_CONF}
  # Generate Config file
  [[ "$DEBUG" == "true" ]] &&  GENERAL_OPTIONS+=" -D "

  GENERAL_OPTIONS+=" -f -i $BASE_IMAGE -b $BUCKET -P $VM_PREFIX -n $NUM_NODES -z $ZONE"

#  if [[ "${ATTACHED_PD_TYPE}" != "NONE" ]]
#  then
#    PD_COUNT=1
#    PD_DISK_OPTIONS=" -d"
  #  PD_DISK_OPTIONS+=" --master_attached_pd_type $ATTACHED_PD_TYPE --master_attached_pd_size_gb $PDSIZE"
  #  PD_DISK_OPTIONS+=" --worker_attached_pds_type $ATTACHED_PD_TYPE --worker_attached_pds_size_gb $PDSIZE"
#  fi

  MASTER_OPTIONS=" -M $MASTER_MACHINE_TYPE --master_boot_disk_size_gb $MASTER_BOOT_DISK_SIZE"
  MASTER_OPTIONS+=" --master_local_ssd_count $MASTER_SSD_COUNT"

  WORKER_OPTIONS=" -m $WORKER_MACHINE_TYPE --worker_boot_disk_size_gb $WORKER_BOOT_DISK_SIZE"
  WORKER_OPTIONS+=" --worker_local_ssd_count $WORKER_SSD_COUNT"

  HADOOP_OPTIONS="-F hdfs -e hadoop2_env.sh -e ./extensions/levyx/levyx_env.sh"

  CMD_OPTIONS="generate_config $THIS_BDUTIL_CONF"
  BDUTIL_COMMAND="./bdutil $GENERAL_OPTIONS $MASTER_OPTIONS $WORKER_OPTIONS $PD_DISK_OPTIONS $HADOOP_OPTIONS $CMD_OPTIONS"
  echo "$BDUTIL_COMMAND"
  $BDUTIL_COMMAND
}

run_bdutil_create() {
  echo "************************************** Creating instances!"
  ./bdutil -f -e  ${THIS_BDUTIL_CONF} create
}

run_bdutil_deploy() {
  echo "************************************** run_command_steps!"
  ./bdutil -f -e  ${THIS_BDUTIL_CONF} run_command_steps
}

run_bdutil_delete() {
  echo "************************************** Deleting instances!"
  ./bdutil -f -e  ${THIS_BDUTIL_CONF} delete
}

upload_env() {
  local url="gs://${BUCKET}/${THIS_ENV}" 
  echo "************************************** Uploading Bucket files!"
  gsutil cp ${THIS_ENV} gs://$BUCKET/
  RC=$?
  if [ "$RC" -ne "0" ]
  then
    echo "could upload $url"
    exit -1
  fi
}

verify_env_file() {
  local url="gs://${BUCKET}/${THIS_ENV}" 
  echo "************************************** Check if Bucket file exitst!"
  set +e
  gsutil cp $url /tmp
  RC=$?
  ((EXIT_ON_ERR_FLAG)) && set -e

  if [ "$RC" -eq "0" ]
  then
    echo "$url Already Exists!"
    exit -1
  fi
}


load_env() {
  local url="gs://${BUCKET}/${THIS_ENV}" 
  echo "************************************** Downloading Bucket files!"
  gsutil cp $url .
  RC=$?
  if [ "$RC" -ne "0" ]
  then
    echo "could not find $url"
    exit -1
  fi
  pwd
  ls -l
  source ./${THIS_ENV}
}

delete_env_files() {
  echo "************************************** Removing Bucket files!"
  gsutil rm  gs://$BUCKET/${THIS_ENV}
}

interesting_ports() {
  echo "************************************** Master node interesting ports!"
  gcloud compute instances list | grep ${VM_PREFIX}-m | tr -s " " | cut -d' ' -f 1,5 | while read -r -a array
  do
    name=${array[0]}
    ip=${array[1]}
    echo -e "\tFor the instance:$name Hadoop UI at http://$ip:50070"
  done
}

copy_development_ssh_keys() {
  echo "************************************** copy ssh keys"
  path=/opt/levyx
  script=ssh_keys/*
  file=$path/$script
  gcloud compute ssh ${USER}@${VM_PREFIX}-m --zone $ZONE --command "chmod u+w ~/.ssh/*"
  gcloud compute copy-files --zone $ZONE $file ${USER}@${VM_PREFIX}-m:~/.ssh
  gcloud compute ssh ${USER}@${VM_PREFIX}-m --zone $ZONE --command "chmod 400 ~/.ssh/id_rsa"
}

copy_local_ssh_keys() {
  echo "************************************** copy ssh keys"
  path=~/.ssh
  script=id_rsa*
  file=$path/$script
  gcloud compute ssh ${USER}@${VM_PREFIX}-m --zone $ZONE --command "chmod u+w ~/.ssh/*"
  gcloud compute ssh ${USER}@${VM_PREFIX}-m --zone $ZONE --command ' echo -e "Host github.com\n\tStrictHostKeyChecking no\n" >> ~/.ssh/config ' 
  gcloud compute copy-files --zone $ZONE $file ${USER}@${VM_PREFIX}-m:~/.ssh
  gcloud compute ssh ${USER}@${VM_PREFIX}-m --zone $ZONE --command "chmod 400 ~/.ssh/id_rsa"
}

clone_levyx_spark() {
  echo "************************************** clone levyx spark"
  local br=$1
  local ofile=./clone_le.sh
  cat << EOF > $ofile 
     [ -d "~./.ivy2" ] && find ~/.ivy2 -type f -delete
     [ -d "~./.m2" ] && find ~/.m2 -type f -delete
     [ -d "./levyx-spark" ] && rm -rf levyx-spark
     echo "##################### git clone "
     git clone git@github.com:levyx/levyx-spark.git  || {  echo "git clone failed";  exit -1; }
     echo "##################### git checkout $br "
     pushd levyx-spark
     git checkout $br || { echo "git checkout failed"; exit -1;}
     popd
EOF

  gcloud compute copy-files $ofile ${USER}@${VM_PREFIX}-m: --zone $ZONE
  gcloud compute ssh ${USER}@${VM_PREFIX}-m --zone $ZONE --command "bash -xe $ofile $LS_GIT_BRANCH"
  rm $ofile 
}


build_levyx_spark() {
  local ofile=./build_le.sh
  cat << EOF > $ofile 
    #     export LD_LIBRARY_PATH=$HOME}/levyx-spark/xenon/dist/lib
    #     export SBT_OPTS="-Xmx6G -XX:MaxMetaspaceSize=2G -XX:MaxPermSize=2G -XX:+CMSClassUnloadingEnabled"

    # Modify the environment for JAVA_HOME
    echo "export JAVA_HOME=\`./levyx-spark/xenon/dist/src/C/javahome.sh\`" >> .bashrc
    . .bashrc
    #
    echo "##################### Run make-distribution "
    pushd ./levyx-spark/xenon/dist
    bash -x make-distribution.sh
    popd

    pushd ./levyx-spark/spark/
    echo "##################### TEMP! - Run sbt clean"
    build/sbt clean
    echo "##################### TEMP! - Run sbt assembly"
    build/sbt assembly
    popd
EOF

  gcloud compute copy-files $ofile ${USER}@${VM_PREFIX}-m: --zone $ZONE
  gcloud compute ssh ${USER}@${VM_PREFIX}-m --zone $ZONE --command "bash -xe $ofile"
  rm $ofile 
}


deploy_levyx_spark() {
  local ofile=./deploy_le.sh
  local sparkDistPath=./levyx-spark/spark/dist

  cat << EOF > $ofile 
    echo "##################### Deploy Levyx Spark"
    # Set up spark: copy dist directory, set up conf/slaves, modify .bashrc file" 
    echo "#" > $sparkDistPath/conf/slaves 
    echo -e "SPARK_DRIVER_MEMORY=24G\nSPARK_EXECUTOR_MEMORY=24G\nSPARK_LOCAL_DIRS=/mnt/ed1" > $sparkDistPath/conf/spark-env.sh 
 
    echo "cd ${sparkDistPath}; . ./bin/xenon-env.sh; cd ~" >> ~/.bashrc 
    for ((i=0; i<${NUM_NODES}; i++)) 
    do 
      echo "${USER}@${VM_PREFIX}-w-\${i}" >> ${sparkDistPath}/conf/slaves 
      ssh ${USER}@${VM_PREFIX}-w-\${i} "mkdir -p ${sparkDistPath}" 
      scp -r ${sparkDistPath}/* ${USER}@${VM_PREFIX}-w-\${i}:${sparkDistPath} 
 
      ssh ${USER}@${VM_PREFIX}-w-\${i} "echo cd ${sparkDistPath} >> ~/.bashrc" 
      ssh ${USER}@${VM_PREFIX}-w-\${i} "echo source ./bin/xenon-env.sh >> ~/.bashrc" 
      ssh ${USER}@${VM_PREFIX}-w-\${i} "echo cd ~ >> ~/.bashrc" 
    done 
EOF

  gcloud compute copy-files $ofile ${USER}@${VM_PREFIX}-m: --zone $ZONE
  gcloud compute ssh ${USER}@${VM_PREFIX}-m --zone $ZONE --command "bash -xe $ofile"
  rm $ofile 
}


build_dsdgen() {
  local ofile=./build_dsdgen.sh

  cat << EOF > $ofile 
    echo "##################### build dsgen on master"
    file=DSTools.zip
    rm -rf $file TPCDSVersion1.3.1
    gsutil cp gs://levyx-share/\$file .
    unzip \$file
    make -C TPCDSVersion1.3.1/tools

    echo "##################### copy dsgen into workers"
    for ((i=0; i<${NUM_NODES}; i++))
    do
      scp -r TPCDSVersion1.3.1 ${user}@${VM_PREFIX}-w-\${i}:
    done
EOF

  gcloud compute copy-files $ofile ${USER}@${VM_PREFIX}-m: --zone $ZONE
  gcloud compute ssh ${USER}@${VM_PREFIX}-m --zone $ZONE --command "bash -xe $ofile"
  rm $ofile 
}


gen_n_load_data_orig() {
  local file=gen_n_load_data_original.sh
  local path=../common/$file

   echo "************************************** run $file to generate and load data into hdfs"
   local NUM_MASTER_CPU=${MASTER_MACHINE_TYPE##*-*-}
   local NUM_WORKER_CPU=${WORKER_MACHINE_TYPE##*-*-}

   # first balance the number for num CPU
   local parts_per_cpu=$(( TOTAL_NUM_PARTITIONS / NUM_WORKER_CPU ))
   local num_partitions=$(( parts_per_cpu * NUM_WORKER_CPU ))
   local parts_per_node=$(( num_partitions / NUM_NODES ))
   local num_partitions=$(( parts_per_node * NUM_NODES ))

   local begin_index=0
   local end_index=0
   local ssh_cmd=""
   for (( i=0; i<$NUM_NODES; i++))
   do
     begin_index=$(($i * $parts_per_node + 1 ))
     end_index=$(( (i + 1) * $parts_per_node  ))
     echo "worker $i do: $begin_index, $end_index"
     gcloud compute copy-files --zone $ZONE $path ${USER}@${VM_PREFIX}-w-$i:~/
     ssh_cmd="bash -xe $file -m /mnt -b $begin_index -e $end_index -s $DG_SCALE -t $num_partitions"
     ssh_cmd+="  -c $NUM_WORKER_CPU -w $i"
     ${MULTIPLE_FILE_PUT_FLAG} && ssh_cmd+=" -p"
     gcloud_cmd="gcloud compute ssh ${USER}@${VM_PREFIX}-w-$i --zone $ZONE --command $ssh_cmd"  
     echo "gcloud_cmd is: $gcloud_cmd"
     $gcloud_cmd &
   done
   wait
}


gen_n_load_data_stripe() {
  local file=gen_n_load_data_stripe.sh
  local path=../common/$file
  HDFS_SIZE_FACTOR=1

  echo "************************************** run $file to generate and load data into hdfs"
  local NUM_MASTER_CPU=${MASTER_MACHINE_TYPE##*-*-}
  local NUM_WORKER_CPU=${WORKER_MACHINE_TYPE##*-*-}

  worker_node=0
  while [ $worker_node -lt $NUM_NODES ]
  do
    gcloud compute copy-files --zone $ZONE $path ${USER}@${VM_PREFIX}-w-$worker_node:~/
    local ssh_cmd="bash -e ./$file -s $DG_SCALE -t $NUM_WORKER_CPU -n $NUM_NODES -w $worker_node -f $HDFS_SIZE_FACTOR"
    ${MULTIPLE_FILE_PUT_FLAG} && ssh_cmd+=" -p"
    gcloud_cmd="gcloud compute ssh ${USER}@${VM_PREFIX}-w-$worker_node --zone $ZONE --command $ssh_cmd"
    echo "gcloud_cmd is: $gcloud_cmd"
    $gcloud_cmd &
    worker_node=$(( $worker_node + 1 ))
  done
  wait
}


run_tpc() {
  local file=run_tpc.sh
  local path=../common/$file
  local SSPBranch=run-on-cloud

  echo "************************************** run run_tpc.sh"
  gcloud compute copy-files $path ${USER}@${VM_PREFIX}-m: --zone $ZONE
  gcloud compute ssh ${USER}@${VM_PREFIX}-m --zone $ZONE --command "bash -xe $file -n $NUM_NODES -b $SSPBranch -p $VM_PREFIX"
}

run_tpc_xenon() {
  local file=run_xenon_tpc.sh
  local path=../common/$file

  echo "************************************** run run_tpc.sh"
  gcloud compute copy-files $path ${USER}@${VM_PREFIX}-m: --zone $ZONE
  gcloud compute ssh ${USER}@${VM_PREFIX}-m --zone $ZONE --command "bash -xe $file -s $DG_SCALE -p $VM_PREFIX"
}


function do_cluster() {
  cmd=$@
  local i=0

  echo "cmd is $cmd"
  gcloud compute ssh ${USER}@${VM_PREFIX}-m --zone $ZONE --command "$cmd" &
  for ((i=0; i<${NUM_NODES}; i++))
  do
    gcloud compute ssh ${USER}@${VM_PREFIX}-w-${i} --zone $ZONE --command "$cmd" &
  done
  wait
}

function sudo_cluster() {
  cmd=$@
  local i=0
  extra_flags="--zone $ZONE --ssh-flag=-tt"

  echo "cmd is $cmd"
  gcloud compute ssh ${USER}@${VM_PREFIX}-m $extra_flags --command "$cmd" &
  for ((i=0; i<${NUM_NODES}; i++))
  do
    gcloud compute ssh ${USER}@${VM_PREFIX}-w-${i} $extra_flags --command "$cmd" &
  done
  wait
}

function wait_for_ssh() {
  trap handle_error ERR
  local node=$1
  local max_attempts=10
  local sleep_time=15
  local i=0

  for (( i=0; i < ${max_attempts}; i++ )); do
    if   gcloud compute ssh ${USER}@${node} --zone $ZONE --command 'exit 0'; then
      return 0
    else
      # Save the error code responsible for the trap.
      local errcode=$?
      echo "'${node}' not yet sshable (${errcode}); sleeping ${sleep_time}."
      sleep ${sleep_time}
    fi
  done
  echo "Node '${node}' did not become ssh-able after ${max_attempts} attempts"
  return ${errcode}
}

function reset_cluster() {
  echo "************************************** Hard reset of instances!"
  local i=0
  gcloud compute ssh ${VM_PREFIX}-m --zone $ZONE --command "/bin/sync" &
  for ((i=0; i<${NUM_NODES}; i++))
  do
    gcloud compute ssh ${VM_PREFIX}-w-${i} --zone $ZONE --command "/bin/sync" &
  done
  wait

  gcloud compute instances reset ${VM_PREFIX}-m --zone $ZONE &
  for ((i=0; i<${NUM_NODES}; i++))
  do
    gcloud compute instances reset ${VM_PREFIX}-w-${i} --zone $ZONE &
  done
  wait

  wait_for_ssh ${VM_PREFIX}-m
  for ((i=0; i<${NUM_NODES}; i++))
  do
    echo "i is $i"
    wait_for_ssh ${VM_PREFIX}-w-${i}  
  done
}

function show_gcloud_instances() {
  local msg=$1
  echo "************************************** $msg"
  gcloud compute instances list
}

generate_perf_html() {
  local i=0
  PUBLISH_PATH+=/${JOB_NAME}/${BUILD_NUMBER}
  mkdir -p ${PUBLISH_PATH}
  cp ${THIS_BDUTIL_CONF} ${PUBLISH_PATH}
  cp ${THIS_ENV} ${PUBLISH_PATH}
  GEN_HTML_CMD="python $JENKINS_PATH/../index_graphs.py -v $VM_PREFIX -n $NUM_NODES"
  for i in 5 20 40
  do
    fname=0_last_${i}_minutes.html
    $GEN_HTML_CMD -f -$i -U min -o ${PUBLISH_PATH}/${fname}
  done

  for i in 1 4 12 16
  do
    fname=1_last_${i}_hours.html
    $GEN_HTML_CMD -f -$i -U hour -o ${PUBLISH_PATH}/${fname}
  done

  for i in 1 2 3 5 7
  do
    fname=2_last_${i}_days.html
    $GEN_HTML_CMD -f -$i -U day -o ${PUBLISH_PATH}/${fname}
  done
  echo "Watch results here at http://10.0.0.30:/${JOB_NAME}/${BUILD_NUMBER}"
}
