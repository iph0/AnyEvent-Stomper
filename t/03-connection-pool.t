use 5.008000;
use strict;
use warnings;

use Test::More tests => 11;

BEGIN {
  *CORE::GLOBAL::rand = sub { return 1 };
}

use AnyEvent::Stomper::Pool;

my $pool = AnyEvent::Stomper::Pool->new(
  nodes => [
    { host => '172.18.0.2', port => 61613 },
    { host => '172.18.0.3', port => 61613 },
    { host => '172.18.0.4', port => 61613 },
  ],
  lazy => 1,
);

can_ok( $pool, 'get' );
can_ok( $pool, 'nodes' );
can_ok( $pool, 'random' );
can_ok( $pool, 'next' );
can_ok( $pool, 'force_disconnect' );

t_get($pool);
t_nodes($pool);
t_random($pool);
t_next($pool);


sub t_get {
  my $pool = shift;

  my $t_stomper = $pool->get( '172.18.0.2', 61613 );

  is( $t_stomper->host, '172.18.0.2', 'get' );

  return;
}

sub t_nodes {
  my $pool = shift;

  my @t_hosts;

  foreach my $stomper ( $pool->nodes ) {
    push( @t_hosts, $stomper->host );
  }

  is_deeply( \@t_hosts,
    [ '172.18.0.2',
      '172.18.0.3',
      '172.18.0.4',
    ],
    'nodes'
  );

  return;
}

sub t_random {
  my $pool = shift;

  my $t_stomper = $pool->random;

  is( $t_stomper->host, '172.18.0.3', 'random' );

  return;
}

sub t_next {
  my $pool = shift;

  my $t_stomper = $pool->next;
  is( $t_stomper->host, '172.18.0.2', 'next; first' );

  $t_stomper = $pool->next;
  is( $t_stomper->host, '172.18.0.3', 'next; second' );

  $t_stomper = $pool->next;
  is( $t_stomper->host, '172.18.0.4', 'next; third' );

  return;
}
