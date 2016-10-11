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

my $sub_id = 'foo';
my $dst    = '/queue/foo';

$stomper->subscribe(
  id          => $sub_id,
  destination => $dst,
  ack         => 'client',

  { on_receipt => sub {
      my $receipt = shift;
      my $err     = shift;

      if ( defined $err ) {
        warn $err->message . "\n";
        $cv->send;

        return;
      }

      print "Subscribed to $sub_id\n";
    },

    on_message => sub {
      my $frame = shift;

      my $headers = $frame->headers;
      my $body    = $frame->body;

      $stomper->ack(
        id => $headers->{'message-id'},

        sub {
          my $receipt = shift;
          my $err     = shift;

          if ( defined $err ) {
            warn $err->message . "\n";
            return;
          }

          print "Consumed: $body\n";
        }
      );
    },
  }
);

my $on_signal = sub {
  print "Stopped\n";

  $stomper->unsubscribe(
    id          => $sub_id,
    destination => $dst,

    sub {
      my $receipt = shift;
      my $err     = shift;

      if ( defined $err ) {
        warn $err->message . "\n";
        $cv->send;

        return;
      }

      print "Unsubscribed from $sub_id\n";

      $cv->send;
    }
  );
};

my $int_w  = AE::signal( INT  => $on_signal );
my $term_w = AE::signal( TERM => $on_signal );

$cv->recv;
