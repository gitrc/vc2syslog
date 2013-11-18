#!/usr/bin/perl -w
#
# vc2syslog.pl - Send the vCenter Events to syslog
#
# Rod Cordova (@gitrc)
#
# August 2011

$|++;

use strict;
use warnings;

use Data::Dumper qw(Dumper);
use DateTime;
use DateTime::Format::DateParse;
use DateTime::Format::Strptime;
use Getopt::Long qw(:config require_order);
use Packet::UDP::Syslog;
use lib 'lib';

$ENV{'VI_CONFIG'} ||= '/root/.visdkrc';
$Data::Dumper::Indent = 1;

use vmAPI;

my $debug;
$debug = exists( $ENV{SSH_CLIENT} ) ? 1 : 0;

my $opts = {
    'start' => DateTime->now()->set_time_zone('America/New_York')
      ->subtract( minutes => 5 )->set_time_zone('UTC'),
    'end' => DateTime->now(),
};

my $r = GetOptions(
    $opts,
    'host:s',
    'username:s',
    'password:s',
    'start:s' => \&parse_datetime_arg,
    'end:s'   => \&parse_datetime_arg,
);

exit 1 if !$r;

if (   !$opts->{'start'}
    || !$opts->{'end'}
    || DateTime->compare( @{$opts}{ 'start', 'end' } ) > 0 )
{
    printf STDERR "Invalid datetime range: start: %s end: %s\n",
      $opts->{'start'}->datetime, $opts->{'end'}->datetime;

    exit 1;
}

my $vmAPI = vmAPI->new();
$vmAPI->connect();

my $event_manager =
  $vmAPI->mor_to_views( $vmAPI->vim_service_content()->eventManager() )->[0];
my $event_filter_spec = EventFilterSpec->new(
    time => EventFilterSpecByTime->new(
        'beginTime' => $opts->{'start'}->datetime,
        'endTime'   => $opts->{'end'}->datetime,
    )
);
my $event_collector =
  $vmAPI->mor_to_views(
    $event_manager->CreateCollectorForEvents( 'filter' => $event_filter_spec ) )
  ->[0];

my $file = "state.txt";
open( LOG, "$file" ) or die "Cannot open file $!";
my $lastId = <LOG>;
close(LOG);

$lastId = 0 unless $lastId;
my $loghost = "127.0.0.1";
my @EventIds;
my $eventcount = 0;

while ( my $entries = $event_collector->ReadNextEvents( 'maxCount' => '1000' ) )
{
    last if !@$entries;

    foreach my $entry ( sort { $a->key <=> $b->key } @$entries ) {
        my $sequenceId = $entry->key() + 0;
        next if $sequenceId <= $lastId;
        push @EventIds, $sequenceId;
        if ( $entry->fullFormattedMessage =~ /(ignoreuser1|ignoreuser2)/ ) {
            $eventcount++;
            next;
        }

        my $month =
          DateTime::Format::DateParse->parse_datetime( $entry->createdTime )
          ->set_time_zone('America/New_York')->month_abbr();
        my $day =
          DateTime::Format::DateParse->parse_datetime( $entry->createdTime )
          ->set_time_zone('America/New_York')->day();
        my $time =
          DateTime::Format::DateParse->parse_datetime( $entry->createdTime )
          ->set_time_zone('America/New_York')->hms();
        my $hostname =
          ( $entry->host ) ? $entry->host->name : 'vcenter.fqdn';
        my $message = substr $entry->fullFormattedMessage(), 0;
        my $username = substr $entry->userName, 0;
        $username = 'VCENTER' if $username eq '';
        my $payload =
          "$month $day $time vcenter_event[$sequenceId]: $message by $username";
        &sendlog( $hostname, $payload );

    }
}

if (@EventIds) {
    open( LOG, "> $file" ) or die "Cannot open file $!";
    print LOG $EventIds[-1];
    close(LOG);
}

print "Completed at $EventIds[-1].  Processed "
  . ( scalar(@EventIds) - $eventcount )
  . " out of "
  . scalar(@EventIds)
  . " total events.\n"
  if $debug;

##
## Subroutines
##

sub parse_datetime_arg {
    my $key          = shift;
    my $datetime_str = shift;

    my $strp;

    $datetime_str =~
s/^(\d{4})[^\d]?(\d{2})[^\d]?(\d{2})[\s]?(\d{2})[^\d]?(\d{2})[^\d]?(\d{2})$/$1-$2-$3 $4:$5:$6/;

    $strp = DateTime::Format::Strptime->new(
        'pattern'   => '%F %T',
        'time_zone' => 'America/New_York',
    );

    my $dt = $strp->parse_datetime($datetime_str);

    die('Invalid date input') if !$dt;

    $opts->{$key} = $dt->set_time_zone('UTC');
}

sub sendlog {
    my $hostname = shift;
    my $payload  = shift;

    my $syslog = Packet::UDP::Syslog->new( $hostname, $loghost );
    $syslog->pkt_payload( 'local0', 'info', $payload );
    $syslog->pkt_send( 1, 1 );
    $syslog->DESTROY;

}
