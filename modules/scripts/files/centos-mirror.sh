#!/bin/sh

mkdir -p /var/www/mirror/centos/6/os/
rsync -artq rsync://mirror.ovh.net/ftp.centos.org/6/os/x86_64 /var/www/mirror/centos/6/os/  --bwlimit 200
