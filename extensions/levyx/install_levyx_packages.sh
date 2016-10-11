#sudo yum -y update
# Only for yum based 
#install_application epel-release
#install_application tree vim wget sysstat mdadm lsof screen wget fuser psmisc 
#install_application net-tools nmap-ncat collectd wget git emacs
#gcloud components update

yum -y install epel-release
yum -y install tree vim wget sysstat mdadm lsof screen wget psmisc net-tools nmap-ncat collectd git dstat

# Needed for compiling 
yum -y install gcc zlib-devel zip unzip flex byacc
#yum -y install maven emacs nginx

# Set time display to America/Los_Angeles
echo "export TZ=America/Los_Angeles" >> /etc/bashrc

cat << HEREDOC1 > /etc/collectd.conf
FQDNLookup   false
LoadPlugin syslog
LoadPlugin cpu
LoadPlugin disk
LoadPlugin interface
LoadPlugin memory
LoadPlugin write_graphite
<Plugin cpu>
  ReportByCpu false
  ReportByState true
</Plugin>
<Plugin disk>
        Disk "/^[hs]d[a-f][0-9]?$/"
</Plugin>
<Plugin interface>
        Interface "eth0"
</Plugin>
<Plugin memory>
        ValuesAbsolute false
        ValuesPercentage true
</Plugin>
<Plugin write_graphite>
  <Node "grf0">
    Host "104.154.91.143"
    Port "2003"
    Protocol "tcp"
    LogSendErrors true
    Prefix ""
    Postfix ""
    StoreRates true
    AlwaysAppendDS false
    EscapeCharacter "_"
  </Node>
</Plugin>
HEREDOC1

setenforce permissive
cat << HEREDOC2 > /etc/selinux/config
SELINUX=permissive
SELINUXTYPE=targeted
HEREDOC2
# Start collectd
systemctl enable collectd
systemctl start collectd

# Modify sshd defaults 
sed -i 's/ClientAliveInterval 420/ClientAliveInterval 0/' /etc/ssh/sshd_config
systemctl restart sshd

# Install sbt
/usr/local/bin/gsutil cp gs://levyx-share/sbt-0.13.0.rpm .
yum install -y ./sbt-0.13.0.rpm

# Install scala
/usr/local/bin/gsutil cp gs://levyx-share/scala-2.11.2.tgz .
tar xzf scala-2.11.2.tgz -C /opt

# Modify /etc/sudouers 
chmod +w /etc/sudoers
sed -i 's/Defaults\s\+requiretty/#Defaults requiretty/' /etc/sudoers
sed -i 's/Defaults\s\+!visiblepw/#Defaults !visiblepw/' /etc/sudoers
chmod -w /etc/sudoers
