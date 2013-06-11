class basenode {
  class {'htop':
  }
  include vim
  include yumrepos
  include puppet::agent
  include yumrepos::epel
  class { 'nethogs':
  }
}

class glusternode {
  include basenode
  include yumrepos::gluster
  file { [ '/export', '/export/gv0']:
    seltype => 'usr_t',
    ensure  => directory,
  }
  
  package { 'xfsprogs': ensure => installed 
  }
  exec { 'lvcreate /dev/vg0/gv0':
    command => '/sbin/lvcreate -L 6G -n gv0 vg0',
    creates => '/dev/vg0/gv0',
    notify  => Exec['mkfs /dev/vg0/gv0'],
  }
  exec { 'mkfs /dev/vg0/gv0':
    command     => '/sbin/mkfs.xfs -i size=512 /dev/vg0/gv0',
    require     => [ Package['xfsprogs'], Exec['lvcreate /dev/vg0/gv0'] ],
    refreshonly => true,
  }
  mount { '/export/gv0':
    device  => '/dev/vg0/gv0',
    fstype  => 'xfs',
    options => 'defaults',
    ensure  => mounted,
    require => [ Exec['mkfs /dev/vg0/gv0'], File['/export/gv0'] ],
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
}

node 'mirror.chriscowley.local' {
  include basenode
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

node 'openstack1.chriscowley.local' {
  include basenode
}

node 'webdev.chriscowley.local' {
  include basenode
}

node 'ci.chriscowley.local' {
  include basenode
}
