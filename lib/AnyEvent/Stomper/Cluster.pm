package AnyEvent::Stomper::Cluster;

use 5.008000;
use strict;
use warnings;
use base qw( Exporter );

our $VERSION = '0.15_01';

use AnyEvent::Stomper;
use AnyEvent::Stomper::Error;

use Scalar::Util qw( weaken );
use Carp qw( croak );

our %ERROR_CODES;

BEGIN {
  %ERROR_CODES = %AnyEvent::Stomper::Error::ERROR_CODES;
  our @EXPORT_OK   = keys %ERROR_CODES;
  our %EXPORT_TAGS = ( err_codes => \@EXPORT_OK );
}

use constant \%ERROR_CODES;


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
      reconnect_interval handle_params lazy default_headers command_headers
      body_encoder body_decoder ) )
  {
    next unless defined $params{$name};
    $node_params{$name} = $params{$name};
  }
  $self->{_node_params} = \%node_params;

  $self->_reset_internals;
  $self->_init;

  return $self;
}

sub execute {
  my $self     = shift;
  my $cmd_name = shift;

  my $cmd = $self->_prepare( $cmd_name, [@_] );
  $self->_execute($cmd);

  return;
}

# Generate methods
{
  no strict qw( refs );

  foreach my $name ( qw( send subscribe unsubscribe ack nack begin commit
      abort disconnect ) )
  {
    *{$name} = sub {
      my $self = shift;

      my $cmd = $self->_prepare( $name, [@_] );
      $self->_execute($cmd);

      return;
    }
  }
}

sub get {
  my $self = shift;
  my $host = shift;
  my $port = shift;

  return $self->{_nodes_pool}{"$host:$port"};
}

sub nodes {
  my $self = shift;
  return values %{ $self->{_nodes_pool} };
}

sub force_disconnect {
  my $self = shift;

  foreach my $node ( values %{ $self->{_nodes_pool} } ) {
    $node->force_disconnect;
  }
  $self->_reset_internals;

  return;
}

sub _init {
  my $self = shift;

  my $nodes_pool = $self->{_nodes_pool};

  foreach my $node_params ( @{ $self->{nodes} } ) {
    my $hostport = "$node_params->{host}:$node_params->{port}";

    unless ( defined $nodes_pool->{$hostport} ) {
      $nodes_pool->{$hostport}
          = $self->_new_node( $node_params->{host}, $node_params->{port} );
    }
  }

  $self->{_nodes}       = [ keys %{ $self->{_nodes_pool} } ];
  $self->{_active_node} = $self->_next_node;

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
    lazy          => 1,
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

    my $err_code = $err->code;

    if ( $err_code != E_OPRN_ERROR
      && $err_code != E_CONN_CLOSED_BY_CLIENT )
    {
      $self->{_active_node} = $self->_next_node;
    }

    if ( defined $self->{on_node_error} ) {
      $self->{on_node_error}->( $err, $host, $port );
    }
  };
}

sub _prepare {
  my $self     = shift;
  my $cmd_name = uc(shift);
  my $args     = shift;

  my %cbs;
  if ( ref( $args->[-1] ) eq 'CODE'
    && scalar @{$args} % 2 > 0 )
  {
    if ( $cmd_name eq 'SUBSCRIBE' ) {
      $cbs{on_message} = pop @{$args};
    }
    else {
      $cbs{on_receipt} = pop @{$args};
    }
  }

  my %headers = @{$args};
  foreach my $name ( qw( on_receipt on_message on_node_error ) ) {
    if ( defined $headers{$name} ) {
      $cbs{$name} = delete $headers{$name};
    }
  }
  my $body = delete $headers{body};

  my $cmd = {
    name    => $cmd_name,
    headers => \%headers,
    body    => $body,
    %cbs,
  };

  return $cmd;
}

