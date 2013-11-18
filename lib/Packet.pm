package Packet;
use strict; 
use warnings;
use Net::RawIP;

sub new {
    my($class, $opts) = @_;

    my $self = bless {}, $class || ref $class;
    $self->{rawip} = Net::RawIP->new($opts);

    return $self;
}

sub pkt_payload {
}

sub pkt_size {
}

sub pkt_debug {
}

sub pkt_send {
    my($self, $delay, $amount) = @_;

    #$self->pkt_debug();
    $self->{rawip}->send($delay, $amount);
}

1;
