class basenode {
  class {'htop':
  }
  include vim
  include yumrepos
  include puppet::agent
  include yumrepos::epel
  class { 'nethogs':
  }
  class { 'mosh':
  }
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

node 'ext.chriscowley.local' {
  include basenode
  include php::fpm::daemon
  php::fpm::conf { 'www':
    listen  => '127.0.0.1:9001',
    user    => 'nginx',
    # For the user to exist
    require => Package['nginx'],
  }
  package { 'nginx':
    ensure => latest,
  }
#
#  class { 'apache': }
#  apache::mod { 'php':
#    require => Package['php'],
#  }
#  class { 'php::mod_php5': inifile => '/etc/httpd/conf/php.ini' }

#  apache::vhost { 'tflux.chriscowley.local':
#    serveraliases => [
#      'tflux.chriscowley.me.uk',
#      'tflux',
 #   ],
 #   port    => '80',
 #   docroot => '/var/www/tflux',
 # }

}

node 'ci.chriscowley.local' {
  include basenode
}
