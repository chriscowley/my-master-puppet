class basenode {
  if $osfamily == 'RedHat' {
    include yumrepos
    include yumrepos::epel
  }
  class {'htop':
  }
  include vim
  include puppet::agent
  class { 'nethogs':
  }
  class { 'mosh':
  }
}

class ubuntunode {
  class { 'htop': }
}

class glusternode {
  include basenode
  include yumrepos::gluster

  # Create Logical Volume and base XFS filesystem on each node
  volume_group { "vg0":
    ensure           => present,
    physical_volumes => "/dev/vdb",
    require          => Physical_volume["/dev/vdb"]
  }
  physical_volume { "/dev/vdb":
    ensure => present
  }
  logical_volume { "gv0":
    ensure       => present,
    require     => Volume_group['vg0'],
    volume_group => "vg0",
    size         => "7G",
  }
  file { [ '/export', '/export/gv0']:
    seltype => 'usr_t',
    ensure  => directory,
  }
  package { 'xfsprogs': ensure => installed 
  }
  filesystem { "/dev/vg0/gv0":
    ensure   => present,
    fs_type  => "xfs",
    options  => "-i size=512",
    require => [Package['xfsprogs'], Logical_volume['gv0'] ],
  }

  # Mount XFS file system and create the bricks
#  exec { 'lvcreate /dev/vg0/gv0':
#    command => '/sbin/lvcreate -L 6G -n gv0 vg0',
#    creates => '/dev/vg0/gv0',
#    notify  => Exec['mkfs /dev/vg0/gv0'],
#  }
#  exec { 'mkfs /dev/vg0/gv0':
#    command     => '/sbin/mkfs.xfs -i size=512 /dev/vg0/gv0',
#    require     => [ Package['xfsprogs'], Exec['lvcreate /dev/vg0/gv0'] ],
#    refreshonly => true,
#  }
  mount { '/export/gv0':
    device  => '/dev/vg0/gv0',
    fstype  => 'xfs',
    options => 'defaults',
    ensure  => mounted,
#    require => [ Exec['mkfs /dev/vg0/gv0'], File['/export/gv0'] ],
    require => [ Filesystem['/dev/vg0/gv0'], File['/export/gv0'] ],
  }
  class { 'glusterfs::server':
    peers => $::hostname ? {
      'gluster1' => '192.168.1.38', # Note these are the IPs of the other nodes
      'gluster2' => '192.168.1.84',
    },
  }
  glusterfs::volume { 'gv0':
    create_options => 'replica 2 192.168.1.38:/export/gv0 192.168.1.84:/export/gv0',
    require        => Mount['/export/gv0'],
  }
}

node 'razor.chriscowley.local' {
  include basenode
  class { 'sudo':
    config_file_replace => false,
  }
  include razor
}
node 'puppet.chriscowley.local' {
  include basenode
  include puppet
# include yumrepos::cloudera
#  include yumrepos::epel

}

node 'gluster1' {
  include glusternode
  file { '/var/www': ensure => directory }
  glusterfs::mount { '/var/www':
    device => $::hostname ? {
      'gluster1' => '192.168.1.84:/gv0',
    }
  }
}

node 'gluster2' {
  include glusternode
  file { '/var/www': ensure => directory }
  glusterfs::mount { '/var/www':
    device => $::hostname ? {
      'gluster2' => '192.168.1.38:/gv0',
    }
  }

}

node 'backup.chriscowley.local' {
  include basenode
  class { 'rdiff-backup':
  }
  class {'nfs::server':
  }
  file { '/srv/backup/nadege':
    ensure => directory,
    owner  => 'nadege',
    group  => 'nadege',
  }
  file { '/srv/backup/anne':
    ensure => directory,
    owner  => 'anne',
    group  => 'anne',
  }
  file { '/srv/backup/timothy':
    ensure => directory,
    owner  => 'timothy',
    group  => 'timothy',
  }
  file { '/srv/backup/nicolas':
    ensure => directory,
    owner  => 'nicolas',
    group  => 'nicolas',
  }
}

node 'mirror.chriscowley.local' {
  include basenode
  cron::daily {
    'update_local_centos_mirror':
      minute  => '2',
      hour    => '4',
      user    => 'nginx',
      require => [File['/var/www/mirror'],File['/usr/local/bin/centos-mirror.sh']],
#      command => 'rsync -art --progress rsync://mirror.ovh.net/ftp.centos.org/6/os/x86_64 /var/www/mirror/centos/6/os/  --bwlimit 200',
      command => '/usr/local/bin/centos-mirror.sh',
  }
  cron::daily { 'update_local_epel_mirror':
    minute  => '12',
    hour    => '4',
    user    => 'nginx',
    require => [File['/var/www/mirror'],File['/usr/local/bin/epel-mirror.sh']],
    command => '/usr/local/bin/epel-mirror.sh',
  }
  file { '/var/www/mirror':
    ensure => directory,
    owner  => 'nginx',
  }
  file {'/usr/local/bin/centos-mirror.sh':
    owner => 'root',
    mode  => 'ga=rx,u=rwx',
    source => 'puppet:///modules/scripts/centos-mirror.sh',
  }
  file {'/usr/local/bin/epel-mirror.sh':
    owner => 'root',
    mode  => 'ga=rx,u=rwx',
    source => 'puppet:///modules/scripts/epel-mirror.sh',
  }
#  class { 'nginx': }
#  nginx::resource::vhost { 'mirror.chriscowley.local':
#    ensure   => present,
#    www_root => '/var/www/mirror.chriscowley.local',
#  }

}

