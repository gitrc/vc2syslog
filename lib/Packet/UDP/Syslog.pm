package Packet::UDP::Syslog;
use strict; 
use warnings;
use base qw/Packet::UDP/;

sub new {
    my ($class, $src, $dst) = @_;
    my $self = $class->SUPER::new("$src:1666", "$dst:514");
    return $self;
}

# TAG               CODE    DESCRIPTION
# =====================================
# kernel            0       kernel messages
# user              1       user-level messages
# mail              2       mail system
# system            3       system daemons
# security          4       security/authorization messages (note 1)
# internal          5       messages generated internally by syslogd
# print             6       line printer subsystem
# news              7       network news subsystem
# uucp              8       UUCP subsystem
# clock             9       clock daemon (note 2)
# security2        10       security/authorization messages (note 1)
# ftp              11       FTP daemon
# ntp              12       NTP subsystem
# logaudit         13       log audit (note 1)
# logalert         14       log alert (note 1)
# clock2           15       clock daemon (note 2)
# local0           16       local use 0  (local0)
# local1           17       local use 1  (local1)
# local2           18       local use 2  (local2)
# local3           19       local use 3  (local3)
# local4           20       local use 4  (local4)
# local5           21       local use 5  (local5)
# local6           22       local use 6  (local6)
# local7           23       local use 7  (local7)
my $i = 0;
my %fac_map = map {$_ => $i++ } qw/kernel user mail system security internal print news uucp clock security2 ftp ntp logaudit logalert clock2 local0 local1 local2 local3 local4 local5 local6 local7/;

# TAG             CODE    DESCRIPTION
# =====================================
# emerg           0       Emergency: system is unusable
# alert           1       Alert: action must be taken immediately
# crit            2       Critical: critical conditions
# err             3       Error: error conditions
# warn            4       Warning: warning conditions
# notice          5       Notice: normal but significant condition
# info            6       Informational: informational messages
# debug           7       Debug: debug-level messages
$i = 0;
my %sev_map = map {$_ => $i++} qw/emerg alert crit err warn notice info debug/;

sub pkt_payload {
    my($self, $facility, $severity, $msg) = @_;

    my ($fac_sev) = ($fac_map{$facility} << 3) + $sev_map{$severity};
    $self->{rawip}->set({
            udp => {
                data => "<$fac_sev>$msg."
                }
            }
    );

    # call and set the size
    $self->pkt_size();
}

1;
