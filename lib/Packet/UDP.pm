package Packet::UDP;
use strict; 
use warnings;
use base qw/Packet/;
use POSIX qw{strftime};

#
# src => IP:PORT
# dst => IP:PORT
#
sub new {
    my($class, $src, $dst) = @_;
    my($saddr, $sport) = split /:/, $src;
    my($daddr, $dport) = split /:/, $dst;

    my $self = $class->SUPER::new({
            ip => {
                saddr    => $saddr,
                daddr    => $daddr,
                frag_off => 0,
                tos      => 0,
                id       => $$ + strftime('%s', localtime()),
            },
            udp => {
                source => $sport,
                dest   => $dport,
            },
            });
}

sub pkt_size {
    my($self)= @_;

    my($src, $dst, $data) = $self->{rawip}->get( {
                udp => [qw/source dest data/]
            },
    );
    my $size = length($src) + length($dst) + length($data);

    # set 'check' to 0 to recalculate the UDP checksum
    $self->{rawip}->set( {
            udp => {
                len   => $size,
                check => 0,
            }
    });

    return $size;
}

sub pkt_payload {
}

sub pkt_debug {
    my($self) = @_;

    my(@ip_fields)  = qw/version ihl tos id frag_off ttl protocolsaddr daddr/;
    my(@udp_fields) = qw/source dest len data/;
    my(@ip_data)    = $self->{rawip}->get({ ip  => \@ip_fields });
    my(@udp_data)   = $self->{rawip}->get({ udp => \@udp_fields });

    print "IP FIELDS\n";
    print "=========\n";
    print "- $ip_fields[$_]: $ip_data[$_]\n" foreach 0 ..  $#ip_data;
    print "UDP FIELDS\n";
    print "=========\n";
    print "- $udp_fields[$_]: $udp_data[$_]\n" foreach 0 ..  $#udp_data;

}

1;
