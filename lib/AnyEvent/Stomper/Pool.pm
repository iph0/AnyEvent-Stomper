package AnyEvent::Stomper::Pool;

use 5.008000;
use strict;
use warnings;
use base qw( Exporter );

our $VERSION = '0.01_01';

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
  foreach my $name ( qw( login passcode vhost heart_beat connection_timeout
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
  $self->{_pool_size}  = undef;
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
      { host => '172.18.0.2', port => 61613 },
      { host => '172.18.0.3', port => 61613 },
      { host => '172.18.0.4', port => 61613 },
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

=head1 CONSTRUCTOR

=head2 new( %params )

  my $stomper = AnyEvent::Stomper::Pool->new(
    nodes => [
      { host => '172.18.0.2', port => 61613 },
      { host => '172.18.0.3', port => 61613 },
      { host => '172.18.0.4', port => 61613 },
    ],
    login              => 'guest',
    passcode           => 'guest',
    vhost              => '/',
    heart_beat         => [ 5000, 5000 ],
    connection_timeout => 5,
    lazy               => 1,
    reconnect_interval => 5,

    on_connect => sub {
      # handling...
    },

    on_disconnect => sub {
      # handling...
    },

    on_error => sub {
      my $err = shift;

      # error handling...
    },
  );

=over

=item nodes => \@nodes

=item login => $login

=item passcode => $passcode

=item vhost => $vhost

=item heart_beat => \@heart_beat

=item connection_timeout => $connection_timeout

=item lazy => $boolean

=item reconnect_interval => $reconnect_interval

=item handle_params => \%params

=item on_connect => $on_connect

=item on_disconnect => $on_disconnect

=item on_connect => $on_connect

=item on_error => $on_error

=back

=head1 METHODS

=head2 get( $host, $port )

=head2 nodes()

=head2 random()

=head2 next()

=head2 force_disconnect()

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
