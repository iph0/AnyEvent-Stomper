use 5.008000;
use strict;
use warnings;

use Test::More tests => 14;
use Test::Fatal;
use AnyEvent::Stomper;
use AnyEvent::Stomper::Pool;

t_heart_beat();
t_conn_timeout();
t_reconnect_interval();
t_on_message();
t_nodes();

sub t_heart_beat {
   like(
    exception {
      my $stomper = AnyEvent::Stomper->new(
        heart_beat => 'invalid',
      );
    },
    qr/"heart_beat" must be specified as array reference/,
    'invalid "heart_beat" (character string)'
  );

  like(
    exception {
      my $stomper = AnyEvent::Stomper->new(
        heart_beat => [ 'invalid', 'invalid' ],
      );
    },
    qr/"heart_beat" values must be an integer numbers/,
    'invalid "heart_beat" values (character string)'
  );
}

sub t_conn_timeout {
  like(
    exception {
      my $stomper = AnyEvent::Stomper->new(
        connection_timeout => 'invalid',
      );
    },
    qr/"connection_timeout" must be a positive number/,
    'invalid connection timeout (character string; constructor)'
  );

  like(
    exception {
      my $stomper = AnyEvent::Stomper->new(
        connection_timeout => -5,
      );
    },
    qr/"connection_timeout" must be a positive number/,
    'invalid connection timeout (negative number; constructor)'
  );

  my $stomper = AnyEvent::Stomper->new();

  like(
    exception {
      $stomper->connection_timeout('invalid');
    },
    qr/"connection_timeout" must be a positive number/,
    'invalid connection timeout (character string; accessor)'
  );

  like(
    exception {
      $stomper->connection_timeout(-5);
    },
    qr/"connection_timeout" must be a positive number/,
    'invalid connection timeout (negative number; accessor)'
  );

  return;
}

sub t_reconnect_interval {
  like(
    exception {
      my $stomper = AnyEvent::Stomper->new(
        reconnect_interval => 'invalid',
      );
    },
    qr/"reconnect_interval" must be a positive number/,
    q{invalid "reconnect_interval" (character string; constructor)},
  );

  like(
    exception {
      my $stomper = AnyEvent::Stomper->new(
        reconnect_interval => -5,
      );
    },
    qr/"reconnect_interval" must be a positive number/,
    q{invalid "reconnect_interval" (negative number; constructor)},
  );

  my $stomper = AnyEvent::Stomper->new();

  like(
    exception {
      $stomper->reconnect_interval('invalid');
    },
    qr/"reconnect_interval" must be a positive number/,
    q{invalid "reconnect_interval" (character string; accessor)},
  );

  like(
    exception {
      $stomper->reconnect_interval(-5);
    },
    qr/"reconnect_interval" must be a positive number/,
    q{invalid "reconnect_interval" (negative number; accessor)},
  );

  return;
}

sub t_on_message {
  my $stomper = AnyEvent::Stomper->new();

  like(
    exception {
      $stomper->subscribe(
        id          => 'foo',
        destination => '/queue/foo',
      );
    },
    qr/"on_message" callback must be specified/,
    "\"on_message\" callback not specified",
  );

  return;
}

sub t_nodes {
  like(
    exception {
      my $cluster = AnyEvent::Stomper::Pool->new();
    },
    qr/Nodes not specified/,
    'Nodes not specified'
  );

  like(
    exception {
      my $cluster = AnyEvent::Stomper::Pool->new(
        nodes => {},
      );
    },
    qr/Nodes must be specified as array reference/,
    'Nodes in invalid format (hash reference)'
  );

  like(
    exception {
      my $cluster = AnyEvent::Stomper::Pool->new(
        nodes => [],
      );
    },
    qr/Specified empty list of nodes/,
    'empty list of nodes'
  );
}