node 'store.chriscowley.local' {
  include basenode
  class {'nfs::server':
  }
}

node 'monitor.chriscowley.local' {
  include basenode
#  class { 'php::mod_php5':
#  }
#  apache_httpd { 'prefork':
#      modules => [ 'mime' ],
#  }

  class { 'nagios::client':
    service_use => 'generic-service,nagiosgraph-service',
  }
  class { 'nagios::server':
    process_performance_data => '1',
        service_perfdata_file    => '/var/log/nagios/service_perfdata.log',
        service_perfdata_file_template => '$LASTSERVICECHECK$||$HOSTNAME$||$SERVICEDESC$||$SERVICEOUTPUT$||$SERVICEPERFDATA$',
        service_perfdata_file_processing_interval => '30',
        service_perfdata_file_processing_command => 'process-service-perfdata-nagiosgraph',
  }
}

node 'lab01' {
  include basenode
#  class { 'yumrepos::rdo':
#  }
  package { 'nmap':
    ensure => latest,
  }
}

node 'webdev.chriscowley.local' {
  include basenode
}

node 'db.chriscowley.local' {
  include basenode
  class { 'mysql::server':
    config_hash => { 'root_password' => 'mysqlpassword' },
  }
  mysql::server::config { 'basic_config':
    settings => {
      'mysqld' => {
        'bind-address' => '192.168.1.104',
      }
    }
  }
  mysql::db { 'torrentflux':
    user => 'torrentflux',
    password => 'torrentflux',
    host     => 'torrents.chriscowley.local',
    grant    => ['all'],
  }
  mysql::db { 'gitlab':
    user => 'gitlab',
    password => 'gitlab',
    host     => 'torrents.chriscowley.local',
    grant    => ['all'],
  }
  

}

node 'ext.chriscowley.local' {
  include basenode
  class { 'yumrepos::rpmfusion': }
  package { 'vlc':
    ensure => latest,
    require => Class['yumrepos::rpmfusion']
  }
  package { 'unrar':
    ensure => latest,
    require => Class['yumrepos::rpmfusion']
  }
  package { 'cksfv':
    ensure => latest,
    require => Class['yumrepos::rpmfusion']
  }
  package { 'perl-Convert-UUlib':
    ensure => latest,
    require => Class['yumrepos::epel']
  }
  package { 'transmission-cli':
    ensure => latest,
    require => Class['yumrepos::epel']
  }
  
  include php::cli
  include php::fpm::daemon
  php::ini { '/etc/php.ini':
    memory_limit   => '256M',
  }
  php::module { [ 'mysql', 'pecl-apc' ]: }
  php::module::ini {'pecl-apc':
    settings => {
      'apc.enabled'      => '1',
      'apc.shm_segments' => '1',
      'apc.shm_size'     => '64',
    }
  }
  php::fpm::conf { 'www':
    listen  => '127.0.0.1:9001',
    user    => 'nginx',
    # For the user to exist
    require => Class['nginx'],
  }
  class { 'nginx':
  }
  nginx::vhost::php {'torrents':
    docroot_suffix => 'html/',
  }
  class { 'rvm':
    version => '1.20.12'
  }
  class { 'gitlab':
    db_server => 'db.chriscowley.local',
    vhost     => 'gitlab.chriscowley.me.uk',
  }
}

node 'ci.chriscowley.local' {
  include basenode
}

node 'gitlab.chriscowley.local' {
  include ubuntunode
}

node 'ns1.chriscowley.local' {
  include basenode
  include bind
  bind::server::conf { '/etc/named.conf':
    listen_on_addr    => [ 'any' ],
    forwarders        => [ '192.168.1.1' ],
    allow_query       => [ 'localnets' ],
    zones             => {
      'chriscowley.local' => [
        'type master',
        'file "myzone.lan"',
      ],
      '1.168.192.in-addr.arpa' => [
        'type master',
        'file "1.168.192.in-addr.arpa"',
      ],
    },
  }
  class { 'dhcp':
    domainname    => 'chriscowley.local',
    nameservers   => ['192.168.1.1', '8.8.8.8'],
    subnet        => '192.168.1.0',
    netmask       => '255.255.255.0',
    addressrange  => ['192.168.1.30', '192.168.1.50' ],
    router        => '192.168.1.1',
    ensure        => 'stopped',
  }
}
