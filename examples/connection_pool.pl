#/usr/bin/env perl

use strict;
use warnings;

use AnyEvent;
use AnyEvent::Stomper::Pool;

my $pool = AnyEvent::Stomper::Pool->new(
  nodes => [
    { host => '172.18.0.2', port => 61613 },
    { host => '172.18.0.3', port => 61613 },
    { host => '172.18.0.4', port => 61613 },
  ],
  login    => 'guest',
  passcode => 'guest',

  on_node_connect => sub {
    my $host = shift;
    my $port = shift;

    print "Connected to $host:$port\n";
  },

  on_node_disconnect => sub {
    my $host = shift;
    my $port = shift;

    print "Disconnected from $host:$port\n";
  },

  on_node_error => sub {
    my $err  = shift;
    my $host = shift;
    my $port = shift;

    warn "$host:$port: " . $err->message . "\n";
  },
);

my $stomper = $pool->random;
my $cv      = AE::cv;
my $sub_id  = 'foo';
my $dst     = '/queue/foo';

$stomper->subscribe(
  id          => $sub_id,
  destination => $dst,

  on_receipt => sub {
    my $err = $_[1];

    if ( defined $err ) {
      warn $err->message . "\n";
      $cv->send;

      return;
    }

    print "Subscribed to $sub_id\n";

    $stomper->send(
      destination => $dst,
      persistent  => 'true',
      body        => 'Hello, world!',
    );
  },

  on_message => sub {
    my $msg = shift;

    my $headers = $msg->headers;
    my $body    = $msg->body;

    print "Consumed: $body\n";

    $cv->send;
  }
);

$cv->recv;

$pool->force_disconnect;