sub _execute {
  my $self      = shift;
  my $cmd       = shift;
  my $fails_cnt = shift || 0;

  my $hostport = $self->{_active_node};
  my $node     = $self->{_nodes_pool}{$hostport};

  weaken($self);

  $node->execute( $cmd->{name}, %{ $cmd->{headers} },
    body => $cmd->{body},

    on_receipt => sub {
      my $receipt = shift;
      my $err     = shift;

      if ( defined $err ) {
        my $err_code = $err->code;
        $fails_cnt++;

        my $on_node_error = $cmd->{on_node_error} || $self->{on_node_error};
        if ( defined $on_node_error ) {
          my $node = $self->{_nodes_pool}{$hostport};
          $on_node_error->( $err, $node->host, $node->port );
        }

        if ( $err_code != E_OPRN_ERROR
          && $err_code != E_CONN_CLOSED_BY_CLIENT
          && $fails_cnt < scalar @{ $self->{_nodes} } )
        {
          $self->_execute( $cmd, $fails_cnt );
          return;
        }

        if ( defined $cmd->{on_receipt} ) {
          $cmd->{on_receipt}->( $receipt, $err );
        }

        return;
      }

      if ( defined $cmd->{on_receipt} ) {
        $cmd->{on_receipt}->($receipt);
      }
    },

    defined $cmd->{on_message}
    ? ( on_message => $cmd->{on_message} )
    : (),
  );

  return;
}

sub _next_node {
  my $self = shift;

  unless ( defined $self->{_node_index} ) {
    $self->{_node_index} = int( rand( scalar @{ $self->{_nodes} } ) );
  }
  elsif ( $self->{_node_index} == scalar @{ $self->{_nodes} } ) {
    $self->{_node_index} = 0;
  }

  return $self->{_nodes}[ $self->{_node_index}++ ];
}

sub _reset_internals {
  my $self = shift;

  $self->{_nodes_pool}  = {};
  $self->{_nodes}       = undef;
  $self->{_node_index}  = undef;
  $self->{_active_node} = undef;

  return;
}

1;
__END__

=head1 NAME

AnyEvent::Stomper::Cluster - The client for the cluster of STOMP servers

=head1 SYNOPSIS

  use AnyEvent;
  use AnyEvent::Stomper::Cluster;

  my $cluster = AnyEvent::Stomper::Cluster->new(
    nodes => [
      { host => 'stomp-server-1.com', port => 61613 },
      { host => 'stomp-server-2.com', port => 61613 },
      { host => 'stomp-server-3.com', port => 61613 },
    ],
    login    => 'guest',
    passcode => 'guest',
  );

  my $cv = AE::cv;

  $cluster->subscribe(
    id          => 'foo',
    destination => '/queue/foo',

    { on_receipt => sub {
        my $err = $_[1];

        if ( defined $err ) {
          warn $err->message . "\n";
          $cv->send;

          return;
        }

        $cluster->send(
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

AnyEvent::Stomper::Cluster is the client for the cluster of STOMP servers.

=head1 CONSTRUCTOR

=head2 new( %params )

  my $cluster = AnyEvent::Stomper::Cluster->new(
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

AnyEvent::Stomper::Cluster has same constructor parameters as
L<AnyEvent::Stomper>, and few more parameters listed below.

=over

=item nodes => \@nodes

Specifies the list of nodes. Parameter should contain array of hashes. Each
hash should contain C<host> and C<port> elements.

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

=head1 COMMAND METHODS

See documentation on L<AnyEvent::Stomper> to learn how execute STOMP commands.

=head1 ERROR CODES

Every error object, passed to callback, contain error code, which can be used
for programmatic handling of errors. AnyEvent::Stomper::Cluster provides
constants for error codes. They can be imported and used in expressions.

  use AnyEvent::Stomper::Cluster qw( :err_codes );

Full list of error codes see in documentation on L<AnyEvent::Stomper>.

=head1 OTHER METHODS

=head2 get( $host, $port )

Gets node by host and port.

=head2 nodes()

Gets all available nodes.

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
