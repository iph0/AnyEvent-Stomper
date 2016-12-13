package AnyEvent::Stomper::Pool;

use 5.008000;
use strict;
use warnings;
use base qw( Exporter );

our $VERSION = '0.10';

use AnyEvent::Stomper;
use Scalar::Util qw( weaken );
use Carp qw( croak );


sub new {
  my $class  = shift;
  my %params = @_;

  my $self = bless {}, $class;

  unless ( defined $params{nodes} ) {
    croak 'Nodes not specified';
  }
  unless ( ref( $params{nodes} ) eq 'ARRAY' ) {
    croak 'Nodes must be specified as array reference';
  }
  unless ( @{ $params{nodes} } ) {
    croak 'Specified empty list of nodes';
  }

  $self->{nodes}              = $params{nodes};
  $self->{on_node_connect}    = $params{on_node_connect};
  $self->{on_node_disconnect} = $params{on_node_disconnect};
  $self->{on_node_error}      = $params{on_node_error};

  my %node_params;
  foreach my $name ( qw( login passcode vhost heartbeat connection_timeout
      reconnect_interval handle_params lazy ) )
  {
    next unless defined $params{$name};
    $node_params{$name} = $params{$name};
  }
  $self->{_node_params} = \%node_params;

  $self->_reset_internals;
  $self->_init;

  return $self;
}

sub get {
  my $self = shift;
  my $host = shift;
  my $port = shift;

  return $self->{_nodes_idx}{"$host:$port"};
}

sub nodes {
  my $self = shift;
  return @{ $self->{_nodes_list} };
}

sub random {
  my $self = shift;

  my $rand_index = int( rand( $self->{_pool_size} ) );

  return $self->{_nodes_list}[$rand_index];
}

sub next {
  my $self = shift;

  unless ( $self->{_node_index} < $self->{_pool_size} ) {
    $self->{_node_index} = 0;
  }

  return $self->{_nodes_list}[ $self->{_node_index}++ ];
}

sub force_disconnect {
  my $self = shift;

  foreach my $node ( @{ $self->{_nodes_list} } ) {
    $node->force_disconnect;
  }
  $self->_reset_internals;

  return;
}

sub _init {
  my $self = shift;

  my $nodes_idx  = $self->{_nodes_idx};
  my $nodes_list = $self->{_nodes_list};

  foreach my $node_params ( @{ $self->{nodes} } ) {
    my $hostport = "$node_params->{host}:$node_params->{port}";

    unless ( defined $nodes_idx->{$hostport} ) {
      my $node
          = $self->_new_node( $node_params->{host}, $node_params->{port} );
      $nodes_idx->{$hostport} = $node;
      push( @{$nodes_list}, $node );
    }
  }

  $self->{_pool_size} = scalar @{$nodes_list};

  return;
}

sub _new_node {
  my $self = shift;
  my $host = shift;
  my $port = shift;

  return AnyEvent::Stomper->new(
    %{ $self->{_node_params} },
    host          => $host,
    port          => $port,
    on_connect    => $self->_create_on_node_connect( $host, $port ),
    on_disconnect => $self->_create_on_node_disconnect( $host, $port ),
    on_error      => $self->_create_on_node_error( $host, $port ),
  );
}

sub _create_on_node_connect {
  my $self = shift;
  my $host = shift;
  my $port = shift;

  weaken($self);

  return sub {
    if ( defined $self->{on_node_connect} ) {
      $self->{on_node_connect}->( $host, $port );
    }
  };
}

sub _create_on_node_disconnect {
  my $self = shift;
  my $host = shift;
  my $port = shift;

  weaken($self);

  return sub {
    if ( defined $self->{on_node_disconnect} ) {
      $self->{on_node_disconnect}->( $host, $port );
    }
  };
}

sub _create_on_node_error {
  my $self = shift;
  my $host = shift;
  my $port = shift;

  weaken($self);

  return sub {
    my $err = shift;

    if ( defined $self->{on_node_error} ) {
      $self->{on_node_error}->( $err, $host, $port );
    }
  };
}

sub _reset_internals {
  my $self = shift;

  $self->{_nodes_idx}  = {};
  $self->{_nodes_list} = [];
  $self->{_pool_size}  = 0;
  $self->{_node_index} = 0;

  return;
}

1;
__END__

=head1 NAME

AnyEvent::Stomper::Pool - Connection pool for AnyEvent::Stomper

