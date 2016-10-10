#1/usr/bin/env perl

use 5.010000;
use strict;
use warnings;

use AnyEvent::Stomper qw( :err_codes );
use Data::Dumper;

my $stomper = AnyEvent::Stomper->new(
  host               => 'localhost',
  prot               => '61613',
  login              => 'guest',
  passcode           => 'guest',
  heart_beat         => [ 5000, 5000 ],

  on_connect => sub {
    print "Connected to server\n";
  },

  on_disconnect => sub {
    print "Disconnected from server\n";
  },

  on_error => sub {
    my $err   = shift;
    my $frame = shift;

    print Dumper($frame);
  }
);

my $cv = AE::cv;

my $dst = '/queue/foo';

$stomper->subscribe(
  id          => 1,
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

      print qq{Subscribed to "$dst"\n};
    },

    on_message => sub {
      my $frame = shift;

      print 'Consumed: ' . $frame->body . "\n";

      my $msg_id = $frame->headers->{'message-id'};

      $stomper->ack(
        id => $msg_id,

        sub {
          my $receipt = shift;
          my $err     = shift;

          if ( defined $err ) {
            warn $err->message . "\n";
            return;
          }

          print "Acked: message-id=$msg_id\n",
        }
      );
    },
  }
);

my $on_signal = sub {
  print "Stopped\n";

  $stomper->unsubscribe(
    id          => 1,
    destination => $dst,

    sub {
      my $receipt = shift;
      my $err     = shift;

      if ( defined $err ) {
        warn $err->message . "\n";
        $cv->send;

        return;
      }

      print qq{Unsubscribed from "$dst"\n};

      $cv->send;
    }
  );
};

my $int_w  = AE::signal( INT  => $on_signal );
my $term_w = AE::signal( TERM => $on_signal );

$cv->recv;

undef $stomper;
