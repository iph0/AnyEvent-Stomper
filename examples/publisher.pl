#1/usr/bin/env perl

use 5.010000;
use strict;
use warnings;

use AnyEvent::Stomper qw( :err_codes );
use Data::Dumper;

my $stomper = AnyEvent::Stomper->new(
  host       => 'localhost',
  prot       => '61613',
  login      => 'guest',
  passcode   => 'guest',
  heart_beat => [ 5000, 5000 ],

  on_connect => sub {
    print "Connected to server\n";
  },

  on_disconnect => sub {
    print "Disconnected from server\n";
  },
);

my $cv = AE::cv;

my $num = 1;

my $timer;
$timer = AE::timer( 0, 1,
  sub {
    my $body = 'foo' . $num++;

    $stomper->send(
      destination => '/queue/foo',
      persistent  => 'true',
      receipt     => 'auto',
      body        => $body,

      sub {
        my $receipt = shift;
        my $err     = shift;

        if ( defined $err ) {
          warn $err->message . "\n";
          return;
        }

        print "Published: $body\n";
      }
    );
  },
);

my $on_signal = sub {
  $stomper->disconnect(
    sub {
      my $err = $_[1];

      if ( defined $err ) {
        warn $err->message . "\n";
      }

      print "Stopped\n";

      $cv->send;
    }
  );
};

my $int_w  = AE::signal( INT  => $on_signal );
my $term_w = AE::signal( TERM => $on_signal );

$cv->recv;