=head1 SYNOPSIS

  use AnyEvent;
  use AnyEvent::Stomper::Pool;

  my $pool = AnyEvent::Stomper::Pool->new(
    nodes => [
      { host => 'stomp-server-1.com', port => 61613 },
      { host => 'stomp-server-2.com', port => 61613 },
      { host => 'stomp-server-3.com', port => 61613 },
    ],
    login    => 'guest',
    passcode => 'guest',
  );

  my $stomper = $pool->random;
  my $cv      = AE::cv;

  $stomper->subscribe(
    id          => 'foo',
    destination => '/queue/foo',

    { on_receipt => sub {
        my $err = $_[1];

        if ( defined $err ) {
          warn $err->message . "\n";
          $cv->send;

          return;
        }

        $stomper->send(
          destination => '/queue/foo',
          body        => 'Hello, world!',
        );
      },

      on_message => sub {
        my $msg = shift;

        my $body = $msg->body;
        print "Consumed: $body\n";

        $cv->send;
      },
    }
  );

  $cv->recv;

=head1 DESCRIPTION

AnyEvent::Stomper::Pool is connection pool for AnyEvent::Stomper. This module
can be used to work with cluster or set of STOMP servers.

=head1 CONSTRUCTOR

=head2 new( %params )

  my $stomper = AnyEvent::Stomper::Pool->new(
    nodes => [
      { host => 'stomp-server-1.com', port => 61613 },
      { host => 'stomp-server-2.com', port => 61613 },
      { host => 'stomp-server-3.com', port => 61613 },
    ],
    login              => 'guest',
    passcode           => 'guest',
    vhost              => '/',
    heartbeat          => [ 5000, 5000 ],
    connection_timeout => 5,
    lazy               => 1,
    reconnect_interval => 5,

    on_node_connect => sub {
      # handling...
    },

    on_node_disconnect => sub {
      # handling...
    },

    on_node_error => sub {
      my $err = shift;

      # error handling...
    },
  );

=over

=item nodes => \@nodes

Specifies the list of nodes. Parameter should contain array of hashes. Each
hash should contain C<host> and C<port> elements.

=item login => $login

The user identifier used to authenticate against a secured STOMP server.

=item passcode => $passcode

The password used to authenticate against a secured STOMP server.

=item vhost => $vhost

The name of a virtual host that the client wishes to connect to.

=item heartbeat => \@heartbeat

Heart-beating can optionally be used to test the healthiness of the underlying
TCP connection and to make sure that the remote end is alive and kicking. The
first number sets interval in milliseconds between outgoing heart-beats to the
STOMP server. C<0> means, that the client will not send heart-beats. The second
number sets interval in milliseconds between incoming heart-beats from the
STOMP server. C<0> means, that the client does not want to receive heart-beats.

  heartbeat => [ 5000, 5000 ],

Not set by default.

=item connection_timeout => $connection_timeout

Specifies connection timeout. If the client could not connect to the node
after specified timeout, the C<on_node_error> callback is called with the
C<E_CANT_CONN> error. The timeout specifies in seconds and can contain a
fractional part.

  connection_timeout => 10.5,

By default the client use kernel's connection timeout.

=item lazy => $boolean

If enabled, the connection establishes at time when you will send the first
command to the node. By default the connection establishes after calling of
the C<new> method.

Disabled by default.

=item reconnect_interval => $reconnect_interval

If the parameter is specified, the client will try to reconnect only after
this interval. Commands executed between reconnections will be queued.

  reconnect_interval => 5,

Not set by default.

=item handle_params => \%params

Specifies L<AnyEvent::Handle> parameters.

  handle_params => {
    autocork => 1,
    linger   => 60,
  }

Enabling of the C<autocork> parameter can improve perfomance. See
documentation on L<AnyEvent::Handle> for more information.

=item on_node_connect => $cb->( $host, $port )

The C<on_node_connect> callback is called when the connection to specific node
is successfully established. To callback are passed two arguments: host and
port of the node to which the client was connected.

Not set by default.

=item on_node_disconnect => $cb->( $host, $port )

The C<on_node_disconnect> callback is called when the connection to specific
node is closed by any reason. To callback are passed two arguments: host and
port of the node from which the client was disconnected.

Not set by default.

=item on_node_error => $cb->( $err, $host, $port )

The C<on_node_error> callback is called when occurred an error, which was
affected on entire node (e. g. connection error or authentication error). Also
the C<on_node_error> callback can be called on command errors if the command
callback is not specified. To callback are passed three arguments: error object,
and host and port of the node on which an error occurred.

Not set by default.

=back

=head1 METHODS

=head2 get( $host, $port )

Gets specified node.

=head2 nodes()

Gets all available nodes.

=head2 random()

Gets random node.

=head2 next()

Gets next node from nodes list cyclically.

=head2 force_disconnect()

The method for forced disconnection. All uncompleted operations will be
aborted.

=head1 SEE ALSO

L<AnyEvent::Stomper>

=head1 AUTHOR

Eugene Ponizovsky, E<lt>ponizovsky@gmail.comE<gt>

Sponsored by SMS Online, E<lt>dev.opensource@sms-online.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2016, Eugene Ponizovsky, SMS Online. All rights reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
