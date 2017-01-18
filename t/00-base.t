use 5.008000;
use strict;
use warnings;

use Test::More tests => 17;

my $t_client_class;
my $t_pool_class;
my $t_frame_class;
my $t_err_class;

BEGIN {
  $t_client_class = 'AnyEvent::Stomper';
  use_ok( $t_client_class );

  $t_pool_class = 'AnyEvent::Stomper::Pool';
  use_ok( $t_pool_class );

  $t_frame_class = 'AnyEvent::Stomper::Frame';
  use_ok( $t_frame_class );

  $t_err_class = 'AnyEvent::Stomper::Error';
  use_ok( $t_err_class );
}

can_ok( $t_client_class, 'new' );
my $stomper = new_ok( $t_client_class => [ lazy => 1 ] );

can_ok( $t_pool_class, 'new' );
my $pool = new_ok( $t_pool_class,
  [ nodes => [
      { host => '172.18.0.2', port => 61613 },
      { host => '172.18.0.3', port => 61613 },
      { host => '172.18.0.4', port => 61613 },
    ],
    lazy => 1
  ]
);

can_ok( $t_frame_class, 'new' );
my $frame = new_ok( $t_frame_class => [ 'MESSAGE', { 'message-id' => '123' },
    'Hello, world!' ] );

can_ok( $frame, 'command' );
can_ok( $frame, 'headers' );
can_ok( $frame, 'body' );

can_ok( $t_err_class, 'new' );
my $err = new_ok( $t_err_class => [ 'Some error', 6 ] );

can_ok( $err, 'message' );
can_ok( $err, 'code' );
