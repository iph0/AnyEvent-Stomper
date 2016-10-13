use 5.008000;
use strict;
use warnings;

use Test::More tests => 8;
use AnyEvent::Stomper qw( :err_codes );

is( E_CANT_CONN, 1, 'E_CANT_CONN' );
is( E_CANT_LOGIN, 2, 'E_CANT_LOGIN' );
is( E_IO, 3, 'E_IO' );
is( E_CONN_CLOSED_BY_REMOTE_HOST, 4, 'E_CONN_CLOSED_BY_REMOTE_HOST' );
is( E_CONN_CLOSED_BY_CLIENT, 5, 'E_CONN_CLOSED_BY_CLIENT' );
is( E_OPRN_ERROR, 6, 'E_OPRN_ERROR' );
is( E_UNEXPECTED_DATA, 7, 'E_UNEXPECTED_DATA' );
is( E_READ_TIMEDOUT, 8, 'E_READ_TIMEDOUT' );
