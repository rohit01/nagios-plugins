#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-02-09 15:44:43 +0000 (Sat, 09 Feb 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a ZooKeeper server's running config against a given configuration file

Useful for checking

1. Configuration Compliance against a baseline
2. Puppet has correctly deployed revision controlled config version

Inspired by check_mysql_config.pl (also part of Advanced Nagios Plugins Collection)
";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
    use lib dirname(__FILE__) . "/nagios-lib";
}
use HariSekhonUtils;
use HariSekhon::ZooKeeper;

my @config_file_only = qw(
                             autopurge.purgeInterval
                             autopurge.snapRetainCount
                             initLimit
                             leaderServes
                             syncLimit
                             server\.\d+
                       );

$host = "localhost";
$port = $ZK_DEFAULT_PORT;

my $ZK_DEFAULT_CONFIG = "/etc/zookeeper/conf/zoo.cfg";
my $conf              = $ZK_DEFAULT_CONFIG;
my $no_warn_extra = 0;

%options = (
    "H|host=s"         => [ \$host,             "Host to connect to (defaults: localhost)" ],
    "P|port=s"         => [ \$port,             "Port to connect to (defaults: $ZK_DEFAULT_PORT)" ],
    "C|config=s"       => [ \$conf,             "ZooKeeper config file (defaults to $ZK_DEFAULT_CONFIG)" ],
    "e|no-warn-extra"  => [ \$no_warn_extra,    "Don't warn on extra config detected on ZooKeeper server that isn't specified in config file (serverId is omitted either way)" ],
);

@usage_order = qw/host port config no-warn-extra/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$conf       = validate_file($conf, 0, "zookeeper config");

vlog2;
set_timeout();

vlog2 "reading zookeeper config file";
my $fh = open_file $conf;
vlog3;
vlog3 "=====================";
vlog3 "ZooKeeper config file";
vlog3 "=====================";
my %config;
while(<$fh>){
    chomp;
    s/#.*//;
    next if /^\s*$/;
    s/^\s*//;
    s/\s*$//;
    vlog3 "config:  $_";
    /^\s*[\w\.]+\s*=\s*.+$/ or quit "UNKNOWN", "unrecognized line in config file '$conf': $_";
    my ($key, $value) = split(/\s*=\s*/, $_, 2);
    if($key eq "dataDir" or $key eq "dataLogDir"){
        $value =~ s/\/$//;
        $value .= "/version-2";
    }
    #next if $key =~ /^server\.\d+$/;
    if(grep { $key =~ /^$_$/ } @config_file_only){
        vlog3 "omitted: $key (config file only)";
        next;
    }
    $config{$key} = $value;
}
vlog3;

$status = "OK";

vlog2 "getting running zookeeper config from '$host:$port'";
vlog3;
zoo_cmd "conf";
vlog3;
vlog3 "========================";
vlog3 "ZooKeeper running config";
vlog3 "========================";
my %running_config;
while(<$zk_conn>){
    chomp;
    s/#.*//;
    next if /^\s*$/;
    s/^\s*//;
    s/\s*$//;
    vlog3 "running config: $_";
    my ($key, $value) = split(/\s*=\s*/, $_, 2);
    next if $key =~ /^serverId$/;
    $running_config{$key} = $value;
}
vlog3;

my @missing_config;
my @mismatched_config;
my @extra_config;
foreach(sort keys %config){
    unless(defined($running_config{$_})){
        push(@missing_config, $_);
        next;
    }
    unless($config{$_} eq $running_config{$_}){
        push(@mismatched_config, $_);
    }
}

foreach(sort keys %running_config){
    unless(defined($config{$_})){
        push(@extra_config, $_);
    }
}

$msg = "";
if(@mismatched_config){
    critical;
    #$msg .= "mismatched config: ";
    foreach(sort @mismatched_config){
        $msg .= "$_ value mismatch '$config{$_}' in config vs '$running_config{$_}' live on server, ";
    }
}
if(@missing_config){
    critical;
    $msg .= "config not found on running server: ";
    foreach(sort @missing_config){
        $msg .= "$_, ";
    }
    $msg =~ s/, $//;
    $msg .= ", ";
}
if((!$no_warn_extra) and @extra_config){
    warning;
    $msg .= "extra config found on running server: ";
    foreach(sort @extra_config){
        $msg .= "$_=$running_config{$_}, ";
    }
    $msg =~ s/, $//;
    $msg .= ", ";
}

$msg = sprintf("%d config values tested from config file '$conf', %s", scalar keys %config, $msg);
$msg =~ s/, $//;

quit $status, $msg;